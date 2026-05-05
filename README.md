# koha-docker-windows

This project is a derivation of the `https://github.com/kosson/koha-docker` repo. It's for those who use Windows as their main development platform. In the aforementioned repo some very sound patterns and ideas were taken from the work done for the project at [koha-testing-docker (a.k.a. KTD)](https://gitlab.com/koha-community/koha-testing-docker).
All the heavy lifting was done using AI agents via a Github subscription. Most of the avatars during development can be tracked if you look into the TRACKER.md file.

Use the source code as is. Remember this is a development project to experiment with Koha, to migrate data, etc. This is not a production suite.

## Scope

Building a cluster of Docker containers that gives the possibility to work with Koha latest version. At the time of this repo initialization the version is Koha 25.12.00. Koha needs a database (MariaDB), a caching mechanism (Memcache), an indexing engine (OpenSearch), and a proxy for accessing the installation in the browser (Traefik).

## Prerequisites

You need to have a fairly well endowed computer to run these services. All the final product will need around 12Gb of RAM to run comfortably. The RAM of your computer needs to be at least 16Gb, which is not that rare these days. You need to activate virtualization in BIOS so that some cores of your processors may be "borrowed" for the containers we raise for each of the components. Also, you need to have a good Internet connection. First thing on the list is installing Docker Desktop. This is the main ingredient. Follow, the list:

