param(
    [ValidateSet("start", "stop", "restart", "status", "logs", "build", "health")]
    [string]$Command = "start",
    [switch]$BuildOpenSearch,
    [switch]$BuildKoha,
    [switch]$Build,
    [switch]$NoFreshDb,
    [switch]$NoLogs,
    [switch]$NoDemoData,
    [switch]$WithDemoData
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Info([string]$Message) { Write-Host "[INFO ] $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "[ OK  ] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "[WARN ] $Message" -ForegroundColor Yellow }
function Fail([string]$Message) { throw $Message }

function Get-EnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Key,
        [string]$Default = ""
    )

    if (-not (Test-Path $FilePath)) {
        return $Default
    }

    $line = Get-Content -Path $FilePath |
        Where-Object { $_ -match "^\s*$Key\s*=" } |
        Select-Object -First 1

    if (-not $line) {
        return $Default
    }

    $value = ($line -split "=", 2)[1].Trim()
    $value = $value.Trim('"').Trim("'")
    return $value
}

function Invoke-Compose {
    param(
        [Parameter(Mandatory = $true)][string]$ComposeFile,
        [Parameter(Mandatory = $true)][string]$EnvFile,
        [Parameter(Mandatory = $true)][string]$ProjectDir,
        [Parameter(Mandatory = $true)][string[]]$ComposeArgs
    )

    # PS 5.1 can occasionally bind remaining arguments as a single string (e.g. "up -d").
    # Normalize that case so Docker always receives distinct tokens.
    $normalizedComposeArgs = @()
    if ($ComposeArgs.Count -eq 1 -and $ComposeArgs[0] -match "\s") {
        $normalizedComposeArgs = $ComposeArgs[0] -split "\s+" | Where-Object { $_ -ne "" }
    }
    else {
        $normalizedComposeArgs = $ComposeArgs
    }

    & docker compose -f $ComposeFile --env-file $EnvFile --project-directory $ProjectDir @normalizedComposeArgs
    if ($LASTEXITCODE -ne 0) {
        $commandSuffix = ($normalizedComposeArgs -join ' ')
        if (-not $commandSuffix) {
            $commandSuffix = "<no compose subcommand provided>"
        }
        Fail "docker compose failed ($ComposeFile): $commandSuffix"
    }
}

function Invoke-KohaCompose {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$ComposeArgs
    )

    Invoke-Compose -ComposeFile $script:KohaComposeFile -EnvFile $script:KohaEnvFile -ProjectDir $script:RepoRoot -ComposeArgs $ComposeArgs
}

function Invoke-OpenSearchCompose {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$ComposeArgs
    )

    Invoke-Compose -ComposeFile $script:OpenSearchComposeFile -EnvFile $script:OpenSearchEnvFile -ProjectDir $script:OpenSearchDir -ComposeArgs $ComposeArgs
}

function Invoke-TraefikCompose {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$ComposeArgs
    )

    Invoke-Compose -ComposeFile $script:TraefikComposeFile -EnvFile $script:TraefikEnvFile -ProjectDir $script:TraefikDir -ComposeArgs $ComposeArgs
}

function Ensure-FrontendNetwork {
    $networkNames = (& docker network ls --format "{{.Name}}")
    if ($LASTEXITCODE -ne 0) {
        Fail "Failed to list Docker networks."
    }

    if ($networkNames -notcontains "frontend") {
        Write-Info "Creating Docker network 'frontend'..."
        & docker network create frontend 1>$null
        if ($LASTEXITCODE -ne 0) {
            Fail "Failed to create Docker network 'frontend'."
        }
        Write-Ok "Network 'frontend' created."
    }
    else {
        Write-Ok "Network 'frontend' already exists."
    }
}

function Wait-OpenSearchGreen {
    param(
        [string]$Password,
        [int]$MaxAttempts = 72,
        [int]$DelaySeconds = 5
    )

    Write-Info "Waiting for OpenSearch cluster status to become green..."

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $raw = & docker exec os01 curl -ks --fail --cert /usr/share/opensearch/config/admin.pem --key /usr/share/opensearch/config/admin-key.pem "https://os01:9200/_cluster/health"
        if ($LASTEXITCODE -eq 0 -and $raw) {
            try {
                $health = $raw | ConvertFrom-Json
                if ($health.status -eq "green") {
                    Write-Ok "OpenSearch cluster is green."
                    return
                }
            }
            catch {
                # Continue polling while JSON is not yet stable.
            }
        }

        Write-Host ("  attempt {0}/{1}..." -f $attempt, $MaxAttempts)
        Start-Sleep -Seconds $DelaySeconds
    }

    Fail "OpenSearch did not reach green status in time."
}

