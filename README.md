# koha-docker-windows

This project is a derivation of the `https://github.com/kosson/koha-docker` repo. It was done for the use of those who use Windows as main development platform. Like the aforementioned repo took some very sound patterns and ideas from the work done with [koha-testing-docker (a.k.a. KTD)](https://gitlab.com/koha-community/koha-testing-docker).
All the heavy listing was done using AI agents via a Github subscription. Most of the avatars during development can be tracked if you look into the TRACKER.md file.

## Scope

Building a cluster of Docker containers that gives the possibility to work with Koha latest version. At the time of this repo initialization the verion is Koha 25.12.00. Koha needs a database (MariaDB), a caching mecanism (Memcache), an indexing engine (OpenSearch), and a proxy for accesing the instalation in the browser (Traefik).

## Prerequisites

You need to have a fairly well endowed computer to run these services. Only the RAM needs to be at lear 16Gb which is not that rare these days. You need to activate virtualization in BIOS so that some cores of your processors may be "borrowed" for the containers we raise for each of the components. Also, you need to have a good Internet connection.

- Docker Desktop (Linux containers mode)
- PowerShell 5.1+
- Git for Windows
- WSL installed (see: https://docs.docker.com/desktop/features/wsl/) needed by the Docker Desktop.

Notes:

- The OpenSearch certificate generator auto-detects `openssl.exe` from common Git for Windows (https://git-scm.com/install/windows) locations.
- OpenSSL in PATH is optional. The script will try and solve this automaticaly. Further down there a instructions on how you could install it by yourself if you want to.
- For Docker you need at least 8Gb of RAM, a 64bit processor with at least four cores (8 threads), at least 20Gb of HDD/SSD, and virtualization activated in BIOS/EFI to avoid errors described in the following online document: https://docs.docker.com/desktop/troubleshoot-and-support/troubleshoot/topics/#docker-desktop-fails-due-to-virtualization-not-working.

Check the needed tools if they are installed:

```powershell
git --version
docker --version
docker compose version
wsl --version
```

Every command from the listed above run in the PowerShell should yield the version of the installed package. Solve these requirements first. Copy every command on each line separately.
If you do not have WSL install it with `wsl --install`. If you have it, update it: `wsl --update`.

Optional check for OpenSSL. OpenSSL is very important being used in cryptographic keys generation (see OpenSearch):

```powershell
openssl version
```

If you don't have OpenSSL installed run in PowerShell (as Administrator) the following: `winget install --id=FireDaemon.OpenSSL -e`. Close PowerShel and open it again. Check for version. If no answer is given in the shell, then it needs to be added to the PATH. Run in the shell the following: `$Env:PATH += ";C:\Program Files\FireDaemon OpenSSL 3\bin"`.
OpenSSL is also part of the Git for Windows as mentioned prior.

Now, it is the time to install Docker Desktop if you haven't done that already - https://docs.docker.com/get-started/get-docker/.

## Quick start

1. Clone Koha source in the repository root. We need all the source code of Koha, so, being in the root folder of your project, run:

```powershell
git clone --depth=1 https://git.koha-community.org/Koha-community/Koha.git koha
```

2. Configure Windows host paths in env/.env. These settings are crucial, so track them in the .env file and put your own paths:

```env
DOCKER_BINARY=docker
SYNC_REPO=C:/Users/nicolaie/Documents/DEVELOPMENT/koha-docker-windows/koha
OPENSEARCH_CA_CERT=C:/Users/nicolaie/Documents/DEVELOPMENT/koha-docker-windows/OpenSearch-3.6/assets/ssl/root-ca.pem
```

For `SYNC_REPO`, the path should be the `koha` subfolder that was created at in the previous step.
For the `OPENSEARCH_CA_CERT` put the same path just in front of the ending sequence `/OpenSearch-3.6/assets/ssl/root-ca.pem`. Observerd that the file `root-ca.pem` referenced in the path might not exist at this stage. This is ok. It will be created in the following step.

Be very thorough with these paths. Double check everything.

3. Generate OpenSearch certificates:

Now, because OpenSearch needs a secure communication setup between its nodes, we need to create the cryptographic keys it uses. Set execution policy for the current user:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Then run the following commands separately (every command on each line in order):

```powershell
cd .\OpenSearch-3.6
.\opensearch_local_certificates_creator.ps1
cd ..
```

You should obtain in the PowerShell an output similar to the following:

```txt
[INFO ] Loading config: C:\Users\kosson\Documents\DEVELOPMENT\koha-docker-windows\OpenSearch-3.6\opensearch_installer_vars.cfg
[INFO ] Using OpenSSL: C:\Program Files\FireDaemon OpenSSL 4\bin\openssl.exe
[INFO ] Creating root CA key and certificate...
[INFO ] Creating admin TLS certificate...
Certificate request self-signature ok
subject=C=RO, ST=ILFOV, L=MAGURELE, O=NIPNE, OU=DFCTI, CN=admin
[INFO ] Creating TLS certificate for os01...
Certificate request self-signature ok
subject=C=RO, ST=ILFOV, L=MAGURELE, O=NIPNE, OU=DFCTI, CN=os01
[INFO ] Creating TLS certificate for os02...
Certificate request self-signature ok
subject=C=RO, ST=ILFOV, L=MAGURELE, O=NIPNE, OU=DFCTI, CN=os02
[INFO ] Creating TLS certificate for os03...
Certificate request self-signature ok
subject=C=RO, ST=ILFOV, L=MAGURELE, O=NIPNE, OU=DFCTI, CN=os03
[INFO ] Creating TLS certificate for os04...
Certificate request self-signature ok
subject=C=RO, ST=ILFOV, L=MAGURELE, O=NIPNE, OU=DFCTI, CN=os04
[INFO ] Creating TLS certificate for os05...
Certificate request self-signature ok
subject=C=RO, ST=ILFOV, L=MAGURELE, O=NIPNE, OU=DFCTI, CN=os05
[INFO ] Creating TLS certificate for client...
Certificate request self-signature ok
subject=C=RO, ST=ILFOV, L=MAGURELE, O=NIPNE, OU=DFCTI, CN=client
[INFO ] Creating TLS certificate for dashboards...
Certificate request self-signature ok
subject=C=RO, ST=ILFOV, L=MAGURELE, O=NIPNE, OU=DFCTI, CN=dashboards
[ OK  ] Compliance salt and SQL master key written to all node configs.
  compliance salt : xXwreFzh5RBczEIg
  SQL master key  : f329059be0f53cebbf51216af131561c
Store these values securely; they are required to restore the cluster.
[ OK  ] Best-effort ACL update applied for PEM files on Windows.
[ OK  ] Certificate generation completed.
```

Now, for every subfolder `OpenSearch-3.6./assets/opensearch/config/os01` ... to `os05` you have a configuration file named `opensearch.yml`. All of them have the exact same hard coded settings for the `plugins.security.nodes_dn option`. Modify them for your environment. These are only for test and development builds localized to the creator of this project. You should use it as is only to test. Modify it to adapt it to your institution. Also, the `plugins.security.compliance.salt` and `plugins.query.datasources.encryption.masterkey` values will be re-generated every time you run bash `.\opensearch_local_certificates_creator.ps1`, which you should run before starting the rest of the containers using `stack-windows.ps1` script. Down there are the settings you should make your own, Do not touch the value for `CN`. The values for `OU`, `O`, `L`, `ST`, and `C` should be the ones you seek to modify:

```yaml
plugins.security.nodes_dn:
  - 'CN=os01,OU=DFCTI,O=NIPNE,L=Magurele,ST=ILFOV,C=RO'
  - 'CN=os02,OU=DFCTI,O=NIPNE,L=Magurele,ST=ILFOV,C=RO'
  - 'CN=os03,OU=DFCTI,O=NIPNE,L=Magurele,ST=ILFOV,C=RO'
  - 'CN=os04,OU=DFCTI,O=NIPNE,L=Magurele,ST=ILFOV,C=RO'
  - 'CN=os05,OU=DFCTI,O=NIPNE,L=Magurele,ST=ILFOV,C=RO'
  - 'CN=dashboards,OU=DFCTI,O=NIPNE,L=Magurele,ST=ILFOV,C=RO'
```

Yoy may leave it like this to work without this headache. There is not a problem because the cryptographic keys generated are local to your project.

Always run `.\opensearch_local_certificates_creator.ps1` in the OpenSearch-3.6 folder before the first `docker compose up` command. The script also updates the compliance salt and SQL master key in all `opensearch.yml` files so those settings stay in sync with the newly generated certs.

4. Start the full stack:

```powershell
.\stack-windows.ps1 start
```

Tip: use `-NoLogs` if you do not want log tailing after startup.

Confirm any messages from Docker Desktop concerning acces to networks.

First, the OpenSearch cluster is formed, then the traefik container, MariaDB and Memcached, and finaly the Koha container. Following is a succession of mesages you should see:

```txt
 ✔ Image opensearchproject/opensearch-dashboards:3.6.0 Pulled                                                                       124.3s
 ✔ Image opensearch-36-os03                            Built  176.6s
 ✔ Image opensearch-36-os04                            Built  176.6s
 ✔ Image opensearch-36-os05                            Built  176.6s
 ✔ Image opensearch-36-os01                            Built  176.6s
 ✔ Image opensearch-36-os02                            Built  176.6s
 ✔ Network opensearch-36_osearch                       Created                                                                        0.1s
 ✔ Network knonikl                                     Created                                                                        0.1s
 ✔ Container os01                                      Healthy                                                                        7.3s
 ✔ Container os05                                      Started                                                                        1.4s
 ✔ Container os02                                      Started                                                                        1.5s
 ✔ Container os04                                      Started                                                                        1.5s
 ✔ Container os03                                      Started                                                                        1.4s
 ✔ Container dashboards                                Started                                                                        8.0s
 [ OK  ] OpenSearch containers started.
[INFO ] Waiting for OpenSearch cluster status to become green...
  attempt 15/72...
[ OK  ] OpenSearch cluster is green...
[INFO ] Starting Traefik...
[+] up 1/1
 ✔ Container traefik Running                                                                                                          0.0s
[ OK  ] Traefik started.
[INFO ] Starting MariaDB and Memcached...
[+] up 2/2
 ✔ Container koha-docker-windows-memcached-1 Running                                                                                  0.0s
 ✔ Container koha-docker-windows-db-1        Running                                                                                  0.0s
[ OK  ] Support services started.
[INFO ] Waiting for MariaDB in 'koha-docker-windows-db-1'...
[ OK  ] MariaDB is ready.
[INFO ] Resetting database 'koha_kohadev'...
[ OK  ] Database 'koha_kohadev' is ready.
[INFO ] Starting Koha container...
 ```
You should be patient with the last step because it takes a lot of time to complete.

Opening Docker Desktop you should have a status like the one in the following screenshot:

![](DockerDesktop-Usage.png)

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

### Koha image build fails with apt exit code 100

Symptoms:

- `failed to solve ... apt-get ... did not complete successfully: exit code: 100`
- `E: Failed to fetch ... Connection timed out`

Notes:

- This is a transient download/network issue during apt package fetch, not usually a missing package.
- The Dockerfile now retries apt install blocks automatically, including cleanup between attempts.

Run a clean Koha rebuild:

```powershell
.\stack-windows.ps1 build -BuildKoha
```

If the network is unstable, re-run once:

```powershell
.\stack-windows.ps1 build -BuildKoha
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
