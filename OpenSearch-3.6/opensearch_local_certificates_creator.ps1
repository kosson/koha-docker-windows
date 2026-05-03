param(
    [string]$ConfigFile = "opensearch_installer_vars.cfg"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Info([string]$Message) { Write-Host "[INFO ] $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "[ OK  ] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "[WARN ] $Message" -ForegroundColor Yellow }

$script:OpenSslCommand = $null
$script:IsWindowsPlatform = $env:OS -eq "Windows_NT"

function Resolve-PathFromScript {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$ScriptDir
    )

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $ScriptDir $PathValue))
}

function Read-SimpleConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Config file not found: $Path"
    }

    $map = @{}

    foreach ($line in (Get-Content -Path $Path)) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }

        if ($trimmed -notmatch "^([A-Za-z_][A-Za-z0-9_]*)=(.*)$") {
            continue
        }

        $key = $matches[1]
        $value = $matches[2].Trim()

        if (
            ($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))
        ) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        $map[$key] = $value
    }

    return $map
}

function Invoke-OpenSsl {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    & $script:OpenSslCommand @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "OpenSSL failed: $script:OpenSslCommand $($Arguments -join ' ')"
    }
}

function Resolve-OpenSslCommand {
    $command = Get-Command openssl -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    if ($script:IsWindowsPlatform) {
        $windowsCandidates = @(
            (Join-Path ${env:ProgramFiles} "Git\usr\bin\openssl.exe"),
            (Join-Path ${env:ProgramFiles} "Git\mingw64\bin\openssl.exe"),
            (Join-Path ${env:ProgramFiles} "OpenSSL-Win64\bin\openssl.exe"),
            (Join-Path ${env:ProgramFiles(x86)} "OpenSSL-Win32\bin\openssl.exe")
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        foreach ($candidate in $windowsCandidates) {
            if (Test-Path $candidate) {
                return $candidate
            }
        }
    }

    throw "OpenSSL was not found. Install OpenSSL or Git for Windows, or add openssl.exe to PATH."
}

function Get-DisplayPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        return [System.IO.Path]::GetRelativePath((Get-Location).Path, $Path)
    }
    catch {
        return $Path
    }
}

function New-RandomAlnum {
    param([int]$Length)

    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    $bytes = New-Object byte[] ($Length * 2)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $result = New-Object System.Text.StringBuilder

        while ($result.Length -lt $Length) {
            $rng.GetBytes($bytes)
            foreach ($b in $bytes) {
                $result.Append($chars[$b % $chars.Length]) | Out-Null
                if ($result.Length -ge $Length) {
                    break
                }
            }
        }

        return $result.ToString()
    }
    finally {
        $rng.Dispose()
    }
}

function New-RandomHex {
    param([int]$ByteLength)

    $bytes = New-Object byte[] $ByteLength
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $rng.GetBytes($bytes)
        return -join ($bytes | ForEach-Object { $_.ToString("x2") })
    }
    finally {
        $rng.Dispose()
    }
}

function Update-OrAppendYamlSetting {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$ValueWithQuotes
    )

    $content = Get-Content -Path $FilePath
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*:'
    $replacementLine = "{0}: {1}" -f $Key, $ValueWithQuotes

    $matched = $false
    for ($i = 0; $i -lt $content.Count; $i++) {
        if ($content[$i] -match $pattern) {
            $content[$i] = $replacementLine
            $matched = $true
            break
        }
    }

    if (-not $matched) {
        $content += $replacementLine
    }

    Set-Content -Path $FilePath -Value $content -Encoding utf8
}