function Get-DbRootPassword {
    param(
        [string]$DbContainer
    )

    return $script:DbRootPassword
}

function Get-DbRootMysqlArgs {
    param(
        [string]$DbContainer
    )

    $password = Get-DbRootPassword -DbContainer $DbContainer
    if (-not [string]::IsNullOrWhiteSpace($password)) {
        & docker exec $DbContainer mysql -uroot "-p$password" -Nse "SELECT 1" 1>$null 2>$null
        if ($LASTEXITCODE -eq 0) {
            return @("-uroot", "-p$password")
        }
    }

    & docker exec $DbContainer mysql -uroot -Nse "SELECT 1" 1>$null 2>$null
    if ($LASTEXITCODE -eq 0) {
        return @("-uroot")
    }

    return @()
}

function Wait-DbReady {
    param(
        [string]$DbContainer,
        [int]$MaxAttempts = 30,
        [int]$DelaySeconds = 2
    )

    Write-Info "Waiting for MariaDB in '$DbContainer'..."

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $rootArgs = Get-DbRootMysqlArgs -DbContainer $DbContainer
        if ($rootArgs.Count -gt 0) {
            Write-Ok "MariaDB is ready."
            return
        }

        Write-Host ("  attempt {0}/{1}..." -f $attempt, $MaxAttempts)
        Start-Sleep -Seconds $DelaySeconds
    }

    Fail "MariaDB did not become ready in time."
}

function Reset-KohaDatabase {
    param(
        [string]$DbContainer,
        [string]$DbName,
        [string]$DbUser
    )

    Write-Info "Resetting database '$DbName'..."

    $sql = @"
DROP DATABASE IF EXISTS $DbName;
CREATE DATABASE $DbName CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON $DbName.* TO '$DbUser'@'%';
FLUSH PRIVILEGES;
"@

    $rootArgs = Get-DbRootMysqlArgs -DbContainer $DbContainer
    if ($rootArgs.Count -eq 0) {
        Fail "Could not authenticate as MariaDB root user."
    }

    $sql | & docker exec -i $DbContainer mysql @rootArgs
    if ($LASTEXITCODE -ne 0) {
        Fail "Failed to reset database '$DbName'."
    }

    Write-Ok "Database '$DbName' is ready."
}

function Show-Status {
    Write-Host ""
    Write-Host "Koha stack:"
    Invoke-KohaCompose @("ps")
    Write-Host ""

    Write-Host "OpenSearch stack:"
    Invoke-OpenSearchCompose @("ps")
    Write-Host ""

    Write-Host "Traefik stack:"
    Invoke-TraefikCompose @("ps")
    Write-Host ""

    Write-Host "OpenSearch cluster health:"
    $raw = & docker exec os01 curl -ks --fail --cert /usr/share/opensearch/config/admin.pem --key /usr/share/opensearch/config/admin-key.pem "https://os01:9200/_cluster/health"
    if ($LASTEXITCODE -eq 0 -and $raw) {
        try {
            $health = $raw | ConvertFrom-Json
            $health | Format-List | Out-String | Write-Host
        }
        catch {
            Write-Warn "Could not parse health JSON. Raw output:"
            Write-Host $raw
        }
    }
    else {
        Write-Warn "OpenSearch cluster health endpoint is unreachable."
    }
}

