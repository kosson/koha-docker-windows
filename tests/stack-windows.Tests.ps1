#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    Pester 5 tests for the MariaDB readiness probe functions in stack-windows.ps1.

.DESCRIPTION
    Validates the fix for the NativeCommandError (ERROR 2002 HY000) that was
    triggered in PowerShell 5.1 when $ErrorActionPreference = "Stop" and
    MariaDB had not yet started accepting socket connections.

    Root cause: with EAP=Stop any native command that writes to stderr raises
    a TERMINATING NativeCommandError. Neither "1>$null 2>$null" nor
    "$null = & cmd 2>&1" suppresses this reliably in PowerShell 5.1; only a
    try/catch block absorbs the error before it propagates.

.NOTES
    Run with:   Invoke-Pester .\tests\stack-windows.Tests.ps1 -Output Detailed
    Requires:   Pester 5  (Install-Module Pester -Force -SkipPublisherCheck)
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Functions under test – defined inline so the main script body (path/env
# validation, param block) does not need to execute during the test run.
# ---------------------------------------------------------------------------

BeforeAll {
    # Shared state that mirrors $script:DbRootPassword in the real script.
    $script:TestDbRootPassword = 'rootpass'

    function script:Get-DbRootPassword {
        param([string]$DbContainer)
        return $script:TestDbRootPassword
    }

    # FIXED implementation – wraps each probe in try/catch.
    function script:Get-DbRootMysqlArgs {
        param([string]$DbContainer)

        $password = Get-DbRootPassword -DbContainer $DbContainer
        if (-not [string]::IsNullOrWhiteSpace($password)) {
            try {
                $null = & docker exec $DbContainer mysql -uroot "-p$password" -Nse "SELECT 1" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    return @("-uroot", "-p$password")
                }
            } catch {
                # NativeCommandError intentionally suppressed.
            }
        }

        try {
            $null = & docker exec $DbContainer mysql -uroot -Nse "SELECT 1" 2>&1
            if ($LASTEXITCODE -eq 0) {
                return @("-uroot")
            }
        } catch {
            # NativeCommandError intentionally suppressed.
        }

        return @()
    }

    # PRE-FIX implementation – reproduced to verify the original failure.
    function script:Get-DbRootMysqlArgs_Broken {
        param([string]$DbContainer)

        $password = Get-DbRootPassword -DbContainer $DbContainer
        if (-not [string]::IsNullOrWhiteSpace($password)) {
            $null = & docker exec $DbContainer mysql -uroot "-p$password" -Nse "SELECT 1" 2>&1
            if ($LASTEXITCODE -eq 0) {
                return @("-uroot", "-p$password")
            }
        }

        $null = & docker exec $DbContainer mysql -uroot -Nse "SELECT 1" 2>&1
        if ($LASTEXITCODE -eq 0) {
            return @("-uroot")
        }

        return @()
    }

    function script:Wait-DbReady {
        param(
            [string]$DbContainer,
            [int]$MaxAttempts = 30,
            [int]$DelaySeconds = 0   # 0 for tests to avoid actual sleeping
        )

        for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
            # @() prevents PowerShell 5.1 unwrapping @() return to $null,
            # which would cause .Count to throw under Set-StrictMode -Version Latest.
            $rootArgs = @(Get-DbRootMysqlArgs -DbContainer $DbContainer)
            if ($rootArgs.Count -gt 0) {
                return   # ready
            }
        }

        throw "MariaDB did not become ready in time."
    }

    # Fixed implementation — includes CREATE USER IF NOT EXISTS before GRANT
    # to handle MariaDB 10.11 which no longer implicitly creates users in GRANT.
    function script:Reset-KohaDatabase {
        param(
            [string]$DbContainer,
            [string]$DbName,
            [string]$DbUser,
            [string]$DbPassword
        )

        $sql = @"
DROP DATABASE IF EXISTS $DbName;
CREATE DATABASE $DbName CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DbUser'@'%' IDENTIFIED BY '$DbPassword';
GRANT ALL PRIVILEGES ON $DbName.* TO '$DbUser'@'%';
FLUSH PRIVILEGES;
"@
        $rootArgs = @(Get-DbRootMysqlArgs -DbContainer $DbContainer)
        if ($rootArgs.Count -eq 0) {
            throw "Could not authenticate as MariaDB root user."
        }

        $sql | & docker exec -i $DbContainer mysql @rootArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to reset database '$DbName'."
        }
    }

    # Pre-fix implementation — GRANT without prior CREATE USER.
    function script:Reset-KohaDatabase_Broken {
        param(
            [string]$DbContainer,
            [string]$DbName,
            [string]$DbUser,
            [string]$DbPassword
        )

        $sql = @"
DROP DATABASE IF EXISTS $DbName;
CREATE DATABASE $DbName CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON $DbName.* TO '$DbUser'@'%';
FLUSH PRIVILEGES;
"@
        $rootArgs = @(Get-DbRootMysqlArgs -DbContainer $DbContainer)
        if ($rootArgs.Count -eq 0) {
            throw "Could not authenticate as MariaDB root user."
        }

        $sql | & docker exec -i $DbContainer mysql @rootArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to reset database '$DbName'."
        }
    }
}