function Protect-FilesBestEffort {
    param(
        [Parameter(Mandatory = $true)][string]$SslDir,
        [Parameter(Mandatory = $true)][string]$ConfigBase,
        [Parameter(Mandatory = $true)][string]$PerfDir
    )

    if ($script:IsWindowsPlatform) {
        # Windows ACLs differ from chmod; keep this best-effort to avoid over-restricting shared repos.
        $pemFiles = Get-ChildItem -Path $SslDir -Filter "*.pem" -File -ErrorAction SilentlyContinue
        foreach ($file in $pemFiles) {
            try {
                & icacls $file.FullName /inheritance:r 1>$null 2>$null
                & icacls $file.FullName /grant:r "${env:USERNAME}:(R,W)" 1>$null 2>$null
            }
            catch {
                Write-Warn "Could not update ACL for $($file.FullName): $($_.Exception.Message)"
            }
        }
        Write-Ok "Best-effort ACL update applied for PEM files on Windows."
        return
    }

    # Unix-like fallback for PowerShell Core on Linux/macOS.
    Get-ChildItem -Path $SslDir -Filter "*.pem" -File -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object { & chmod 600 $_.FullName }

    Get-ChildItem -Path $ConfigBase -Directory -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object { & chmod 700 $_.FullName }

    Get-ChildItem -Path $ConfigBase -File -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object { & chmod 600 $_.FullName }

    if (Test-Path $PerfDir) {
        Get-ChildItem -Path $PerfDir -File -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object { & chmod 600 $_.FullName }
    }

    Write-Ok "File permissions set (certs: 600, config dirs: 700, config files: 600)."
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Resolve-PathFromScript -PathValue $ConfigFile -ScriptDir $scriptDir

Write-Info "Loading config: $configPath"
$config = Read-SimpleConfig -Path $configPath

foreach ($required in @("CERT_DN", "LOCAL_ROOT_CA", "ADMIN_CA", "OS_CERTS_PATH")) {
    if (-not $config.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($config[$required])) {
        throw "Missing required config value: $required"
    }
}

$script:OpenSslCommand = Resolve-OpenSslCommand
Write-Info "Using OpenSSL: $(Get-DisplayPath -Path $script:OpenSslCommand)"

$certDn = $config["CERT_DN"]
$localRootCa = $config["LOCAL_ROOT_CA"]
$adminCa = $config["ADMIN_CA"]
$osCertsPath = Resolve-PathFromScript -PathValue $config["OS_CERTS_PATH"] -ScriptDir $scriptDir
$configBase = Join-Path $scriptDir "assets/opensearch/config"
$perfDir = Join-Path $scriptDir "assets/opensearch/performance-analyzer"

New-Item -Path $osCertsPath -ItemType Directory -Force | Out-Null

$rootCaKey = Join-Path $osCertsPath "root-ca-key.pem"
$rootCaPem = Join-Path $osCertsPath "root-ca.pem"

Write-Info "Creating root CA key and certificate..."
Invoke-OpenSsl -Arguments @("genrsa", "-out", $rootCaKey, "2048")
Invoke-OpenSsl -Arguments @("req", "-new", "-x509", "-sha256", "-key", $rootCaKey, "-subj", "$certDn/CN=$localRootCa", "-out", $rootCaPem, "-days", "730")

$adminTempKey = Join-Path $osCertsPath "$adminCa-key-temp.pem"
$adminKey = Join-Path $osCertsPath "$adminCa-key.pem"
$adminCsr = Join-Path $osCertsPath "$adminCa.csr"
$adminPem = Join-Path $osCertsPath "$adminCa.pem"

Write-Info "Creating admin TLS certificate..."
Invoke-OpenSsl -Arguments @("genrsa", "-out", $adminTempKey, "2048")
Invoke-OpenSsl -Arguments @("pkcs8", "-inform", "PEM", "-outform", "PEM", "-in", $adminTempKey, "-topk8", "-nocrypt", "-v1", "PBE-SHA1-3DES", "-out", $adminKey)
Invoke-OpenSsl -Arguments @("req", "-new", "-key", $adminKey, "-subj", "$certDn/CN=$adminCa", "-out", $adminCsr)
Invoke-OpenSsl -Arguments @("x509", "-req", "-in", $adminCsr, "-CA", $rootCaPem, "-CAkey", $rootCaKey, "-CAcreateserial", "-sha256", "-out", $adminPem, "-days", "730")

$nodes = @("os01", "os02", "os03", "os04", "os05", "client", "dashboards")

foreach ($node in $nodes) {
    Write-Info "Creating TLS certificate for $node..."
    $tempKey = Join-Path $osCertsPath "$node-key-temp.pem"
    $nodeKey = Join-Path $osCertsPath "$node-key.pem"
    $csr = Join-Path $osCertsPath "$node.csr"
    $ext = Join-Path $osCertsPath "$node.ext"
    $nodePem = Join-Path $osCertsPath "$node.pem"

    Invoke-OpenSsl -Arguments @("genrsa", "-out", $tempKey, "2048")
    Invoke-OpenSsl -Arguments @("pkcs8", "-inform", "PEM", "-outform", "PEM", "-in", $tempKey, "-topk8", "-nocrypt", "-v1", "PBE-SHA1-3DES", "-out", $nodeKey)
    Invoke-OpenSsl -Arguments @("req", "-new", "-key", $nodeKey, "-subj", "$certDn/CN=$node", "-out", $csr)

    Set-Content -Path $ext -Value "subjectAltName=DNS:$node" -Encoding ascii

    Invoke-OpenSsl -Arguments @("x509", "-req", "-in", $csr, "-CA", $rootCaPem, "-CAkey", $rootCaKey, "-CAcreateserial", "-sha256", "-out", $nodePem, "-days", "730", "-extfile", $ext)

    Remove-Item -Path $tempKey, $csr, $ext -Force -ErrorAction SilentlyContinue
}

Remove-Item -Path $adminCsr, $adminTempKey, (Join-Path $osCertsPath "root-ca.srl") -Force -ErrorAction SilentlyContinue

# Keep generated values identical on all OpenSearch nodes.
$complianceSalt = New-RandomAlnum -Length 16
$sqlMasterKey = New-RandomHex -ByteLength 16

$nodeConfigFiles = Get-ChildItem -Path $configBase -Filter "opensearch.yml" -Recurse -File |
    Where-Object { $_.FullName -match "[\\/]os0[1-5][\\/]opensearch\.yml$" }

if (-not $nodeConfigFiles) {
    throw "Could not find node opensearch.yml files under $configBase"
}

foreach ($cfg in $nodeConfigFiles) {
    Update-OrAppendYamlSetting -FilePath $cfg.FullName -Key "plugins.security.compliance.salt" -ValueWithQuotes ('"' + $complianceSalt + '"')
    Update-OrAppendYamlSetting -FilePath $cfg.FullName -Key "plugins.query.datasources.encryption.masterkey" -ValueWithQuotes ('"' + $sqlMasterKey + '"')
}

Write-Ok "Compliance salt and SQL master key written to all node configs."
Write-Host "  compliance salt : $complianceSalt"
Write-Host "  SQL master key  : $sqlMasterKey"
Write-Host "Store these values securely; they are required to restore the cluster."

Protect-FilesBestEffort -SslDir $osCertsPath -ConfigBase $configBase -PerfDir $perfDir
Write-Ok "Certificate generation completed."