function Invoke-HealthCheck {
    $counts = @{ pass = 0; fail = 0 }

    $Check = {
        param([string]$Label, [scriptblock]$Test)
        try {
            $ok = & $Test
            if ($ok) {
                Write-Host ("  [ PASS ] {0}" -f $Label) -ForegroundColor Green
                $counts.pass++
            } else {
                Write-Host ("  [ FAIL ] {0}" -f $Label) -ForegroundColor Red
                $counts.fail++
            }
        } catch {
            Write-Host ("  [ FAIL ] {0} ({1})" -f $Label, $_.Exception.Message) -ForegroundColor Red
            $counts.fail++
        }
    }

    Write-Host ""
    Write-Host "Health check" -ForegroundColor Cyan
    Write-Host "------------"

    & $Check "Docker 'frontend' network exists" {
        $names = & docker network ls --format "{{.Name}}" 2>$null
        $names -contains "frontend"
    }

    & $Check "OpenSearch os01 container healthy" {
        $state = & docker inspect --format "{{.State.Health.Status}}" os01 2>$null
        $state -eq "healthy"
    }

    & $Check "OpenSearch cluster status green" {
        $raw = & docker exec os01 curl -ks --fail `
            --cert  /usr/share/opensearch/config/admin.pem `
            --key   /usr/share/opensearch/config/admin-key.pem `
            --cacert /usr/share/opensearch/config/root-ca.pem `
            "https://os01:9200/_cluster/health" 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $raw) { return $false }
        ($raw | ConvertFrom-Json).status -eq "green"
    }

    & $Check "Traefik container running" {
        $state = & docker inspect --format "{{.State.Status}}" traefik 2>$null
        $state -eq "running"
    }

    & $Check "MariaDB container running" {
        $state = & docker inspect --format "{{.State.Status}}" $script:DbContainer 2>$null
        $state -eq "running"
    }

    & $Check "MariaDB accepting connections" {
        (Get-DbRootMysqlArgs -DbContainer $script:DbContainer).Count -gt 0
    }

    & $Check "Memcached container running" {
        $name = "$($script:ProjectName)-memcached-1"
        $state = & docker inspect --format "{{.State.Status}}" $name 2>$null
        $state -eq "running"
    }

    & $Check "Koha container running" {
        $name = "$($script:ProjectName)-koha-1"
        $state = & docker inspect --format "{{.State.Status}}" $name 2>$null
        $state -eq "running"
    }

    & $Check "Koha OPAC responds HTTP 200" {
        $code = & curl.exe -s -o NUL -w "%{http_code}" --max-time 10 "http://localhost:8080" 2>$null
        $code -eq "200"
    }

    Write-Host ""
    if ($counts.fail -eq 0) {
        Write-Host ("All {0} checks passed." -f $counts.pass) -ForegroundColor Green
    } else {
        Write-Host ("{0} passed, {1} failed." -f $counts.pass, $counts.fail) -ForegroundColor Yellow
    }
    Write-Host ""
}

function Print-Urls {
    $publicPortSuffix = if ($script:TraefikHttpPort -eq "80") { "" } else { ":$($script:TraefikHttpPort)" }
    Write-Host ""
    Write-Host "URLs:"
    Write-Host "  OPAC:      http://$($script:KohaInstance)$($script:KohaDomain)$publicPortSuffix"
    Write-Host "  Staff:     http://$($script:KohaInstance)$($script:KohaIntranetSuffix)$($script:KohaDomain)$publicPortSuffix"
    Write-Host "  Dashboards:http://dashboards.localhost$publicPortSuffix"
    Write-Host "  Traefik:   http://localhost:$($script:TraefikDashboardPort)"
    Write-Host ""
    Write-Host "Demo data mode: $($script:LoadDemoData)"
    Write-Host ""
}

function Start-FullStack {
    if ($BuildOpenSearch) {
        Write-Info "Building OpenSearch images..."
        Invoke-OpenSearchCompose @("build")
        Write-Ok "OpenSearch images built."
    }

    if ($BuildKoha) {
        Write-Info "Building Koha image..."
        Invoke-KohaCompose @("build", "koha")
        Write-Ok "Koha image built."
    }

    # The 'frontend' network must exist before OpenSearch compose runs because
    # the dashboards service declares it as external.
    Ensure-FrontendNetwork

    # Required order: OpenSearch first.
    Write-Info "Starting OpenSearch cluster (first)..."
    Invoke-OpenSearchCompose @("up", "-d")
    Write-Ok "OpenSearch containers started."
    Wait-OpenSearchGreen -Password $script:OpenSearchPassword

    Write-Info "Starting Traefik..."
    Invoke-TraefikCompose @("up", "-d", "traefik")
    Write-Ok "Traefik started."

    Write-Info "Starting MariaDB and Memcached..."
    Invoke-KohaCompose @("up", "-d", "db", "memcached")
    Write-Ok "Support services started."
    Wait-DbReady -DbContainer $script:DbContainer

    if (-not $NoFreshDb) {
        Reset-KohaDatabase -DbContainer $script:DbContainer -DbName $script:DbName -DbUser $script:DbUser
    }
    else {
        Write-Warn "Skipping DB reset due to -NoFreshDb."
    }

    Write-Info "Starting Koha container..."
    Invoke-KohaCompose @("up", "-d", "--force-recreate", "koha")
    Write-Ok "Koha container started."

    Print-Urls

    if (-not $NoLogs) {
        Write-Info "Tailing Koha logs (Ctrl+C to stop following logs)..."
        Invoke-KohaCompose @("logs", "-f", "koha")
    }
    else {
        Write-Ok "Startup completed without log tailing (-NoLogs)."
    }
}

