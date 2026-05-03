# Cluster setup

## About

This repo is designed to realize an OpenSearch cluster with five nodes using Docker Compose. This project has been create on an Ubuntu 25.10. Docker and Java should be installed already.

Acesta este un repo dedicat realizării unui cluster OpenSearch cu 5 noduri folosind Docker Compose. Acest proiect este creat pe o mașină Ubuntu 25.10. [Docker-ul](https://docs.docker.com/get-started/get-docker/) și Java ar trebui să fie deja instalat.
Documentația originală este accesibilă de la https://docs.opensearch.org/latest/install-and-configure/install-opensearch/index. Repo-ul unde se află resursele oficiale Docker, se găsește la https://hub.docker.com/u/opensearchproject. Documentația aferentă la https://docs.opensearch.org/latest/install-and-configure/install-opensearch/docker.

## Setarea mașinii gazdă

În Ubuntu 25.10 investigarea memoriei virtuale cu `cat /proc/sys/vm/max_map_count` a rezultat într-o valoare de `1048576`, mult superioară limitei de `262144` recomandată în documentație. Dacă valoarea este mai mică pentru ceea ce descoperi la această investigație, mărește `ulimits` pentru mașina gazdă pentru ca aceasta să permită I/O mărit.

```bash
sudo sysctl -w vm.max_map_count=512000
```

Poți face această setare permanentă scriind-o în `/etc/sysctl.conf`, după care execuți comanda: `sysctl -p`. Totuși, în Ubuntu 25.10, acest fișier nu există.

## Configurare inițială

Configurează fișierul `opensearch_installer_vars.cfg` cu valorile care sunt caracteristice propriului proiect. La fel și în cazul fișierul `.env`.

## Pașii de inițializare a clusterului

Reține faptul că trebuie să rulezi comenzile din rădăcina proiectului, locul unde ai ales să descarci proiectul de pe Github.

### Pasul 1

Curăță toate datele dintr-o sesiune anterioară, dacă acesta este cazul, rulând: `bash restart-to-clear-cluster.sh`.
Generează certificatele necesare dacă acestea nu au fost create anterior rulând: `bash opensearch_local_certificates_creator.sh`. Reține faptul că vor fi create certificate pentru dezvoltare locală. Root CA-ul este self-signed.

Setează permisiunile fișierelor după ce au fost create:

```bash
find assets/opensearch/config -type d | xargs chmod 700
find assets/opensearch/config -type f | xargs chmod 600
find assets/ssl -type f -name "*.pem" | xargs chmod 600
find assets/opensearch/performance-analyzer -type f | xargs chmod 600
```

```bash
import bcrypt; print(bcrypt.checkpw(b'admin', b'\$2y\$12\$qQz2JKL6uIC1LZuU/jPUleofpFJJw3NJlbSn0T1Xtzc694yaF4Ghe'))" 2>/dev/null || python3 -c "import bcrypt; h=b'\$2y\$12\$qQz2JKL6uIC1LZuU/jPUleofpFJJw3NJlbSn0T1Xtzc694yaF4Ghe'; print('admin:', bcrypt.checkpw(b'admin', h)); print('test@Cici24#ANA:', bcrypt.checkpw(b'test@Cici24#ANA', h))
```

Vezi nodurile:

```bash
sleep 8 && docker ps --format "{{.Names}}\t{{.Status}}" && echo "---" && curl -k -s "https://localhost:9200/_cluster/health?pretty" -u "admin:test@Cici24#ANA" | grep -E "status|number_of_nodes"
```

Studiază fișierul `opensearch_local_certificates_creator.sh` pentru că în acesta sunt parametrizate numele nodurilor. Vezi lista de valori din secvența `for NODE_NAME in "os01" "os02" "os03" "os04" "os05" "client" "dashboards"`. Dacă modifici oricare valoare din listă, trebuie reflectate modficările și în fișierul `initial_api_calls.sh`. Va trebui să modifici și denumirile tuturor subdirectoarelor din `./assets/opensearch/config` pentru a se potrivi alegerilor tale. Trebuie să modifici și `./assets/opensearch/config/os01/opensearch.yml`. Acesta este fișierul central de configurare. Dacă aduci modificări asupra modului în care generezi certificatele, asigură-te că toate modificările sunt reflectate și în acest fișier (căi și CN-uri).

Toate valorile din fișierul `opensearch_installer_vars.cfg` pot fi modificate, mai puțin `admin` de la `ADMIN_CA`.

Dacă modifici numele subdirectorului în care stă acest proiect, va trebui să modifici și `restart-to-clear-cluster.sh` pentru că numele întregului stack de Docker este dat de numele subdirectorului în care stă `docker-compose.yml`. Deci, va trebui să modifici linia `docker image rm cluster-opensearch-os01:latest;` din fișier dacă modifici numele subdirectorului rădăcină.

Ca măsură de prevedere, pentru propriul proiect modifică valoarea de la `OPENSEARCH_INITIAL_ADMIN_PASSWORD` din fișierul `.env`. Poți modifica și restul valorilor după cum ți se pare util.

### Pasul 2

Pornește clusterul generând containerele: `docker compose up -d`. Dacă nu ești în directorul proiectului, poți rula o comandă folosindu-te de căie absolute:

```bash
docker compose --project-directory /home/nicolaie/Documents/NIPNE/cluster-opensearch/OpenSearch-3.6 -f /home/nicolaie/Documents/NIPNE/cluster-opensearch/OpenSearch-3.6/docker-compose.yml up 2>&1 | tee /tmp/opensearch-startup-5.log
```

Outputul îl vezi rulând comanda: `docker logs os01 -f`. Rezultatul este apariția în prompt a faptului că mai întâi de toate este activat pluginul de securitate:

```text
Enabling OpenSearch Security Plugin
Disabling execution of install_demo_configuration.sh for OpenSearch Security Plugin
Enabling execution of OPENSEARCH_HOME/bin/opensearch-performance-analyzer/performance-analyzer-agent-cli for OpenSearch Performance Analyzer Plugin
```

Indiferent de erorile care apar, repornești containerul: `docker compose restart os01`.

Uneori apare eroarea `ERROR org.opensearch.security.configuration.ConfigurationLoaderSecurity7 - Failure no such index [.opendistro_security] retrieving configuration for [ACTIONGROUPS, ALLOWLIST, AUDIT, CONFIG, INTERNALUSERS, NODESDN, ROLES, ROLESMAPPING, TENANTS, WHITELIST] (index=.opendistro_security)`. În acest caz, treci la pasul 3.

Pentru a opri containerele: `docker compose down`.

În cazul în care dorești distrugerea containerelor pentru a o lua de la capăt rulează: `docker compose down -v --remove-orphans`. Eventual, refaci clusterul rulând comenzile de la pasul 1.

Dacă totul este ok, ar trebui să primești date pentru `curl -k --cert assets/ssl/admin.pem --key assets/ssl/admin-key.pem -XGET https://0.0.0.0:9200/_cluster/health?pretty -u admin:admin`. Remarcă faptul că `status` are valoarea `red`. Verifică mai întâi dacă ai răspuns la comanda anterioară. Dacă da, sari direct la pasul 4.

Închidere și repornire de la zero:

```bash
docker compose down -v --remove-orphans
sudo rm -rf assets/opensearch/data/os{01,02,03,04,05}data/nodes
docker compose up
```

La nevoie salvează un output al log-ului pentru analiză. De exemplu:

```bash
docker compose up 2>&1 | tee /tmp/opensearch-startup-0.log
```

Verifică starea:

```bash
curl -k -s "https://localhost:9200/_cat/nodes?v&h=name,ip,roles,heap.percent,load_1m" -u "admin:test@Cici24#ANA" && echo "---" && curl -k -s "https://localhost:9200/_cluster/health?pretty" -u "admin:test@Cici24#ANA" | grep -E '"status"|"number_of_nodes"|"active_shards"|"relocating"'
```

Verifică securitatea:

```bash
docker exec os01 sh -c "
  CONF=/usr/share/opensearch/config/opensearch-security
  CERT=/usr/share/opensearch/config/admin.pem
  KEY=/usr/share/opensearch/config/admin-key.pem
  CA=/usr/share/opensearch/config/root-ca.pem
  /usr/share/opensearch/plugins/opensearch-security/tools/securityadmin.sh -cd \$CONF -h os01 -p 9200 -cert \$CERT -key \$KEY -cacert \$CA -nhnv
" 2>&1 | tail -20
```


### Pasul 3

Rulează comanda pentru a crea datele inițiale în `.opendistro_security`:

```bash
docker exec os01 bash -c "chmod +x /usr/share/opensearch/plugins/opensearch-security/tools/securityadmin.sh && bash /usr/share/opensearch/plugins/opensearch-security/tools/securityadmin.sh -cd /usr/share/opensearch/config/opensearch-security/ -cacert /usr/share/opensearch/config/root-ca.pem -cert /usr/share/opensearch/config/admin.pem -key /usr/share/opensearch/config/admin-key.pem -icl -nhnv -t config -h os01 --accept-red-cluster"
```

Răspunsul este similar cu:

```shell
**************************************************************************
** This tool will be deprecated in the next major release of OpenSearch **
** https://github.com/opensearch-project/security/issues/1755           **
**************************************************************************
Security Admin v7
Will connect to os01:9200 ... done
Connected as "CN=admin,OU=DFCTI,O=NIPNE,L=MAGURELE,ST=ILFOV,C=RO"
OpenSearch Version: 2.15.0
Contacting opensearch cluster 'opensearch' ...
Clustername: opensearch
Clusterstate: RED
Number of nodes: 5
Number of data nodes: 4
.opendistro_security index already exists, so we do not need to create one.
ERR: .opendistro_security index state is RED.
Populate config from /usr/share/opensearch/config/opensearch-security/
Will update '/config' with /usr/share/opensearch/config/opensearch-security/config.yml 
   FAIL: Configuration for 'config' failed because of java.net.SocketTimeoutException: 30,000 milliseconds timeout on connection http-outgoing-6 [ACTIVE]
Will update '/roles' with /usr/share/opensearch/config/opensearch-security/roles.yml 
   FAIL: Configuration for 'roles' failed because of java.net.SocketTimeoutException: 30,000 milliseconds timeout on connection http-outgoing-7 [ACTIVE]
Will update '/rolesmapping' with /usr/share/opensearch/config/opensearch-security/roles_mapping.yml 
   FAIL: Configuration for 'rolesmapping' failed because of java.net.SocketTimeoutException: 30,000 milliseconds timeout on connection http-outgoing-8 [ACTIVE]
Will update '/internalusers' with /usr/share/opensearch/config/opensearch-security/internal_users.yml 
   FAIL: Configuration for 'internalusers' failed because of java.net.SocketTimeoutException: 30,000 milliseconds timeout on connection http-outgoing-9 [ACTIVE]
Will update '/actiongroups' with /usr/share/opensearch/config/opensearch-security/action_groups.yml 
   FAIL: Configuration for 'actiongroups' failed because of java.net.SocketTimeoutException: 30,000 milliseconds timeout on connection http-outgoing-10 [ACTIVE]
Will update '/tenants' with /usr/share/opensearch/config/opensearch-security/tenants.yml 
   FAIL: Configuration for 'tenants' failed because of java.net.SocketTimeoutException: 30,000 milliseconds timeout on connection http-outgoing-11 [ACTIVE]
Will update '/nodesdn' with /usr/share/opensearch/config/opensearch-security/nodes_dn.yml 
   FAIL: Configuration for 'nodesdn' failed because of java.net.SocketTimeoutException: 30,000 milliseconds timeout on connection http-outgoing-12 [ACTIVE]
Will update '/whitelist' with /usr/share/opensearch/config/opensearch-security/whitelist.yml 
   FAIL: Configuration for 'whitelist' failed because of java.net.SocketTimeoutException: 30,000 milliseconds timeout on connection http-outgoing-13 [ACTIVE]
Will update '/audit' with /usr/share/opensearch/config/opensearch-security/audit.yml 
   FAIL: Configuration for 'audit' failed because of java.net.SocketTimeoutException: 30,000 milliseconds timeout on connection http-outgoing-14 [ACTIVE]
Will update '/allowlist' with /usr/share/opensearch/config/opensearch-security/allowlist.yml 
   FAIL: Configuration for 'allowlist' failed because of java.net.SocketTimeoutException: 30,000 milliseconds timeout on connection http-outgoing-15 [ACTIVE]
ERR: cannot upload configuration, see errors above
```

Repornește containerul `os01` rulând: `docker compose restart os01`.

La rularea scriptului `securityadmin` pur și simplu se creează indexul, dar nu sunt preluate complet datele din fișierele yaml. Este vorba despre parolele setate în `internal_users.yml`. De exemplu, userul `admin` încă va avea parola `admin`. Ceea ce prelucrează scriptul `securityadmin.sh` este doar ceea ce este în fișierele cu care vine imaginea. Cumva, mapările pe fișierele din mașina gazdă funcționează, dar nu sunt luate în seamă la rularea scriptului. Se va folosi API-ul pentru crearea și modificarea userilor. De altfel este specificat că se va renunța la scriptul `securityadmin.sh` în viitorul apropiat.

### Pasul 4

Rulează scriptul care inițializează datele de conectare: `bash ./initial_api_calls.sh`. Repornește containerul `os01` rulând: `docker compose restart os01`.

### Pasul 5

Repornește containerul `dashboards` rulând: `docker compose restart dashboards`. Problema care apare este că Dashboards încearcă să se conecteze prea devreme și eșuează. Dacă încă nu ai configurat OpenSearch, vei avea o eroare care indică faptul că nu s-a realizat împerecherea lui OpenSearch cu Dashboards. Mesajul de eroare este similar cu cel de mai jos.

```shell
"[ConnectionError]: connect ECONNREFUSED 192.168.80.7:9200"
```

Trebuie să ajungi la un răspuns similar cu următorul:

```json
{"type":"log","@timestamp":"2024-07-25T08:24:22Z","tags":["listening","info"],"pid":1,"message":"Server running at https://0.0.0.0:5601"}
{"type":"log","@timestamp":"2024-07-25T08:24:22Z","tags":["info","http","server","OpenSearchDashboards"],"pid":1,"message":"http server running at https://0.0.0.0:5601"}
```

Chiar dacă următoarea comandă este parte a pachetului de inițializare din `initial_api_calls.sh`, este necesară repetarea dacă pentru userul admin, care este logat, nu apare la `View roles and identities` -> `Roles` valoarea `all_access`. Acest lucru este absolut necesar pentru a avea acces la `Security` în meniul principal.

## Investigații

### Investigarea clusterului

Pentru a obține o perspectivă asupra clusterului, rulează comanda pe `_cat/nodes`.

```bash
curl -k --cert assets/ssl/admin.pem --key assets/ssl/admin-key.pem -XGET https://0.0.0.0:9200/_cat/nodes?v
```

Obții un răspuns similar cu următorul:

```shell
ip         heap.percent ram.percent cpu load_1m load_5m load_15m node.role node.roles                                        cluster_manager name
172.18.0.4           55          97   6    0.22    0.62     0.88 s         search                                            -               os05
172.18.0.6           44          97   6    0.22    0.62     0.88 m         cluster_manager                                   -               os01
172.18.0.2           27          97   6    0.22    0.62     0.88 dimr      cluster_manager,data,ingest,remote_cluster_client *               os02
172.18.0.3           19          97   6    0.22    0.62     0.88 di        data,ingest                                       -               os03
172.18.0.5           65          97   6    0.22    0.62     0.88 di        data,ingest                                       -               os04
```

### Verifică și starea clusterului 

Rulează comanda:

```bash
curl -k --cert assets/ssl/admin.pem --key assets/ssl/admin-key.pem -XGET https://0.0.0.0:9200/_cluster/health?pretty -u admin:test@Cici24#ANA
```

Parola `test@Cici24#ANA` este una arbitrar setată inițial prin valoarea lui `OPENSEARCH_INITIAL_ADMIN_PASSWORD` din `.env` și apoi în apelurile API de configurare din `initial_api_calls.sh`. Rezultatul trebuie să fie similar cu:

```json
{
  "cluster_name" : "opensearch",
  "status" : "green",
  "timed_out" : false,
  "number_of_nodes" : 5,
  "number_of_data_nodes" : 4,
  "discovered_master" : true,
  "discovered_cluster_manager" : true,
  "active_primary_shards" : 8,
  "active_shards" : 20,
  "relocating_shards" : 0,
  "initializing_shards" : 0,
  "unassigned_shards" : 0,
  "delayed_unassigned_shards" : 0,
  "number_of_pending_tasks" : 0,
  "number_of_in_flight_fetch" : 0,
  "task_max_waiting_in_queue_millis" : 0,
  "active_shards_percent_as_number" : 100.0
}
```

Același rezultat trebuie obținut prin apel direct care folosește Basic Auth:

```bash
curl -k -XGET https://0.0.0.0:9200/_cluster/health?pretty -u admin:test@Cici24#ANA
```

### Investighează indecșii existenți

În lucrul cu indecșii, ai nevoie de confirmarea că au fost creați. Din acest motiv ai nevoie de un mijloc de investigație.

```bash
curl -k --cert assets/ssl/admin.pem --key assets/ssl/admin-key.pem -XGET https://0.0.0.0:9200/_cat/indices
```

Răspunsul poate fi similar cu următorul:

```shell
green open .opensearch-observability    CyNl204KSa2asRj7oMPR8g 1 2  0 0    624b    208b
green open .plugins-ml-config           _3f5kdwTQOCeSuqHCjMpYA 1 1  1 0   7.8kb   3.9kb
green open .ql-datasources              QmN4MbcwSc-LJf8NCM1sxw 1 2  0 0    624b    208b
green open security-auditlog-2024.07.26 UGt48s2aQMGfe7uHCyZ9Cg 1 1 24 0 309.1kb 154.7kb
green open .opendistro_security         -MS0L1sNQM6YOKqMwQ8V7w 1 2 10 1 116.7kb  38.9kb
green open .kibana_1                    TDdg9JfNTgiK-x06_GchFg 1 1  1 0  10.3kb   5.1kb
green open security-auditlog-2024.07.25 uCBrERxwTDua0r1EzeGpKQ 1 1 26 0 296.5kb 148.2kb
```

## Variabilele unui container

Uneori este foarte util să afli variabilele unui container. Comanda pe care o rulezi este următoarea:

```bash
docker exec -it -u 0 os01 sh -c "env"
```

## Informații despre utilizatori

De cele mai multe ori este necesar să cunoști date despre un anumit utilizator. Mai jos sunt două comenzi. Prima aduce date pentru userul admin pentru care este îndeajuns trimiterea certificatului. Iar pentru cea de-a doua, va fi făcută și autentificarea cu user și parolă.

```bash
curl -k --cert assets/ssl/admin.pem --key assets/ssl/admin-key.pem -XGET https://0.0.0.0:9200/_plugins/_security/api/account?pretty
curl -k --cert assets/ssl/dashboards.pem --key assets/ssl/dashboards-key.pem -XGET https://0.0.0.0:9200/_plugins/_security/api/account?pretty -u 'dashboards:test@Cici24#ANA'
```

Mai multe detalii la https://opensearch.org/docs/latest/security/access-control/api/#account.

### Userul admin

În cazul comenzii de mai jos sunt aduse datele doar pentru utilizatorul `admin`. Utilizatorul `admin` este precizat de certificatele utilizate pentru a autentifica cererea.

```bash
curl -k --cert assets/ssl/admin.pem --key assets/ssl/admin-key.pem -XGET https://0.0.0.0:9200/_opendistro/_security/authinfo?pretty
```

Vei obține detaliile utilizatorului admin:

```json
{
  "user" : "User [name=CN=admin,OU=DFCTI,O=NIPNE,L=MAGURELE,ST=ILFOV,C=RO, backend_roles=[], requestedTenant=null]",
  "user_name" : "CN=admin,OU=DFCTI,O=NIPNE,L=MAGURELE,ST=ILFOV,C=RO",
  "user_requested_tenant" : null,
  "remote_address" : null,
  "backend_roles" : [ ],
  "custom_attribute_names" : [ ],
  "roles" : [
    "own_index",
    "all_access"
  ],
  "tenants" : {
    "global_tenant" : true,
    "admin_tenant" : true,
    "CN=admin,OU=DFCTI,O=NIPNE,L=MAGURELE,ST=ILFOV,C=RO" : true
  },
  "principal" : "CN=admin,OU=DFCTI,O=NIPNE,L=MAGURELE,ST=ILFOV,C=RO",
  "peer_certificates" : "1",
  "sso_logout_url" : null
}
```

Utilizatorul este autorizat de certificate pentru a obține datele dorite. Încercând cu alte certificate, nu vei fi autorizat. Administratorul trebuie să aibă `backend_roles` cu valoarea `all_access`, dar neapărat și `opendistro_security_roles` cu aceeași valoare de `all_access`. Dacă în `"backend_roles"` nu ai valoarea `"admin"`, nu poți face apeluri folosind Basic Auth: `curl -X GET https://0.0.0.0:9200 -u 'admin:test@Cici24#ANA' --insecure`. Vei avea un 403 drept răspuns.

### Alți useri

Pentru a afla datele specifice pentru un utilizator, altul decât un admin, vei însoți cererea de user și parolă. De exemplu, pentru utilizatorul `dashboards` care a fost creat arbitrar, vom folosi comanda de mai jos pentru a-i aduce datele.

```bash
curl -k --cert assets/ssl/dashboards.pem --key assets/ssl/dashboards-key.pem -XGET https://0.0.0.0:9200/_opendistro/_security/authinfo?pretty -u 'dashboards:test@Cici24#ANA'
```

Cu un rezultat similar cu cel de jos:

```json
{
  "user" : "User [name=dashboards, backend_roles=[all_access, readall, kibana_server], requestedTenant=null]",
  "user_name" : "dashboards",
  "user_requested_tenant" : null,
  "remote_address" : "172.20.0.1:47026",
  "backend_roles" : [
    "all_access",
    "readall",
    "kibana_server"
  ],
  "custom_attribute_names" : [ ],
  "roles" : [
    "own_index",
    "all_access",
    "dashboards",
    "kibana_server",
    "readall"
  ],
  "tenants" : {
    "admin_tenant" : true,
    "global_tenant" : true,
    "dashboards" : true
  },
  "principal" : "CN=dashboards,OU=DFCTI,O=NIPNE,L=MAGURELE,ST=ILFOV,C=RO",
  "peer_certificates" : "1",
  "sso_logout_url" : null
}
```

Câteva informații și despre certificatul de securitate folosit:

```bash
curl -k --cert assets/ssl/dashboards.pem --key assets/ssl/dashboards-key.pem -XGET https://0.0.0.0:9200/_opendistro/_security/sslinfo?pretty -u 'dashboards:test@Cici24#ANA'
```

#### Informații specifice utilizatorilor in dashboardsinfo

Verifică autentificarea cu user și parolă prin accesarea unor informații de bază caracteristice lui Dashboards.

```bash
curl -k -XPOST -u 'dashboards:test@Cici24#ANA' -XGET "https://0.0.0.0:9200/_plugins/_security/dashboardsinfo?pretty"
curl -k -XPOST -u 'admin:test@Cici24#ANA' -XGET "https://0.0.0.0:9200/_plugins/_security/dashboardsinfo?pretty"
```

### Informație despre toți utilizatorii

De cele mai multe ori, această comandă este necesară pentru a depana rolurile pe care le-ar putea avea un anumit utilizator atunci când încă nu ai acces la Dashboards. Folosim același certificat de administrator pentru a autoriza cererea.

```bash
curl -k --cert assets/ssl/admin.pem --key assets/ssl/admin-key.pem -XGET https://0.0.0.0:9200/_plugins/_security/api/internalusers | jq .
```

sau 

```bash
curl -k -XPOST -u 'admin:test@Cici24#ANA' -XGET https://0.0.0.0:9200/_plugins/_security/api/internalusers | jq .
```

Pentru admin, detaliile sunt următoarele:

```json
{
  "admin": {
    "hash": "",
    "reserved": false,
    "hidden": false,
    "backend_roles": [
      "all_access",
      "readall"
    ],
    "attributes": {},
    "opendistro_security_roles": [
      "all_access"
    ],
    "static": false
  }
}
```

Ceea ce se remarcă este faptul că cele două valori de la `backend_roles` sunt cele care apar mai sus la `roles`.

### Verificarea permisiunilor unui utilizator

De cele mai multe ori ai nevoie să verifici permisiunile unui utilizator.

```bash
curl -k --cert assets/ssl/dashboards.pem --key assets/ssl/dashboards-key.pem -XPOST -u 'dashboards:test@Cici24#ANA' -XGET https://0.0.0.0:9200/_plugins/_security/api/permissionsinfo | jq .
```

Cu un rezultat similar cu cel de jos.

```json
{
  "user": "User [name=dashboards, backend_roles=[all_access, readall, kibana_server], requestedTenant=null]",
  "user_name": "dashboards",
  "has_api_access": true,
  "disabled_endpoints": {}
}
```

## Autentificare

Backend-urile de autentificare sunt definite în `/etc/opensearch/opensearch-security/config.yml`. Aceste backend-uri sunt înlănțuite. Acest lucru înseamnă că *Security plugin* va încerca să autentifice userul într-o secvență care va trece prin toate backendurile definite până când unul are succes. Indiferent de backendul folosit, credențialele sunt trimise odată cu cererea de autentificare (*request for authentication)*. Dacă un backend a verificat credențialele unui utilizator, îi va acorda acestuia backend roles-urile asociate. Furnizorul de date de autentificare determină modul în care aceste roluri sunt obținute. Când este folosit **basic authentication** se va căuta în [baza de date internă](https://opensearch.org/docs/latest/security/authentication-backends/basic-authc/#the-internal-user-database) ce *role mappings* sunt setate. Mai multe detalii la https://opensearch.org/docs/2.14/security/authentication-backends/basic-authc/. După ce userul a fost autentificat și rolurile din backend au fost obținute, *Security plugin* se folosește de *role mapping* pentru a atribui userului rolurile atribuite.

*Client certificate authentication* oferă mai multă securitate decât `basic authentication`. Un alt avantaj este că poți să-l folosești împreună cu `basic authentication` pentru a avea un al doilea nivel de siguranță. Mai întâi, activează în `/etc/opensearch/opensearch.yml` următoarea directivă `plugins.security.ssl.http.clientauth_mode: OPTIONAL`. În `/etc/opensearch/opensearch-security/config.yml` configurează:

```yml
      clientcert_auth_domain:
        description: "Authenticate via SSL client certificates"
        http_enabled: true
        transport_enabled: true
        order: 1
        http_authenticator:
          type: clientcert
          config:
            username_attribute: cn #optional, if omitted DN becomes username
          challenge: false
        authentication_backend:
          type: noop
```

## Roluri

Rolurile definesc limitele de acțiune ale unei permisiuni sau a unui grup de acțiune. Poți crea roluri care au anumite privilegii, de exemplu, roluri care conțin oricare combinație de permisiuni extinse pe tot clusterul sau permisiuni specifice doar unui index, ori securitate la nivel de câmp sau chiar document. Poți conecta utilizatorii la roluri la momentul creării sau după ce utilizatorii și rolurile au fost definite. Această conexiune determină permisiunile și nivelurile de acces pentru fiecare utilizator în baza rolurilor care le-au fost atribuite. *Security plugin* vine cu un număr de *predefined action groups, roluri, mapping-uri și utilizatori* (vezi https://opensearch.org/docs/latest/security/access-control/index/). Aceste *entități* servesc ca default-uri de mare ajutor și constituie un bun ajutor privind modul de utilizare al pluginului.

### Concepte importante de lucru

#### Permission

*Permission* (https://opensearch.org/docs/latest/security/access-control/permissions/) este o acțiune individuală așa cum este, de exemplu crearea unui index. Aceste permisiuni poartă o denumire ceva mai criptică precum `indices:admin/create`. Acțiunile de care vorbim sunt cele pe care un cluster OpenSearch le poate face așa cum este indexarea unui document sau verificarea stării unui cluster. În cele mai multe cazuri, permisiunile se corelează cu anumite operațiuni pe API. De exemplu, `cluster:admin/ingest/pipeline/get` se corelează cu `GET _ingest/pipeline`. Totuși nu există o mapare directă pe operațiunile REST API. Vezi explicația de aici, neapărat: https://opensearch.org/docs/2.14/security/access-control/permissions/#do_not_fail_on_forbidden.

#### Role

Security roles definesc aria de aplicare a unei permisiuni sau a unui action group: cluster, index, document sau field. De exemplu, un rol denumit `delivery_analyst` poate să nu aibă nicio permisiune pe niciun cluster, la *action group* să aibă `READ` pentru toate indexurile care se potrivesc șablonului `delivery-data-*` și să acceseze toate tipurile de documente care au acele indexuri sau să acceseze toate câmpurile mai puțin `delivery_driver_name`. Rolurile sunt cele care dau permisiunile, de fapt prin operațiunea de *role mapping*.

#### Backend role

Acesta este opțional, fiind un șir de caractere ales arbitrar (o denumire arbitrară) pe care o specifici sau care vine de la un sistem extern de autentificare (LDAP sau Active Directory). Aceste *backend roles* pot simplifica procesul de role mapping.
În loc să faci un mapping al aceluiași rol pentru 100 de utilizatori, mai bine faci mapping rolului unui backend role pe care să-l aibă atașat cei 100 de utilizatori. Prin această abordare, mapezi rolul la un identificator care este un backend role în loc să faci maparea fiecărui utilizator în parte.

#### User

Sunt cei care fac apeluri pe clusterele OpenSearch. Un user are credențiale (de ex., un username și o parolă), zero sau mai multe roluri în backend și zero sau mai multe atribute definite arbitrar.

#### Role mapping

Imediat după ce s-au autentificat cu succes, userii își asumă roluri. Role mapping-ul conectează rolurile cu userii sau cu backend roles. De exemplu, conectarea rolului `kibana_user` la userul `jdoe` înseamnă că acest user va avea toate permisiunile asociate rolului `kibana_user` după ce se va autentifica. În mod similar, un mapping al rolului `all_access` la backend role-ului `admin` înseamnă că toți utilizatorii care au backend role-ul `admin` dobândesc toate permisiunile asociale lui `all_access` după ce se autentifică. Poți face mapping fiecărui rol mai multor utilizatori și/sau unor backend roles.

## Useri și roluri activate

Un user are nevoie să îndeplinească anumite roluri. Unele roluri sunt doar read-only (vezi https://opensearch.org/docs/latest/security/access-control/users-roles/#defining-read-only-roles). Rolurile read-only previn modificările accidentale.
Rolurile pot fi definite în OpenSearch folosind API-ul dedicat (se poate și cu fișierul yml sau prin Dashboards, dacă ai deja acces). Un rol are nevoie să-i fie definite anumite permisiuni.

Din start, sunt activate câteva roluri în fișierul de configurare `/etc/opensearch/opensearch.yml` prin directiva `plugins.security.restapi.roles_enabled`. Un exemplu este mai jos:

```yml
plugins.security.restapi.roles_enabled: ["all_access", "security_rest_api_access", "anomaly_full_access", "asynchronous_search_full_access", "index_management_full_access", "security_manager", "kibana_server"]
```

### Roluri deja definite

Să investigăm rolurile care sunt predefinite în sistem - https://opensearch.org/docs/latest/security/access-control/users-roles#predefined-roles. Se va folosi autorizarea de admin pentru a obține aceste date.

```bash
curl -k --cert assets/ssl/admin.pem --key assets/ssl/admin-key.pem -XGET https://localhost:9200/_plugins/_security/api/roles/ -k | jq .
```

În conexiune cu accesul la OpenSearch Dashboards, am găsit rolurile:

- `kibana_user`, care are setările ce ar permite accesul la Dashboards,
- `kibana_read_only`, care permite doar citirea datelor,
- `kibana_server`, care oferă minimum de permisiuni pentru serverul Dashboards (indexul `.opensearch_dashboards`).

### opendistro_security_roles și backend_roles

Rolurile primare cu care vine OpenSearch din oficiu sunt cele care sunt definite în `sudo nano /etc/opensearch/opensearch-security/roles.yml`. Aici am o singură înregistrare care privește OpenSearch Dashboards:

```yml
# Restrict users so they can only view visualization and dashboard on OpenSearchDashboards
kibana_read_only:
  reserved: true
```

Array-ul `opendistro_security_roles` trebuie să conțină roluri care deja au fost definite (vezi pe `_plugins/_security/api/roles`).

### Maparea rolurilor

Pentru a vedea care sunt rolurile mapate, se va executa comanda: `curl -k --cert assets/ssl/admin.pem --key assets/ssl/admin-key.pem -XGET "https://0.0.0.0:9200/_plugins/_security/api/rolesmapping" | jq .`.

## Configurările de securitate

Uneori ai nevoie de câteva detalii privind setările de securitate ale clusterului. Mai jos obții setările pentru Dashboards.

```bash
curl -k --cert assets/ssl/admin.pem --key assets/ssl/admin-key.pem -XGET https://0.0.0.0:9200/_plugins/_security/api/securityconfig | jq .config.dynamic.kibana
```

## Teste sintetice

Când clusterul este pregătit, ai nevoie de informații pe care să le integrezi în diferite fluxuri de lucru. Obține informații despre nodul pe care ajunge interogarea și cum se numește clusterul.

```bash
curl -k --cert assets/ssl/admin.pem --key assets/ssl/admin-key.pem -XGET https://localhost:9200/_cluster/settings?include_defaults=true | jq '.defaults | {nume_nod: .cluster.name, nume_cluster: .cluster.initial_cluster_manager_nodes[0]}'
```

Răspuns similar cu cel de mai de jos.

```json
{
  "nume_nod": "opensearch",
  "nume_cluster": "os01"
}
```

Ceva mai multe date mai jos.

```bash
curl -k --cert assets/ssl/admin.pem --key assets/ssl/admin-key.pem -XGET https://localhost:9200/_cluster/settings?include_defaults=true | jq '.defaults | {nume_nod: .cluster.name, nume_cluster: .cluster.initial_cluster_manager_nodes[0], securitate_admin_dn: .plugins.security.authcz, securitate_plugins_security_config_ssl_dual_mode: .plugins.security_config.ssl_dual_mode_enabled, caile: .path, opensearch_dashboards_system_indices: .opensearch_dashboards.system_indices, node_roles: .node.roles, node_ingest: .node.ingest, node_master: .node.master, node_cale_pid: .node.pidfile, node_local_storage: .node.local_storage, http_cors: .http.cors, http_port: .http.port, network_host: .network.host, transport_tcp: .transport.tcp, discovery_seed_hosts: .discovery.seed_hosts[0]}'
```

## Tenancy

Obține date privind tenancy:

```bash
curl -k -u 'dashboards:test@Cici24#ANA' -XGET "https://0.0.0.0:9200/_plugins/_security/api/tenancy/config?pretty"
```

## Management de containere cu Portainer.io

Pornește un container Portainer. Mai întâi, creează volumul pentru date: `docker volume create portainer_data`. Apoi află care este rețeaua la care vrei containerul Portainer să fie atașat: `docker network ls`. Pentru exemplificare, am următoarele date:

```bash
NETWORK ID     NAME                         DRIVER    SCOPE
4c5304b03496   bridge                       bridge    local
7c143f4bac37   cluster-opensearch_default   bridge    local
e98c8e2250b0   cluster-opensearch_knonikl   bridge    local
d7dac01faf92   cluster-opensearch_osearch   bridge    local
5601e8f57346   host                         host      local
52e4678efdad   none                         null      local
```

În acest caz, vom folosi o rețea suplimentară la care sunt atașate doar două containere din clusterul OpenSearch: `cluster-opensearch_knonikl`.

```bash
docker run -d -p 9000:9000 --network cluster-opensearch_knonikl --name=portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
```

Dacă la rularea comenzii, ai o eroare similară cu `docker: Error response from daemon: Conflict. The container name "/portainer" is already in use by container "c64c02f4924abfdf3d846b8b4c046032dece71aa91cedbc7035393e467608ad3". You have to remove (or rename) that container to be able to reuse that name.` înseamnă că deja ai un container numit `portainer`. Poți să-l ștergi cu `dockr rm portainer`. Dulează din nou comanda care creează containerul.

Aplicația va fi disponibilă pe `http://0.0.0.0:9000/`.

## Test creare index

În acest moment ai nevoie să faci teste pentru a te asigura că totul funcționează corect.

```bash
curl -XPUT -k -u 'admin:test@Cici24#ANA' 'https://0.0.0.0:9200/test-index'
curl -k -XPUT 'https://0.0.0.0:9200/test-index/_doc/1' -H 'Content-Type: application/json' -d '{"Description": "To be or not to be, that is the question."}' -u 'admin:test@Cici24#ANA'
curl -k -XDELETE 'https://0.0.0.0:9200/test-index/_doc/1' -u 'admin:test@Cici24#ANA'
curl -k -XDELETE 'https://0.0.0.0:9200/test-index/' -u 'admin:test@Cici24#ANA'
```

## Tenants

*Tenants* sunt niște spații în OpenSearch Dashboards unde sunt salvate șablone de nume pentru indecși, vizualizări, dashboard-uri și alte obiecte ale OpenSearch Dashboards. OpenSeach permite utilizatorilor să creeze tenants multipli în diverse scopuri.
Tenants sunt utili pentru a oferi acces securizat altor utilizatori OpenSearch Dashboards. Din oficiu, toți utilizatorii de Dashboards au acces la doi tenants independenți. Cel global și cel privat. Multi-tenancy care este caracteristic Dashboards permite opțiunea de a crea tenants customizați.
Global tenant este partajat cu toți userii de Dashboards, permițând distribuirea de obiecte OpenSearch Dashboards cu cei care au acces la acesta. Tenant-ul privat este propriu fiecărui user și nu poate fi partajat cu alții.
Tenant-urile custom pot fi create de administratori și li se pot atribui roluri. Din moment ce sunt create, aceste tenant-uri, aceste pot oferi spații pentru grupuri specifice de utilizatori.

Documentația: https://opensearch.org/docs/latest/security/multi-tenancy/tenant-index/
