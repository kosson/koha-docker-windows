Comenzi investigații

```bash
docker network inspect knonikl 2>/dev/null | grep -E '"Name"|"Subnet"' | head -5 && docker compose -f /media/expansion/DEVELOPMENT/KOHA-DOCKER-SOLUTIONS/koha-docker/OpenSearch-3.6/docker-compose.yml ps 2>/dev/null | head -10 || docker ps --filter name=os 2>/dev/null | head -10
```

Stergerea retelei din clusterul OpenSearch

```bash
docker run --rm --network knonikl curlimages/curl:latest curl -sk -u "admin:test@Cici24#ANA" https://os01:9200/_cluster/health?pretty 2>&1 | head -15
```

din nou

```bash
docker run --rm --network knonikl curlimages/curl:latest curl -sk -u "admin:test@Cici24#ANA" https://os01:9200/_cluster/health?pretty 2>&1 | head -15
```

sau

```bash
docker run --rm --network knonikl curlimages/curl:latest curl -v -k -u "admin:test@Cici24#ANA" https://os01:9200/ 2>&1 | tail -20
```

Investigare din nou a rețelei knonikl

```bash
docker network inspect knonikl 2>/dev/null | python3 -c "import json,sys; n=json.load(sys.stdin); [print(c['Name'], c.get('IPv4Address',''), [a for a in c.get('Aliases',[])][:5]) for c in n[0]['Containers'].values()]"
```

Investigație suplimentare

```bash
docker inspect os01 2>/dev/null | python3 -c "import json,sys; c=json.load(sys.stdin)[0]; print(c['Config'].get('Labels',{}))" 2>&1 | head -5
```

Câte rețele sunt in cluster

```bash
cat /media/expansion/DEVELOPMENT/KOHA-DOCKER-SOLUTIONS/koha-docker/OpenSearch-3.6/docker-compose.yml | grep -A5 "networks:" | head -30
```

Cine raspunde pe 9200

```bash
docker exec os01 bash -c "ss -tlnp 2>/dev/null | grep 9200 || netstat -tlnp 2>/dev/null | grep 9200"
```

Deconectează knonikl de pe primul nod al clusterului.
Motivație:

OpenSearch binds only to 172.28.0.3 (its opensearch-36_osearch IP), not 0.0.0.0. Connecting os01 to knonikl won't help — the koha container needs to join the opensearch-36_osearch network instead:

```bash
docker network disconnect knonikl os01 && echo "Disconnected os01 from knonikl"
```

Now update docker-compose.yml to join the koha container to opensearch-36_osearch: ` opensearch-36_osearch: {}`

```bash
docker compose --env-file env/.env up -d 2>&1
```

Investigație:

```bash
docker compose --env-file env/.env logs -f koha 2>&1 | tee /tmp/koha-runtime2.log
```

și

```bash
docker ps --filter name=koha-docker-koha 2>/dev/null && docker inspect koha-docker-koha-1 2>/dev/null | python3 -c "import json,sys; c=json.load(sys.stdin)[0]; s=c['State']; print('Status:', s['Status'], 'ExitCode:', s.get('ExitCode',''))"
```

Reinițializează baza de date

```bash
docker exec koha-docker-db-1 mysql -uroot -ppassword -e "DROP DATABASE IF EXISTS koha_kohadev; CREATE DATABASE koha_kohadev CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; GRANT ALL PRIVILEGES ON koha_kohadev.* TO 'koha_kohadev'@'%'; FLUSH PRIVILEGES;" 2>&1
```

si

```bash
docker exec koha-docker-db-1 mysql -uroot -ppassword -e "SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema='koha_kohadev';" 2>&1
```

Dă un curl folosind o imagine specializată

```bash
docker run --rm --network knonikl curlimages/curl:latest curl -sk -u "admin:test@Cici24#ANA" https://os01:9200/_cluster/health 2>&1
```

Script de researe

```bash
docker run --rm \
  --network koha-docker_kohanet \
  --network opensearch-36_osearch \
  --name koha-debug \
  -e KOHA_CONF=/etc/koha/sites/kohadev/koha-conf.xml \
  -e PERL5LIB=/kohadevbox/koha:/kohadevbox/koha/lib \
  -e PERL_LWP_SSL_VERIFY_HOSTNAME=0 \
  koha-docker-koha \
  perl /kohadevbox/koha/misc/search_tools/rebuild_elasticsearch.pl -v 2>&1 | head -40
```

suplimentar

```bash
docker exec koha-debug bash -c '
  # Check if os01 resolves
  getent hosts os01 2>&1 | head -3
  echo "---"
  # Try a direct HTTP connection to os01:9200
  curl -sk --max-time 5 -u "admin:test@Cici24#ANA" https://os01:9200/ 2>&1 | head -5
  echo "EXIT: $?"
' 2>&1
```

apoi

```bash
docker exec koha-debug bash -c '
  export PERL5LIB=/kohadevbox/koha:/kohadevbox/koha/lib
  export PERL_LWP_SSL_VERIFY_HOSTNAME=0
  # Check if KOHA_CONF exists at the default path
  ls /etc/koha/sites/ 2>&1
  cat /etc/koha/sites/kohadev/koha-conf.xml 2>/dev/null | grep -E "elasticsearch|elastic|server" | head -10
' 2>&1
```