function Restart-KohaQuick {
    Write-Info "Quick restart: OpenSearch is expected to already be up."
    Write-Info "Ensuring MariaDB and Memcached are running..."
    Invoke-KohaCompose @("up", "-d", "db", "memcached")
    Wait-DbReady -DbContainer $script:DbContainer

    if (-not $NoFreshDb) {
        Reset-KohaDatabase -DbContainer $script:DbContainer -DbName $script:DbName -DbUser $script:DbUser
    }
    else {
        Write-Warn "Skipping DB reset due to -NoFreshDb."
    }

    Write-Info "Recreating Koha container..."
    Invoke-KohaCompose @("up", "-d", "--force-recreate", "koha")
    Write-Ok "Koha container restarted."

    Print-Urls

    if (-not $NoLogs) {
        Write-Info "Tailing Koha logs (Ctrl+C to stop following logs)..."
        Invoke-KohaCompose @("logs", "-f", "koha")
    }
}

function Stop-All {
    Write-Info "Stopping Koha container..."
    Invoke-KohaCompose @("stop", "koha")
    Write-Info "Stopping MariaDB and Memcached..."
    Invoke-KohaCompose @("stop", "db", "memcached")
    Write-Info "Stopping OpenSearch cluster..."
    Invoke-OpenSearchCompose @("down")
    Write-Info "Stopping Traefik..."
    Invoke-TraefikCompose @("stop", "traefik")
    Write-Ok "All services stopped."
}

# Resolve core paths.
$RepoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$KohaComposeFile = Join-Path $RepoRoot "docker-compose.yml"
$KohaEnvFile = Join-Path $RepoRoot "env/.env"
$OpenSearchDir = Join-Path $RepoRoot "OpenSearch-3.6"
$OpenSearchComposeFile = Join-Path $OpenSearchDir "docker-compose.yml"
$OpenSearchEnvFile = Join-Path $OpenSearchDir ".env"
$TraefikDir = Join-Path $RepoRoot "traefik"
$TraefikComposeFile = Join-Path $TraefikDir "docker-compose.yaml"
$TraefikEnvFile = Join-Path $TraefikDir ".env"

# Input validation.
if ($NoDemoData -and $WithDemoData) {
    Fail "Use either -NoDemoData or -WithDemoData, not both."
}

if (($Command -eq "stop" -or $Command -eq "status" -or $Command -eq "logs") -and ($NoDemoData -or $WithDemoData -or $NoFreshDb)) {
    Write-Warn "Flags -NoDemoData, -WithDemoData and -NoFreshDb are ignored for command '$Command'."
}

if (-not (Test-Path $KohaComposeFile)) { Fail "Missing file: $KohaComposeFile" }
if (-not (Test-Path $KohaEnvFile)) { Fail "Missing file: $KohaEnvFile" }
if (-not (Test-Path $OpenSearchComposeFile)) { Fail "Missing file: $OpenSearchComposeFile" }
if (-not (Test-Path $OpenSearchEnvFile)) { Fail "Missing file: $OpenSearchEnvFile" }
if (-not (Test-Path $TraefikComposeFile)) { Fail "Missing file: $TraefikComposeFile" }
if (-not (Test-Path $TraefikEnvFile)) { Fail "Missing file: $TraefikEnvFile" }

Get-Command docker -ErrorAction Stop | Out-Null
& docker compose version 1>$null
if ($LASTEXITCODE -ne 0) {
    Fail "Docker Compose plugin is not available."
}

# Build options.
if ($Build) {
    $BuildOpenSearch = $true
    $BuildKoha = $true
}