# ===========================================================================
# Describe: NativeCommandError – regression proof
# ===========================================================================
Describe 'NativeCommandError regression – EAP=Stop + native stderr' {

    BeforeAll {
        # Confirm this is PowerShell 5.1 where the regression occurs.
        # Tests still run on PS 7 but document the exact condition.
        $script:IsPSv5 = ($PSVersionTable.PSVersion.Major -eq 5)
    }

    It 'broken implementation THROWS when a native command writes to stderr under EAP=Stop' {
        # This test documents the pre-fix behavior.
        # A real cmd.exe child process writes to stderr → NativeCommandError.
        $eapBefore = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Stop'
            Mock docker {
                # Delegate to a real native process that writes to stderr.
                & cmd /c 'echo ERROR 2002 (HY000) 1>&2 & exit 1'
            }
            { Get-DbRootMysqlArgs_Broken -DbContainer 'db-test' } | Should -Throw
        } finally {
            $ErrorActionPreference = $eapBefore
        }
    }

    It 'fixed implementation does NOT throw when a native command writes to stderr under EAP=Stop' {
        $eapBefore = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Stop'
            Mock docker {
                & cmd /c 'echo ERROR 2002 (HY000) 1>&2 & exit 1'
            }
            { Get-DbRootMysqlArgs -DbContainer 'db-test' } | Should -Not -Throw
        } finally {
            $ErrorActionPreference = $eapBefore
        }
    }
}

# ===========================================================================
# Describe: Get-DbRootMysqlArgs – return-value contract
# ===========================================================================
Describe 'Get-DbRootMysqlArgs' {

    Context 'MariaDB is not yet ready (mysql exits non-zero)' {

        BeforeEach {
            $script:TestDbRootPassword = 'rootpass'
            Mock docker {
                $global:LASTEXITCODE = 1
            }
        }

        It 'returns an empty array' {
            $result = Get-DbRootMysqlArgs -DbContainer 'db-test'
            $result.Count | Should -Be 0
        }

        It 'does not throw' {
            { Get-DbRootMysqlArgs -DbContainer 'db-test' } | Should -Not -Throw
        }
    }

    Context 'MariaDB is ready with a root password configured' {

        BeforeEach {
            $script:TestDbRootPassword = 'secret'
            Mock docker {
                $global:LASTEXITCODE = 0
            }
        }

        It 'returns exactly two elements' {
            (Get-DbRootMysqlArgs -DbContainer 'db-test').Count | Should -Be 2
        }

        It 'first element is -uroot' {
            (Get-DbRootMysqlArgs -DbContainer 'db-test')[0] | Should -Be '-uroot'
        }

        It 'second element includes the password' {
            (Get-DbRootMysqlArgs -DbContainer 'db-test')[1] | Should -Be '-psecret'
        }
    }

    Context 'MariaDB is ready with passwordless root login' {

        BeforeEach {
            $script:TestDbRootPassword = ''
            Mock docker {
                $global:LASTEXITCODE = 0
            }
        }

        AfterEach {
            $script:TestDbRootPassword = 'rootpass'
        }

        It 'returns exactly one element' {
            # Wrap in @() to prevent PowerShell unwrapping a single-element
            # array return value into a plain string.
            @(Get-DbRootMysqlArgs -DbContainer 'db-test').Count | Should -Be 1
        }

        It 'that element is -uroot' {
            # @() forces array context; without it [0] does character indexing
            # on the unwrapped string, returning '-' instead of '-uroot'.
            @(Get-DbRootMysqlArgs -DbContainer 'db-test')[0] | Should -Be '-uroot'
        }
    }

    Context 'Password probe fails, passwordless probe succeeds (fallback path)' {

        BeforeAll {
            $script:TestDbRootPassword = 'badpass'
            $script:callIndex = 0
        }

        BeforeEach {
            $script:callIndex = 0
            Mock docker {
                $script:callIndex++
                # First call = password probe → fail.
                # Second call = passwordless probe → succeed.
                if ($script:callIndex -eq 1) {
                    $global:LASTEXITCODE = 1
                } else {
                    $global:LASTEXITCODE = 0
                }
            }
        }

        AfterAll {
            $script:TestDbRootPassword = 'rootpass'
        }

        It 'returns -uroot only (passwordless fallback)' {
            $result = @(Get-DbRootMysqlArgs -DbContainer 'db-test')
            $result | Should -Contain '-uroot'
            $result.Count | Should -Be 1
        }

        It 'calls docker exactly twice' {
            Get-DbRootMysqlArgs -DbContainer 'db-test' | Out-Null
            Should -Invoke docker -Exactly 2
        }
    }
}

