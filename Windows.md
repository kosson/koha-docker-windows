# Windows Quick Reference

This is a concise checklist for the koha-docker-windows fork.
For complete documentation, see README.md.

## 1) Verify prerequisites

```powershell
git --version
docker --version
docker compose version
openssl version
```

## 2) Configure env/.env

```env
DOCKER_BINARY=docker
SYNC_REPO=C:/Users/nicolaie/Documents/DEVELOPMENT/koha-docker-windows/koha
OPENSEARCH_CA_CERT=C:/Users/nicolaie/Documents/DEVELOPMENT/koha-docker-windows/OpenSearch-3.6/assets/ssl/root-ca.pem
```

## 3) Generate OpenSearch certs

```powershell
cd .\OpenSearch-3.6
.\opensearch_local_certificates_creator.ps1
cd ..
```

## 4) Start and operate

```powershell
.\stack-windows.ps1 start
.\stack-windows.ps1 status
.\stack-windows.ps1 logs
.\stack-windows.ps1 restart
.\stack-windows.ps1 stop
```

## Legacy Linux scripts

- stack.sh
- OpenSearch-3.6/opensearch_local_certificates_creator.sh

These are compatibility-only in this fork.