# Resolve runtime values from env files.
$KohaInstance = Get-EnvValue -FilePath $KohaEnvFile -Key "KOHA_INSTANCE" -Default "kohadev"
$KohaDomain = Get-EnvValue -FilePath $KohaEnvFile -Key "KOHA_DOMAIN" -Default ".127.0.0.1.nip.io"
$KohaIntranetSuffix = Get-EnvValue -FilePath $KohaEnvFile -Key "KOHA_INTRANET_SUFFIX" -Default "-intra"
$KohaPublicPort = Get-EnvValue -FilePath $KohaEnvFile -Key "KOHA_PUBLIC_PORT" -Default "80"
$TraefikHttpPort = Get-EnvValue -FilePath $TraefikEnvFile -Key "TRAEFIK_HTTP_PORT" -Default "80"
$TraefikDashboardPort = Get-EnvValue -FilePath $TraefikEnvFile -Key "TRAEFIK_DASHBOARD_PORT" -Default "8083"
$OpenSearchPassword = Get-EnvValue -FilePath $OpenSearchEnvFile -Key "OPENSEARCH_INITIAL_ADMIN_PASSWORD" -Default ""
if ([string]::IsNullOrWhiteSpace($OpenSearchPassword)) {
    $OpenSearchPassword = Get-EnvValue -FilePath $KohaEnvFile -Key "OPENSEARCH_INITIAL_ADMIN_PASSWORD" -Default ""
}
if ([string]::IsNullOrWhiteSpace($OpenSearchPassword)) {
    Fail "OPENSEARCH_INITIAL_ADMIN_PASSWORD is missing in OpenSearch-3.6/.env and env/.env"
}

$SyncRepo = Get-EnvValue -FilePath $KohaEnvFile -Key "SYNC_REPO" -Default ""
if ([string]::IsNullOrWhiteSpace($SyncRepo) -or -not (Test-Path $SyncRepo)) {
    Fail "SYNC_REPO path does not exist: '$SyncRepo'. Clone Koha there before starting."
}

$OpenSearchCaCert = Get-EnvValue -FilePath $KohaEnvFile -Key "OPENSEARCH_CA_CERT" -Default ""
if ([string]::IsNullOrWhiteSpace($OpenSearchCaCert) -or -not (Test-Path $OpenSearchCaCert)) {
    Fail "OPENSEARCH_CA_CERT path does not exist: '$OpenSearchCaCert'. Generate certs first in OpenSearch-3.6."
}

$DbName = "koha_$KohaInstance"
$DbUser = "koha_$KohaInstance"
$DbRootPassword = Get-EnvValue -FilePath $KohaEnvFile -Key "KOHA_DB_ROOT_PASSWORD" -Default "password"
$ProjectName = Split-Path -Path $RepoRoot -Leaf
$DbContainer = "$ProjectName-db-1"

$LoadDemoData = Get-EnvValue -FilePath $KohaEnvFile -Key "LOAD_DEMO_DATA" -Default "yes"
if ($NoDemoData) { $LoadDemoData = "no" }
if ($WithDemoData) { $LoadDemoData = "yes" }
$env:LOAD_DEMO_DATA = $LoadDemoData

Write-Host ""
Write-Host "============================================="
Write-Host "  Koha + OpenSearch Windows Stack Manager"
Write-Host "============================================="
Write-Host ""

switch ($Command) {
    "start" {
        Start-FullStack
    }
    "stop" {
        Stop-All
    }
    "restart" {
        Restart-KohaQuick
    }
    "status" {
        Show-Status
    }
    "logs" {
        Write-Info "Tailing Koha logs (Ctrl+C to stop following logs)..."
        Invoke-KohaCompose @("logs", "-f", "koha")
    }
    "health" {
        Invoke-HealthCheck
    }
    "build" {
        if (-not $BuildOpenSearch -and -not $BuildKoha) {
            $BuildOpenSearch = $true
            $BuildKoha = $true
        }
        if ($BuildOpenSearch) {
            Write-Info "Building OpenSearch images..."
            Invoke-OpenSearchCompose @("build")
            Write-Ok "OpenSearch images built."
        }
        if ($BuildKoha) {
            Write-Info "Building Koha image..."
            Invoke-KohaCompose @("build", "koha")
            Write-Ok "Koha image built."
        }
    }
}