- Docker Desktop (Linux containers mode)
- PowerShell 5.1+
- Git for Windows
- WSL installed (see: https://docs.docker.com/desktop/features/wsl/) needed by Docker Desktop.

Notes:

- The OpenSearch certificate generator auto-detects `openssl.exe` from common Git for Windows (https://git-scm.com/install/windows) locations.
- OpenSSL in PATH is optional. The script will try and solve this automatically. Further down there are instructions on how you could install it by yourself if you want to.
- For Docker you need at least 8Gb of RAM, a 64bit processor with at least four cores (8 threads), at least 20Gb of HDD/SSD, and virtualization activated in BIOS/EFI to avoid errors described in the following online document: https://docs.docker.com/desktop/troubleshoot-and-support/troubleshoot/topics/#docker-desktop-fails-due-to-virtualization-not-working.

Check the needed tools if they are installed:

```powershell
git --version
docker --version
docker compose version
wsl --version
```

Every command listed above, run in PowerShell, should yield the version of the installed package. Solve these requirements first. Run each command on a separate line.
If you do not have WSL install it with `wsl --install`. If you have it, update it: `wsl --update`.

Optional check for OpenSSL. OpenSSL is very important being used in cryptographic keys generation (see OpenSearch):

```powershell
openssl version
```

If you don't have OpenSSL installed run in PowerShell (as Administrator) the following: `winget install --id=FireDaemon.OpenSSL -e`. Close PowerShell and open it again. Check for version. If no answer is given in the shell, then it needs to be added to the PATH. Run in the shell the following: `$Env:PATH += ";C:\Program Files\FireDaemon OpenSSL 3\bin"`.
OpenSSL is also part of Git for Windows as mentioned previously.

Now, it is the time to install Docker Desktop if you haven't done that already - https://docs.docker.com/get-started/get-docker/.

Download the code for the project from this repo. Look at the green button `Code`, and choose to download the zip version. If you have an account at GitHub, use it to download the resources. After you have downloaded the code, unarchive it to a folder of your own choosing. A good idea is to put it in a `DEVELOPMENT` subfolder in `Documents`. This is just a suggestion. Now, after you have unzipped the files, unfortunately, the source code is placed in another subfolder called `koha-docker-windows-main`. Enter it, cut all the content, and paste it above so everything is in the correct subfolder named `koha-docker-windows`. This is a GitHub zipping process quirk. After you move the content, the `koha-docker-windows-main` folder is empty, so delete it, as it is now useless cruft.

Now, the `koha-docker-windows` subfolder will be referred to as the _root folder_ from now on.

## Quick start

1. We need all the source code of Koha ILS, so, being in the root folder of your project, run in the PowerShell in the root of the project:

```powershell
git clone --depth=1 https://git.koha-community.org/Koha-community/Koha.git koha
```

2. Configure Windows host paths in env/.env. These settings are crucial, so track them in the `.env` file in the `env` subfolder, and put your own paths reflecting your location of choice:

```env
DOCKER_BINARY=docker
SYNC_REPO=C:/Users/nicolaie/Documents/DEVELOPMENT/koha-docker-windows/koha
OPENSEARCH_CA_CERT=C:/Users/nicolaie/Documents/DEVELOPMENT/koha-docker-windows/OpenSearch-3.6/assets/ssl/root-ca.pem
```

For `SYNC_REPO`, the path should be the `koha` subfolder that was created at in the previous step.
For the `OPENSEARCH_CA_CERT` put the same path just in front of the ending sequence `/OpenSearch-3.6/assets/ssl/root-ca.pem`. Observe that the file `root-ca.pem` referenced in the path might not exist at this stage. This is ok. It will be created in the following step.

Be very thorough with these paths. Double check everything. Notice the fact that if you copy the path from the exploring window, the systems uses backslashes, a characteristic of Windows OS. When you paste in the `.env` file correct those to slashes. For example, `C:\Users\kosson\Documents\DEVELOPMENT\koha-docker-windows`, needs to be `C:/Users/kosson/Documents/DEVELOPMENT/koha-docker-windows`. Again, be mindful of your own paths, do not copy these examples.

3. Generate OpenSearch certificates:

Now, because OpenSearch needs a secure communication between its nodes, we need to create the cryptographic keys it uses. Set execution policy for the current user.

But first, we need to allow Windows security policies to run our PowerShell scripts. First, go to System -> Advanced and activate `Developer Mode` (On). Then PowerShell -> Change execution policy to allow local PowerShell scripts to run without signing (On). In the opened PowerShell, paste the following command and enter it:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Confirm it with `A` meaning All. It should be like below:

```powershell
PS C:\Users\kosson> Get-ExecutionPolicy -List

        Scope ExecutionPolicy
        ----- ---------------
MachinePolicy       Undefined
   UserPolicy       Undefined
      Process       Undefined
  CurrentUser    RemoteSigned
 LocalMachine    RemoteSigned
```

Restart because Windows.

Now, for every subfolder `OpenSearch-3.6./assets/opensearch/config/os01` ... to `os05` you have a configuration file named `opensearch.yml`. All of them have the exact same hard coded settings for the `plugins.security.nodes_dn option` as value. Modify them to match your institutional environment. These are only for test and development builds localized to the creator of this project. You should use it as is only to test. Modify it to adapt it to your institution. Also, the `plugins.security.compliance.salt` and `plugins.query.datasources.encryption.masterkey` values will be re-generated every time you run bash `.\opensearch_local_certificates_creator.ps1`, which you should run before starting the rest of the containers using `stack-windows.ps1` script. Below are the settings you should make your own. Do not touch the value for `CN`. The other values for `OU`, `O`, `L`, `ST`, and `C` are the ones you should modify:

```yaml
plugins.security.nodes_dn:
  - 'CN=os01,OU=DFCTI,O=NIPNE,L=Magurele,ST=ILFOV,C=RO'
  - 'CN=os02,OU=DFCTI,O=NIPNE,L=Magurele,ST=ILFOV,C=RO'
  - 'CN=os03,OU=DFCTI,O=NIPNE,L=Magurele,ST=ILFOV,C=RO'
  - 'CN=os04,OU=DFCTI,O=NIPNE,L=Magurele,ST=ILFOV,C=RO'
  - 'CN=os05,OU=DFCTI,O=NIPNE,L=Magurele,ST=ILFOV,C=RO'
  - 'CN=dashboards,OU=DFCTI,O=NIPNE,L=Magurele,ST=ILFOV,C=RO'
```

You may leave it like this to work without this headache. There is not a problem because the cryptographic keys generated are local to your project. Remember to modify all the `opensearch.yml` for all the nodes.

Then run the following commands separately (every command on each line in order):

```powershell
cd .\OpenSearch-3.6
.\opensearch_local_certificates_creator.ps1
cd ..
```

If you have issues concerning security imposed on running the scripts, run the script with the following:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\opensearch_local_certificates_creator.ps1
```

It is Windows way. Another way is to right click on the script file and tick the `Unblock` in the `Security` section, or in PowerShell: `Unblock-File -Path .\opensearch_local_certificates_creator.ps1`.

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

The script also updates the compliance salt and SQL master key in all `opensearch.yml` files so those settings stay in sync with the newly generated certs.

4. Start the full stack

First, start Docker Desktop application. This will run the `docker` application in background. This is mandatory.

Now, run the command in the PowerShell in the root of your project:

```powershell
.\stack-windows.ps1 start
```

or for the melodramatic Windows, as above:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\stack-windows.ps1 start
```

If an error like the following stops the setup process, just run the script again. The possible error:

```powershell
[INFO ] Resetting database 'koha_kohadev'...
--------------
GRANT ALL PRIVILEGES ON koha_kohadev.* TO 'koha_kohadev'@'%'
--------------

ERROR 1133 (28000) at line 3: Can't find any matching row in the user table
Failed to reset database 'koha_kohadev'.
At C:\Users\Alina\Documents\koha-docker-windows\stack-windows.ps1:19 char:35
+ function Fail([string]$Message) { throw $Message }
+                                   ~~~~~~~~~~~~~~
    + CategoryInfo          : OperationStopped: (Failed to reset database 'koha_kohadev'.:String) [], RuntimeException
    + FullyQualifiedErrorId : Failed to reset database 'koha_kohadev'.
```

Tip: use `-NoLogs` if you do not want log tailing after startup.

Confirm any messages from Docker Desktop concerning access to networks.

First, the OpenSearch cluster is formed, then the Traefik container, MariaDB and Memcached, and finally the Koha container. Following is a succession of mesages you should see:

```powershell
=============================================
  Koha + OpenSearch Windows Stack Manager
=============================================

[ OK  ] Network 'frontend' already exists.
[INFO ] Starting OpenSearch cluster (first)...
 ✔ Image opensearch-36-os05      Built     5.6s
 ✔ Image opensearch-36-os01      Built     5.6s
 ✔ Image opensearch-36-os02      Built     5.6s
 ✔ Image opensearch-36-os03      Built     5.6s
```

For more details, open the [powerup sequence](power-up-sequence.md).

In case you messed up bad, open Docker desktop, stop all the containers, delete all the volumes, and start all over again. If this happens it means that you have tried in the past, and there are some leftover volumes that mess up things. Delete the volumes, run the script again, and the joyful message `koha-testing-docker has started up and is ready to be enjoyed!` will make your day. Yeeey!

After the happy message, you may close the PowerShell. From now on you will relly only on Docker Desktop.

Opening Docker Desktop you should have a status like the one in the following screenshot:

![](DockerDesktop-Usage.png)

After everything went well and you are able to access the Koha administrator and OPAC using the browser, the management of your installation will be done using Docker Desktop. From here you will stop all the containers when you want to stop the session or start a new one.

### Closing sequence

If you have finished work and you want to close down the application, in Docker Desktop, in Container section (see left menu) select first the `opensearch-36` name. This is a service orchestrating all the containers which form an OpenSearch cluster. This is the indexing engine of your Koha application. Once ticked, press stop buton in the right side. Then close the `traefik` container, and in the end the `koha-docker-windows` one.

### Start sequence

First, open Docker Desktop. Then start the OpenSearch cluster, and wait for 5 to 6 minutes. This time is necessary for the cluster to form. Then, start traefik, and in the end run the command in the PowerShell ypu'll open in the root directory: `.\stack-windows.ps1 start`.

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

Remember to use the containers via Docker Desktop. 

## Default URLs

- OPAC: http://kohadev.127.0.0.1.nip.io
- Staff: http://kohadev-intra.127.0.0.1.nip.io
- Dashboards: http://dashboards.localhost
- Traefik dashboard: http://localhost:8083
- OpenSearch API: https://localhost:9200

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

### OpenSearch startup diagnostics (Windows)

Use this routine when `start -BuildOpenSearch` creates containers but reports errors or does not reach green cluster state.

1. Reset only OpenSearch containers and volumes:

```powershell
docker compose -f .\OpenSearch-3.6\docker-compose.yml --env-file .\OpenSearch-3.6\.env down -v
```

2. Rebuild and start through the Windows manager:

```powershell
.\stack-windows.ps1 start -BuildOpenSearch -NoLogs
```

3. Validate startup state:

```powershell
.\stack-windows.ps1 health
```

Expected OpenSearch checks:

- `OpenSearch os01 container healthy` = PASS
- `OpenSearch cluster status green` = PASS

4. If OpenSearch is still not green, collect focused cluster logs:

```powershell
docker compose -f .\OpenSearch-3.6\docker-compose.yml --env-file .\OpenSearch-3.6\.env ps
docker compose -f .\OpenSearch-3.6\docker-compose.yml --env-file .\OpenSearch-3.6\.env logs
```

5. If Koha build later fails with `Release file ... is not valid yet`, verify Windows clock/timezone sync, restart Docker Desktop, then rerun step 2.

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
