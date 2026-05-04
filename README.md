# koha-docker-windows

Windows-first Koha development stack with Docker Desktop, MariaDB, Traefik, and OpenSearch 3.6.

## Scope

- This repository is the Windows-adapted fork of the original Linux-focused project.
- Primary workflow: PowerShell.
- Linux scripts are kept only for compatibility.

## Prerequisites

- Docker Desktop (Linux containers mode)
- PowerShell 5.1+
- Git for Windows
- WSL installed (see: https://docs.docker.com/desktop/features/wsl/) needed by the Docker Desktop.

Notes:

- The OpenSearch certificate generator auto-detects `openssl.exe` from common Git for Windows locations.
- OpenSSL in PATH is optional.
- For Docker you need at least 8Gb of RAM, a 64bit processor with at least four cores (8 threads), at least 20Gb of HDD/SSD, and virtualization activated in BIOS/EFI to avoid errors described in the following online document: https://docs.docker.com/desktop/troubleshoot-and-support/troubleshoot/topics/#docker-desktop-fails-due-to-virtualization-not-working.

Check tools:

```powershell
git --version
docker --version
docker compose version
wsl --version
```

If you do not have WSL install it with `wsl --install`. If you have it, update it: `wsl --update`.

Optional check:

```powershell
openssl version
```

## Quick start

1. Clone Koha source in the repository root:

```powershell
git clone --depth=1 https://git.koha-community.org/Koha-community/Koha.git koha
```

2. Configure Windows host paths in env/.env:

```env
DOCKER_BINARY=docker
SYNC_REPO=C:/Users/nicolaie/Documents/DEVELOPMENT/koha-docker-windows/koha
OPENSEARCH_CA_CERT=C:/Users/nicolaie/Documents/DEVELOPMENT/koha-docker-windows/OpenSearch-3.6/assets/ssl/root-ca.pem
```

3. Generate OpenSearch certificates:

Set execution policy for the current user:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Then run:

```powershell
cd .\OpenSearch-3.6
.\opensearch_local_certificates_creator.ps1
cd ..
```

4. Start the full stack:

```powershell
.\stack-windows.ps1 start
```

Tip: use `-NoLogs` if you do not want log tailing after startup.

## Lifecycle commands

From repository root:

```powershell
.\stack-windows.ps1 start
.\stack-windows.ps1 stop
.\stack-windows.ps1 restart
.\stack-windows.ps1 status
.\stack-windows.ps1 logs
.\stack-windows.ps1 build
```

Useful flags:

```powershell
.\stack-windows.ps1 start -Build
.\stack-windows.ps1 start -BuildOpenSearch
.\stack-windows.ps1 start -BuildKoha
.\stack-windows.ps1 start -NoFreshDb
.\stack-windows.ps1 start -NoLogs
.\stack-windows.ps1 start -NoDemoData
.\stack-windows.ps1 restart -WithDemoData
```

## Startup order

The Windows manager enforces this sequence:

1. OpenSearch cluster
2. Traefik
3. MariaDB + Memcached
4. Koha

It also:

- Ensures the external Docker network `frontend` exists before startup.
- Waits for OpenSearch green cluster health.
- Waits for MariaDB readiness before Koha launch.

## Default URLs

- OPAC: http://kohadev.127.0.0.1.nip.io
- Staff: http://kohadev-intra.127.0.0.1.nip.io
- Dashboards: http://dashboards.localhost
- Traefik dashboard: http://localhost:8083
- OpenSearch API: https://localhost:9200

## Linux compatibility

The following scripts remain for compatibility only:

- stack.sh
- OpenSearch-3.6/opensearch_local_certificates_creator.sh

Use PowerShell equivalents for normal operation in this fork.

## Troubleshooting

### Common checks

- `SYNC_REPO` missing:
  - Verify env/.env points to an existing Koha checkout.
- `OPENSEARCH_CA_CERT` missing:
  - Re-run `OpenSearch-3.6/opensearch_local_certificates_creator.ps1`.
- OpenSearch not green:

```powershell
docker compose -f .\OpenSearch-3.6\docker-compose.yml --env-file .\OpenSearch-3.6\.env logs
```

### Koha container is not working

1. Check runtime state

```powershell
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
```

2. Read Koha logs

```powershell
docker logs --tail 200 koha-docker-windows-koha-1
```

3. Check dependency status

```powershell
.\stack-windows.ps1 status
docker compose -f .\OpenSearch-3.6\docker-compose.yml --env-file .\OpenSearch-3.6\.env ps
```

### Known Windows issue: CRLF line endings in shell/config files

Symptoms in Koha logs:

- `/kohadevbox/run.sh: line 2: $'\r': command not found`
- `/etc/default/koha-common: line N: $'\r': command not found`
- `/etc/koha/koha-sites.conf: line N: $'\r': command not found`

Cause:

- Linux container shell/config files fail when content is copied with Windows CRLF endings.

Repository fixes:

- The Koha image build now normalizes `/kohadevbox/run.sh` and template files to LF.
- Startup script normalization also cleans copied Koha helper/config shell files before `koha-create`.

If you still see this after old image cache, rebuild and restart:

```powershell
.\stack-windows.ps1 start -BuildKoha -NoLogs
```

### Fast recovery sequence

```powershell
.\stack-windows.ps1 stop
.\stack-windows.ps1 start -BuildKoha -NoLogs
.\stack-windows.ps1 status
```