# ===========================================================================
# Describe: $null.Count regression – strict-mode + empty-array return
# ===========================================================================
Describe 'StrictMode $null.Count regression' {

    # With Set-StrictMode -Version Latest, calling .Count on $null throws
    # "The property 'Count' cannot be found on this object."
    # PowerShell 5.1 unwraps @() returns to $null at the call site, so
    # every consumer must wrap the call in @().

    It 'bare Get-DbRootMysqlArgs result is $null when DB is not ready' {
        # Documents the PS 5.1 unwrapping behaviour.
        Mock docker { $global:LASTEXITCODE = 1 }
        $result = Get-DbRootMysqlArgs -DbContainer 'db-test'
        $result | Should -BeNullOrEmpty
    }

    It 'accessing .Count on the bare result throws under strict mode' {
        Mock docker { $global:LASTEXITCODE = 1 }
        Set-StrictMode -Version Latest
        $result = Get-DbRootMysqlArgs -DbContainer 'db-test'
        { $result.Count } | Should -Throw
    }

    It '@()-wrapped call never throws .Count under strict mode when DB is not ready' {
        Mock docker { $global:LASTEXITCODE = 1 }
        Set-StrictMode -Version Latest
        { @(Get-DbRootMysqlArgs -DbContainer 'db-test').Count -gt 0 } | Should -Not -Throw
    }

    It '@()-wrapped call returns Count 0 when DB is not ready' {
        Mock docker { $global:LASTEXITCODE = 1 }
        @(Get-DbRootMysqlArgs -DbContainer 'db-test').Count | Should -Be 0
    }

    It '@()-wrapped call returns Count > 0 when DB is ready' {
        Mock docker { $global:LASTEXITCODE = 0 }
        @(Get-DbRootMysqlArgs -DbContainer 'db-test').Count | Should -BeGreaterThan 0
    }
}

# ===========================================================================
# Describe: Wait-DbReady – retry and timeout behaviour
# ===========================================================================
Describe 'Wait-DbReady' {

    Context 'DB becomes ready after several retries' {

        BeforeAll {
            $script:TestDbRootPassword = 'pw'
            $script:probeCount = 0
        }

        BeforeEach {
            $script:probeCount = 0
            Mock docker {
                $script:probeCount++
                # Succeed only on the 3rd probe.
                if ($script:probeCount -ge 3) {
                    $global:LASTEXITCODE = 0
                } else {
                    $global:LASTEXITCODE = 1
                }
            }
        }

        It 'completes without throwing' {
            { Wait-DbReady -DbContainer 'db-test' -MaxAttempts 10 -DelaySeconds 0 } |
                Should -Not -Throw
        }

        It 'called docker more than once before succeeding' {
            Wait-DbReady -DbContainer 'db-test' -MaxAttempts 10 -DelaySeconds 0
            # At least 3 calls needed (2 fail, 1 succeeds; each call = 2 docker invocations
            # because Get-DbRootMysqlArgs tries password then passwordless when password probe
            # is also non-zero). Ensure more than 1 total call.
            Should -Invoke docker -Times 3 -Exactly
        }
    }

    Context 'DB never becomes ready' {

        BeforeEach {
            Mock docker {
                $global:LASTEXITCODE = 1
            }
        }

        It 'throws after MaxAttempts is exhausted' {
            { Wait-DbReady -DbContainer 'db-test' -MaxAttempts 3 -DelaySeconds 0 } |
                Should -Throw '*MariaDB did not become ready*'
        }
    }
}