Apoi: `docker exec koha-debug ls /etc/koha/sites/ 2>&1`.

The issue is clear: the error from rebuild_elasticsearch.pl is swallowed because sudo koha-shell suppresses stderr. I need to exec into the running container while it's active and capture the actual error. Let me restart it and exec in before the ES step:

```bash
docker exec koha-docker-db-1 mysql -uroot -ppassword -e "DROP DATABASE IF EXISTS koha_kohadev; CREATE DATABASE koha_kohadev CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; GRANT ALL PRIVILEGES ON koha_kohadev.* TO 'koha_kohadev'@'%'; FLUSH PRIVILEGES;" 2>&1 && \
docker compose -f /media/expansion/DEVELOPMENT/KOHA-DOCKER-SOLUTIONS/koha-docker/docker-compose.yml --env-file /media/expansion/DEVELOPMENT/KOHA-DOCKER-SOLUTIONS/koha-docker/env/.env --project-directory /media/expansion/DEVELOPMENT/KOHA-DOCKER-SOLUTIONS/koha-docker up -d --force-recreate koha 2>&1
```

Apoi

```bash
# Wait for koha-conf.xml to be created (after koha-create completes), then check it
for i in $(seq 1 60); do
  result=$(docker exec koha-docker-koha-1 cat /etc/koha/sites/kohadev/koha-conf.xml 2>/dev/null | grep -A5 "elasticsearch" | head -15)
  if [ -n "$result" ]; then
    echo "=== koha-conf.xml elasticsearch section ==="
    echo "$result"
    break
  fi
  sleep 3
done
```

Apoi

```bash
docker exec koha-docker-koha-1 bash -c '
  export KOHA_CONF=/etc/koha/sites/kohadev/koha-conf.xml
  export PERL5LIB=/kohadevbox/koha:/kohadevbox/koha/lib:/kohadevbox/qa-test-tools
  export PERL_LWP_SSL_VERIFY_HOSTNAME=0
  sudo -u kohadev-koha -s -- bash -c "
    export KOHA_CONF=/etc/koha/sites/kohadev/koha-conf.xml
    export PERL5LIB=/kohadevbox/koha:/kohadevbox/koha/lib:/kohadevbox/qa-test-tools
    export PERL_LWP_SSL_VERIFY_HOSTNAME=0
    perl /kohadevbox/koha/misc/search_tools/rebuild_elasticsearch.pl -v 2>&1
  "
' 2>&1 | head -60
```

Apoi

```bash
docker exec koha-docker-koha-1 bash -c '
  export KOHA_CONF=/etc/koha/sites/kohadev/koha-conf.xml
  export PERL5LIB=/kohadevbox/koha:/kohadevbox/koha/lib:/kohadevbox/qa-test-tools
  # Test: bypass SSL in Search::Elasticsearch directly
  sudo -u kohadev-koha env KOHA_CONF=/etc/koha/sites/kohadev/koha-conf.xml PERL5LIB=/kohadevbox/koha:/kohadevbox/koha/lib PERL_LWP_SSL_VERIFY_HOSTNAME=0 perl -e "
    use Search::Elasticsearch;
    my \$e = Search::Elasticsearch->new(
      nodes => "https://os01:9200",
      userinfo => "admin:test\@Cici24#ANA",
      ssl_options => { verify_hostname => 0, SSL_verify_mode => 0 },
    );
    my \$r = \$e->info;
    print "Connected: ", \$r->{version}{number}, "\n";
  " 2>&1
' 2>&1 | head -20
```

apoi

```bash
# Check which HTTP backend Search::Elasticsearch uses in koha
grep -r "Search::Elasticsearch" /media/expansion/DEVELOPMENT/KOHA-DOCKER-SOLUTIONS/koha-docker/koha/Koha/SearchEngine/Elasticsearch.pm 2>/dev/null | head -5
grep -r "cxn_pool\|client\|HTTP" /media/expansion/DEVELOPMENT/KOHA-DOCKER-SOLUTIONS/koha-docker/koha/Koha/SearchEngine/Elasticsearch.pm 2>/dev/null | head -10
```

Apoi

```bash
grep -n "get_elasticsearch\|Search::Elasticsearch->new\|ssl\|SSL\|verify\|nodes\|cxn" /media/expansion/DEVELOPMENT/KOHA-DOCKER-SOLUTIONS/koha-docker/koha/Koha/SearchEngine/Elasticsearch.pm 2>/dev/null | grep -v "^Binary\|#" | head -30
```

Apoi

```bash
grep -n "ssl\|SSL\|verify\|HTTP::Tiny" /usr/share/perl5/Search/Elasticsearch/Cxn/HTTPTiny.pm | head -30
```

Testare folosind un container suplimentar:

```bash
# Start a debug container that runs the full init but with KOHA_ELASTICSEARCH=no to skip ES step
docker run -d \
  --name koha-estest \
  --network koha-docker_kohanet \
  --network opensearch-36_osearch \
  --env-file /media/expansion/DEVELOPMENT/KOHA-DOCKER-SOLUTIONS/koha-docker/env/.env \
  -e KOHA_ELASTICSEARCH=no \
  -e LOCAL_USER_ID=1000 \
  -e KOHA_IMAGE=main \
  -e KOHA_MARC_FLAVOUR=marc21 \
  -e SKIP_CYPRESS_CHOWN=no \
  -e SKIP_L10N=no \
  -v /media/expansion/DEVELOPMENT/KOHA-DOCKER-SOLUTIONS/koha-docker/koha:/kohadevbox/koha \
  koha-docker-koha \
  sleep 900 2>&1 && echo "Started"
```

The root cause: Search::Elasticsearch base64-encodes the URL-encoded password (test%40...) instead of the actual one. Fix: pass credentials via userinfo separately from the URL.


Reconstrucție și inspecție

```bash
docker compose -f /media/expansion/DEVELOPMENT/KOHA-DOCKER-SOLUTIONS/koha-docker/docker-compose.yml \
  --env-file /media/expansion/DEVELOPMENT/KOHA-DOCKER-SOLUTIONS/koha-docker/env/.env \
  --project-directory /media/expansion/DEVELOPMENT/KOHA-DOCKER-SOLUTIONS/koha-docker \
  logs -f koha 2>&1 | tee /tmp/koha-runtime6.log &

# Poll for completion or error
for i in $(seq 1 300); do
  log=$(cat /tmp/koha-runtime6.log 2>/dev/null)
  if echo "$log" | grep -q "koha-testing-docker has started up"; then
    echo "=== FULLY STARTED ==="
    echo "$log" | grep -E "rebuild_elasticsearch|has started up|plack|Finished" | tail -10
    kill %1 2>/dev/null
    break
  fi
  if echo "$log" | grep -qi "\[Request\].*400\|\[Request\].*illegal\|NoNodes\|exited with code [^0]" | grep -v "exited with code 0"; then
    echo "=== ERROR ==="
    echo "$log" | grep -i "request.*400\|illegal\|NoNodes" | tail -5
    kill %1 2>/dev/null
    break
  fi
  # Also check if container exited
  if ! docker ps | grep -q koha-docker-koha-1; then
    echo "=== CONTAINER EXITED ==="
    echo "$log" | tail -15
    kill %1 2>/dev/null
    break
  fi
  sleep 3
done
```

## Verificarea stării containerelor

Următorul script face verificări.

```bash
cd /media/expansion/DEVELOPMENT/KOHA-DOCKER-SOLUTIONS/koha-docker && timeout 900 docker compose --env-file env/.env logs -f koha 2>&1 | tee /tmp/koha-start.log &
echo "Tailing PID $!"
# Watch for ready or fatal events
for i in $(seq 1 300); do
  log=$(cat /tmp/koha-start.log 2>/dev/null)
  if echo "$log" | grep -q "koha-testing-docker has started up"; then
    echo "=== READY ==="
    echo "$log" | grep -E "rebuild_elasticsearch|started up|Plack|error|Error|FATAL" | tail -20
    break
  fi
  if echo "$log" | grep -qiE "FATAL|rebuild_elasticsearch.*[Ee]rror|NoNodes|ProductCheck|Cannot|refused|exited"; then
    echo "=== ERROR DETECTED ==="
    echo "$log" | grep -iE "FATAL|[Ee]rror|NoNodes|ProductCheck|Cannot|refused" | tail -20
    break
  fi
  sleep 5
done
```

Verifică o anumită rețea

```bash
docker network ls && echo "---" && docker inspect frontend 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['Name'], d[0]['Driver'], 'containers:', list(d[0]['Containers'].keys())[:5])" 2>/dev/null || echo "frontend network not found"
```

Testare acces la sock:

```bash
ls -la /run/user/$(id -u)/docker.sock 2>/dev/null || ls -la ~/.docker/run/docker.sock 2>/dev/null || systemctl --user status docker 2>/dev/null | head -5 || echo "checking rootless..."
```

All done — both issues fixed and tested

nip.io fix (root cause found and resolved):

- The bug was run.sh storing http://kohadev.127.0.0.1.nip.io:8080 in the Koha database as OPACBaseURL. The :8080 made Koha's own links bypass Traefik.
- Fix: new KOHA_PUBLIC_PORT=80 in env/.env. When port is 80, URLs are stored without any port suffix.
- Verified: OPACBaseURL = http://kohadev.127.0.0.1.nip.io (no :8080), both OPAC and Staff return HTTP 200 via nip.io.

Demo data flags:

- ./stack.sh start --no-demo-data → empty catalogue (0 bibliographic records, superlibrarian only)
- ./stack.sh start --with-demo-data → 436 sample MARC records loaded (default)
- Mechanism: run.sh replaces insert_data.pl with a Perl no-op when LOAD_DEMO_DATA=no.

Important reminder: `KOHA_DOMAIN` in `env/.env` is currently set to `.127.0.0.1.nip.io` (for this test session). Change it back to `.myDNSname.org` for production use.