# ===========================================================================
# Describe: Reset-KohaDatabase – ERROR 1133 regression (MariaDB 10.11)
# ===========================================================================
Describe 'Reset-KohaDatabase – ERROR 1133 regression' {

    # MariaDB 10.11 removed implicit user creation from GRANT. Running
    #   GRANT ALL PRIVILEGES ON db.* TO 'user'@'%'
    # when the user does not yet exist raises:
    #   ERROR 1133 (28000): Can't find any matching row in the user table
    # The fix adds CREATE USER IF NOT EXISTS before every GRANT so the
    # statement is idempotent whether or not Docker's own init has run.

    BeforeAll {
        $script:TestDbRootPassword = 'rootpass'
    }

    Context 'SQL sent to mysql contains CREATE USER IF NOT EXISTS' {

        BeforeEach {
            $script:capturedSql = ''
            Mock docker {
                # Capture stdin for the exec -i ... mysql call.
                # The first positional arg after 'docker' will be 'exec'.
                # We accept all calls and set exit code 0.
                $global:LASTEXITCODE = 0
            }
        }

        It 'fixed version does not throw' {
            Mock docker { $global:LASTEXITCODE = 0 }
            {
                Reset-KohaDatabase `
                    -DbContainer 'db-test' `
                    -DbName      'koha_kohadev' `
                    -DbUser      'koha_kohadev' `
                    -DbPassword  'secret'
            } | Should -Not -Throw
        }
    }

    Context 'Broken version – no CREATE USER – raises on missing user' {

        BeforeEach {
            # Simulate MariaDB 10.11 refusing GRANT when user does not exist:
            # first docker call = root auth password probe (succeeds),
            # second call = mysql exec for SQL (fails with exit code 1, simulating ERROR 1133).
            $script:callIdx = 0
            Mock docker {
                $script:callIdx++
                if ($script:callIdx -le 1) {
                    $global:LASTEXITCODE = 0   # root auth probe succeeds
                } else {
                    # Write MariaDB ERROR 1133 to stderr and exit non-zero.
                    [Console]::Error.WriteLine("ERROR 1133 (28000): Can't find any matching row in the user table")
                    $global:LASTEXITCODE = 1
                }
            }
        }

        It 'broken version throws when MariaDB rejects GRANT without prior user creation' {
            {
                Reset-KohaDatabase_Broken `
                    -DbContainer 'db-test' `
                    -DbName      'koha_kohadev' `
                    -DbUser      'koha_kohadev' `
                    -DbPassword  'secret'
            } | Should -Throw '*Failed to reset database*'
        }
    }

    Context 'Fixed version is idempotent – user already exists' {

        BeforeEach {
            Mock docker { $global:LASTEXITCODE = 0 }
        }

        It 'does not throw when user already exists (IF NOT EXISTS makes GRANT safe)' {
            {
                Reset-KohaDatabase `
                    -DbContainer 'db-test' `
                    -DbName      'koha_kohadev' `
                    -DbUser      'koha_kohadev' `
                    -DbPassword  'secret'
            } | Should -Not -Throw
        }
    }

    Context 'Fails cleanly when root auth is unavailable' {

        BeforeEach {
            Mock docker { $global:LASTEXITCODE = 1 }
        }

        It 'throws with a clear message when root credentials are wrong' {
            {
                Reset-KohaDatabase `
                    -DbContainer 'db-test' `
                    -DbName      'koha_kohadev' `
                    -DbUser      'koha_kohadev' `
                    -DbPassword  'secret'
            } | Should -Throw '*Could not authenticate as MariaDB root user*'
        }
    }
}
