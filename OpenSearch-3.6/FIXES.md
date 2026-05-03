# OpenSearch 3.6 Cluster — Startup Issues Tracker

Captured from `docker compose up` on **2026-04-17**. Issues are grouped by severity.
Status legend: `[ ]` open · `[x]` fixed · `[~]` accepted / intentional

---

Issues found (10 warnings, 3 errors, 6 config problems) + 3 new

Errors
ID	Issue	Severity
E1	~~Performance Analyzer config missing on all nodes~~ **FIXED**	High
E2	~~Security not initialized on os01 at first boot~~ **FIXED** (+ 2.15→3.6 compatibility update)	Transient
E3	`.opendistro_security` index missing on os02–os05 at startup	Transient
E4	~~`SettingsException: unknown setting [opensearch_security.compliance.salt]`~~ **FIXED** (renamed to `plugins.security.*` in 3.x)	Critical
E5	~~Cluster formation failure — os01 dual-network transport address split~~ **FIXED** (removed `knonikl` from os01 networks)	Critical
E6	~~`OpenSearchSecurityPlugin` fails to load — `/usr/share/opensearch/config/root-ca.pem is a directory`~~ **FIXED** (2026-05-03)	Critical

Warnings

ID	Issue
W1	~~Insecure file permissions on all config files and certs~~ **FIXED** (`chmod` on host assets/)
W2	~~Compliance salt not configured~~ **FIXED** (salt added to all 5 opensearch.yml)
W3	~~SQL Plugin datasource master key not set~~ **FIXED** (masterkey added to all 5 opensearch.yml)
W4	workload-management plugin missing — soft dependency of opensearch-security
W5	StreamTransportService unavailable (ML streaming) — accepted if not needed
W6	No audit log endpoint configured — using default sink
W7	Repeated auth failures from Dashboards healthcheck (transient)
W8	No resource usage stats from os02–os05 (caused by E1)
W9	JVM native access / deprecated APIs (BouncyCastle, ByteBuddy, Arrow) — upstream
W10	SLF4J provider not found — upstream

New warnings found in startup-4

ID	Issue
N1	~~SecurityAnalyticsPlugin: Failed to initialize LogType config index~~ transient — accepted
N2	DanglingIndicesState: `gateway.auto_import_dangling_indices` is disabled — informational
N3	ConfigOverridesClusterSettingHandler: empty config override string (PA disabled) — benign

docker-compose.yml / config issues

ID	Issue
C1	~~Duplicate `OPENSEARCH_INITIAL_ADMIN_PASSWORD` on os01~~ **FIXED**
C2	~~os02 has no `node.roles`~~ **FIXED** (set to `cluster_manager,data,ingest`)
C3	~~os02–os05 missing `env_file: .env`~~ **FIXED**
C4	~~os03 `extra_hosts` maps own hostname to 127.0.0.1~~ **FIXED** (commented out)
C5	~~os02 `enforce_hostname_verification` commented out~~ **FIXED** (uncommented)
C6	~~os02 `opensearch.yml` missing security REST API settings~~ **FIXED**
C7	~~`internal_users.yml` hash was for password `admin`, not `test@Cici24#ANA`~~ **FIXED**
C8	~~os01 healthcheck: single-quoted password never expands + no `--fail` + dashboards starts before security ready~~ **FIXED**



## ERRORS

### E1 — Performance Analyzer config file missing (all nodes)
**Status:** `[x]` fixed — 2026-04-17

**Log:**
```
[ERROR][o.o.p.c.c.PluginSettings] Loading config file
  /usr/share/opensearch/config/opensearch-performance-analyzer/performance-analyzer.properties
  failed … java.io.FileNotFoundException … Disabling plugin.
[ERROR][o.o.p.c.c.StatsCollector] Error in loading metadata for folderLocation:
  /usr/share/opensearch/config/opensearch-performance-analyzer/, fileLocation: plugin-stats-metadata
```

**Cause:** The `opensearch-performance-analyzer/` config directory is not present inside the container.
The plugin is bundled with OpenSearch but its configuration directory is not created by default when
`DISABLE_INSTALL_DEMO_CONFIG=true`.

**Fix applied:**
- Created `assets/opensearch/performance-analyzer/performance-analyzer.properties` with `performance-analyzer.enabled=false`
- Created `assets/opensearch/performance-analyzer/plugin-stats-metadata` (present to prevent `StatsCollector` FileNotFoundException)
- Added bind-mount to all 5 nodes in `docker-compose.yml`:
  ```yaml
  - ./assets/opensearch/performance-analyzer:/usr/share/opensearch/config/opensearch-performance-analyzer
  ```
- **Note:** Also resolves **W8** (no resource usage stats), since that warning was caused by PA being disabled.

# Check if the plugin-stats-metadata file is bundled anywhere in the plugin jar

`docker exec os01 sh -c "cd /usr/share/opensearch/plugins/opensearch-performance-analyzer && jar tf opensearch-performance-analyzer-3.6.0.0.jar 2>/dev/null | grep -E 'properties|metadata' | head -20" 2>&1`

Creează un director

`mkdir -p /home/nicolaie/Documents/NIPNE/cluster-opensearch/OpenSearch-3.6/assets/opensearch/performance-analyzer`.

E1 is confirmed fixed. All PluginSettings lines are now [INFO] — the plugin loaded its config successfully on all nodes. Zero [ERROR] lines from PluginSettings or StatsCollector.

Notice the change:

Before: [ERROR][o.o.p.c.c.PluginSettings] Loading config file … FileNotFoundException … Disabling plugin.
After: [INFO][o.o.p.c.c.PluginSettings] Cannot find metrics-location, using default value. /dev/shm/performanceanalyzer/
The plugin is now loading and running (it read the properties file, found no metrics-location override, and defaulted gracefully — that's normal INFO behaviour).

Side effect: W8 ("No resource usage stats") still appears because performance-analyzer.enabled=false keeps the metrics collection off. If you want full resource stats visible to the cluster manager, change performance-analyzer.enabled=true in assets/opensearch/performance-analyzer/performance-analyzer.properties and restart. No rebuild needed — it's a bind-mount.

---

### E2 — Security not initialized on os01 at startup (transient) + OpenSearch 2.15→3.6 compatibility
**Status:** `[x]` fixed and verified — 2026-04-17

**Original log:**
```
[ERROR][o.o.s.a.BackendRegistry] [os01] OpenSearch Security not initialized.
  (you may need to run securityadmin)
```

**Verification (startup-4, 2026-04-17):**
- No `UnrecognizedPropertyException` (bad field rename eliminated)
- No persistent `BackendRegistry: Security not initialized` errors
- Transient `ConfigurationLoaderSecurity7: Failure no such index` on os02–os05 at t=0 — **expected** (race condition before master creates the index)
- Single transient `BackendRegistry: Security not initialized` on os01 at 07:57:14 — **resolved at 07:57:15** (1 second, normal startup race)
- All 5 nodes logged `Node 'osXX' initialized` ✅
- os01 reported `healthy`, dashboards up on port 5601 ✅

**Cause:** During the first boot, the `.opendistro_security` index does not exist yet. All REST
requests fail until the cluster manager initialises the security index. The transient error
disappears once `allow_default_init_securityindex: true` triggers auto-init from the YAML files.

The deeper issue was that the `initial_api_calls.sh` script and several config files still used
OpenDistro / OpenSearch 2.x APIs that were removed or renamed in OpenSearch 3.0:

| File | Change |
|------|--------|
| `opensearch-security/config.yml` | Removed `multitenancy_enabled`, `private_tenant_enabled`, `default_tenant` (multi-tenancy removed in 3.0) |
| `opensearch-security/roles.yml` | Removed `tenant_permissions` block (tenant concept gone) |
| `opensearch-security/internal_users.yml` | `opendistro_security_roles` field name is **unchanged** in OpenSearch 3.6 — reverted a bad rename |
| `opensearch-security/roles_mapping.yml` | Replaced stub with full mappings: `all_access`, `opensearch_dashboards_server`, `dashboards`, `own_index`, `readall` |
| `assets/dashboards/opensearch_dashboards.yml` | Removed `opensearch_security.multitenancy.*` settings, removed `securitytenant` header, renamed read-only role to `opensearch_dashboards_read_only` |
| `initial_api_calls.sh` | Full rewrite: removed `opendistro_security_roles`, `tenant_permissions`, deprecated `hosts` field, `kibana_server`/`kibana_user` references; added cluster-ready wait loop; now reads password from env |

**Better approach in 3.6 (no `initial_api_calls.sh` needed on first boot):**
With `plugins.security.allow_default_init_securityindex: true` (already set in `os01/opensearch.yml`),
the cluster reads `opensearch-security/*.yml` files and auto-populates the `.opendistro_security`
index on every fresh start. After the above fixes, those YAML files are self-sufficient:
no manual script run is required for day-1 setup.

`initial_api_calls.sh` is now a **day-2 operations tool** — use it only to push live config
changes to a running cluster without restarting:

```bash
cd OpenSearch-3.6
source .env
bash initial_api_calls.sh
```

### config.yml

Analisis on what needs to be changed for OpenSearch 3.6.0 vs 2.15:

Key breaking changes in OpenSearch Security between 2.15 and 3.6:

Multi-tenancy completely removed (OpenSearch 2.12 deprecated it, 3.0 removed it):

config.yml: kibana.multitenancy_enabled, kibana.private_tenant_enabled, kibana.default_tenant → all removed
roles.yml: tenant_permissions → removed
tenants.yml → effectively dead
The initial_api_calls.sh script that creates a dashboards role with tenant_permissions will either silently fail or throw an error
opendistro_security_roles field removed from user objects:

The opendistro_security_roles field in internal_users.yml and REST API calls is deprecated and removed
Need to switch to opensearch_security_roles instead, or rely on backend_roles with roles_mapping.yml
In the setup script, "opendistro_security_roles": ["all_access"] needs to become "opensearch_security_roles": ["all_access"]
Role name changes in built-in roles:

kibana_server → opensearch_dashboards_server (though kibana_server might still work as an alias)
kibana_user → opensearch_dashboards_user
Tenant-related permissions like kibana_all_write no longer exist
hosts field in rolesmapping: This is deprecated in favor of specifying users directly

For OpenSearch 3.6, the better approach is to rely on allow_default_init_securityindex: true with properly configured YAML files, using the API script only when re-running on fresh data or making changes without restarting.

The recommended path forward is configuring everything statically in the YAML files and letting the auto-initialization handle it on boot, but if they need to keep using the API script, it'll need updates to use the new OpenSearch naming conventions, remove tenant permissions, replace hosts with users in role mappings, and add a wait loop to ensure the cluster is ready before executing.


### opensearch_dashboards.yml

Issues with current configuration for OpenSearch 3.6:

config.yml (opensearch-security):
multitenancy_enabled: true → REMOVED in OpenSearch 3.0
private_tenant_enabled: false → REMOVED
default_tenant: global tenant → REMOVED

roles.yml:
tenant_permissions in dashboards role → REMOVED (tenant concept removed)

internal_users.yml:
opendistro_security_roles → should be opensearch_security_roles (or just use backend_roles + roles_mapping.yml)

#### initial_api_calls.sh:

The script has several compatibility issues: it's hardcoding the admin password instead of using environment variables, referencing deprecated opendistro_security_roles in API calls, attempting to create roles with the removed tenant_permissions structure, and referencing kibana_user which doesn't exist as a built-in role in 3.6 (should be opensearch_dashboards_user instead).

The rolesmapping uses the deprecated hosts field when it should use users or backend_roles, there's no cluster readiness check before making API calls, and while passwords are hardcoded, the cert-based auth approach itself is acceptable for the admin user.

opensearch_dashboards.yml:
The multitenancy configuration is completely obsolete in Dashboards 3.0 — both opensearch_security.multitenancy.enabled and the tenants.preferred setting will trigger startup warnings and should be removed entirely. The securitytenant header in requestHeadersAllowlist is also no longer relevant.

For OpenSearch 3.6, the cleaner approach is using static configuration files only...

Updating the script approach instead...

The dashboards user password is hardcoded in three places — the shell script, the Dashboards config, and the internal users file — and they all need to stay in sync. I should standardize this by using an environment variable across all three locations rather than keeping a hardcoded value scattered around.

For the bigger picture, I'm thinking the cleaner approach for OpenSearch 3.6 is to rely on the static YAML files to bootstrap everything on a fresh start, since allow_default_init_securityindex: true is already enabled. This means updating those files to remove deprecated multitenancy settings and fix the role attribute names, then keeping the shell script only as a fallback for reapplying settings after data wipes. I should also add a wait loop to the script and fix any deprecated API fields it's using.

Now I'm going through each configuration file systematically—removing multitenancy from config.yml, roles.yml, and opensearch_dashboards.yml, updating the role references in internal_users.yml, ensuring roles_mapping.yml has all the proper static mappings, and checking what happened to whitelist.yml since it was renamed to allowlist.yml in this version.

### tenants.yml

Breaking changes between OpenSearch 2.15 → 3.6.0:
Multi-tenancy removed (since 3.0):

config.yml: Remove multitenancy_enabled, private_tenant_enabled, default_tenant
roles.yml: Remove tenant_permissions (will be silently ignored or rejected)
opensearch_dashboards.yml: Remove opensearch_security.multitenancy.enabled, opensearch_security.multitenancy.tenants.preferred, remove securitytenant from requestHeadersAllowlist
Field naming updates: The opendistro_security_roles field needs to be renamed to opensearch_security_roles in both internal_users.yml and the API calls, and whitelist.yml has been replaced with allowlist.yml though backwards compatibility is maintained for now.

Script cleanup needed: The initial_api_calls.sh script references the deprecated field name and attempts to create roles with tenant_permissions, both of which will fail against 3.6.0.

Configuration issues: The script references kibana_user as a backend role that doesn't exist as a built-in, the hosts field in role mappings is deprecated, there's no cluster readiness check, and it's using https://0.0.0.0:9200 instead of the proper hostname.

Actually, I'm realizing the better approach here is that with allow_default_init_securityindex: true, OpenSearch automatically loads the YAML files into the security index on startup, so the API script becomes unnecessary if I configure the YAML files correctly. The script would only be needed for making changes after the initial setup.

So the real fix is to update the YAML configuration files themselves—removing multitenancy settings from config.yml and stripping out tenant permissions from roles.yml since those aren't needed for this setup.

For the user configuration, I need to correct the field name in internal_users.yml to use opensearch_security_roles instead of the deprecated opendistro_security_roles, though the backend_roles approach via roles_mapping.yml is actually the more standard way to handle this in OpenSearch 3.x.

Now I'm working through the roles mapping configuration... I'm realizing the roles_mapping.yml file works as an override layer on top of OpenSearch's built-in defaults when auto-initialization is enabled, so I only need to add the custom dashboards role mapping there. For the initial_api_calls.sh script, its main purpose shifts to applying live updates to a running cluster rather than initialization, since the YAML files handle that automatically. Let me reconsider what E2 actually represents in the context of these fixes. The key insight is that with proper YAML configuration and allow_default_init_securityindex: true, OpenSearch 3.6 handles everything automatically on startup—the script becomes unnecessary for initial setup and should shift to a day-2 operations role. To fully resolve the auth failures, I need to strip multitenancy settings from the config files and ensure the static YAML is complete enough that Dashboards gets everything it needs from the auto-initialization.

Updating the YAML files... I need to take a systematic approach here: explain the better way using static YAML with auto-initialization, then update the script for 3.6 compatibility, fix the YAML files, and update the dashboards config. For the roles mapping in static files, OpenSearch 3.6 merges the YAML definitions with built-in defaults at startup, so I only need to add the custom role mappings rather than redefining everything.

Now I'm checking whether the dashboards user in internal_users.yml has the correct backend_roles configured for automatic role mapping to work properly.

Looking at the user definitions, I can see that dashboards has backend_roles including admin and dashboards, which means it'll automatically map to the all_access role through the admin backend_role. The admin user similarly has the admin backend_role, so it also gets full access. For the certificate-based admin user, I'll need to add its CN to the all_access role mapping.

Now I'm planning the specific changes needed for roles_mapping.yml...

Defining the role mappings to grant full access to the admin backend role and the certificate-based admin user, while also creating a separate mapping for the dashboards user and a custom dashboards role.

I notice the file comment warns that static reserved roles can't be overridden, so I need to be careful about which roles I'm modifying.

Actually, I'm realizing that in OpenSearch, when allow_default_init_securityindex: true, the YAML files do populate the security index on first boot—the "cannot override" error only applies when using the REST API. So I can define these mappings in the static YAML without issues.

Let me write out the updated initialization script...

Writing the initialization script... Setting up the API helper function...

Now I'm checking that the config file exists, sourcing it, and waiting for the cluster to be ready. I'm also handling the admin password from the environment or falling back to the config file value. Then I'm preparing to update the internal users in OpenSearch security, making sure to use the correct API endpoint for version 3.x.

Updating user credentials and roles... Setting up role mappings...

Now I'm thinking about the endpoint configuration—when running this script from the host machine, 0.0.0.0:9200 works because Docker exposes the container's port, but from inside a container I'd need to use the service name os01:9200 instead. Since this is meant to run on the host side with Docker Compose, the current setup should work fine.

I'm also reconsidering the PATCH operation strategy—using "op": "add" will fail if the user already exists, so "replace" is the safer choice here since the internal users are pre-created in the configuration.

Actually, I need to think through this more carefully. The OpenSearch Security API's PATCH endpoint for internal users treats add operations as upserts on existing paths, which is different from strict JSON Patch semantics. So add would work whether the users exist or not, making it more flexible than replace.

Now I'm ready to implement all the configuration changes across seven files: removing multitenancy from the config and dashboards settings, cleaning up the roles to remove tenant permissions, fixing the user role assignments, updating the role mappings, completely rewriting the API initialization script for version 3.6, and updating the status documentation.

Root causes (2.15 → 3.6 breaking changes):

File	                    Issue
config.yml	                multitenancy_enabled, private_tenant_enabled, default_tenant removed in 3.0
roles.yml	                tenant_permissions block removed (multi-tenancy gone)
internal_users.yml	        opendistro_security_roles key deprecated → opensearch_security_roles
roles_mapping.yml	        Only has a stub; needs all_access and opensearch_dashboards_server mappings
opensearch_dashboards.yml	opensearch_security.multitenancy.* settings removed in Dashboards 3.0
initial_api_calls.sh	    All of the above + hosts field in rolesmapping deprecated, no wait loop, references kibana_user/kibana_server which no longer exist

Better way in 3.6: With plugins.security.allow_default_init_securityindex: true already set, the cluster reads the YAML files and self-initializes the security index on every fresh start — no initial_api_calls.sh needed for day-1. The script becomes a day-2 tool only.

### opensearch_dashboards.yml

Removed opensearch_security.multitenancy.* settings (Dashboards 3.0 removed multitenancy)
Removed securitytenant from requestHeadersAllowlist
Renamed readonly role from kibana_read_only → opensearch_dashboards_read_only

#### initial_api_calls.sh

Full rewrite — key changes:

Adds a wait-for-cluster loop (won't run against an unready cluster)
Reads the password from $OPENSEARCH_INITIAL_ADMIN_PASSWORD env var (no hardcoded values)
Replaced opendistro_security_roles with opensearch_security_roles
Removed tenant_permissions from role creation
Replaced kibana_server with opensearch_dashboards_server
Removed deprecated hosts field from all rolesmapping calls

#### ATENȚIE!!!

The "better way": You don't need to run the script at all on first boot. The YAML files are now complete and `allow_default_init_securityindex: true` auto-loads them. The script is now a day-2 operations tool — run it only when pushing live changes to an already-running cluster.


### E3 — `.opendistro_security` index missing on os02–os05 (transient)
**Status:** `[~]` transient — resolves once os01 creates the index

**Log:**
```
[ERROR][o.o.s.c.ConfigurationLoaderSecurity7] [osXX] Failure no such index [.opendistro_security]
  retrieving configuration for [ACTIONGROUPS, ALLOWLIST, AUDIT, CONFIG, …]
```

**Cause:** Non-manager nodes attempt to load security config before the cluster manager (os01) has finished creating the `.opendistro_security` index. This is expected on first start and on a fresh cluster where data directories were cleared.

**Note:** Repeated occurrences on subsequent starts (with persisted data) indicate that os01 is not forming the cluster before the other nodes attempt to load config. Consider adding `depends_on` with `condition: service_healthy` on os02–os05 (currently commented out).

---

## WARNINGS

### W1 — Insecure file permissions on config files and certificates (all nodes)
**Status:** `[x]` fixed — 2026-04-17

**Fix applied:** Run on host before `docker compose up`:
```bash
find assets/opensearch/config -type d | xargs chmod 700
find assets/opensearch/config -type f | xargs chmod 600
find assets/ssl -type f -name "*.pem" | xargs chmod 600
find assets/opensearch/performance-analyzer -type f | xargs chmod 600
```
**Note:** The containers run as root so the files are readable. These `chmod` calls bring them to the 0700/0600 that the Security plugin checks for.

**Log:**
```
[WARN][o.o.s.OpenSearchSecurityPlugin] Directory /usr/share/opensearch/config
  has insecure file permissions (should be 0700)
[WARN][o.o.s.OpenSearchSecurityPlugin] File /usr/share/opensearch/config/opensearch.yml
  has insecure file permissions (should be 0600)
[WARN][o.o.s.OpenSearchSecurityPlugin] File /usr/share/opensearch/config/os01-key.pem
  has insecure file permissions (should be 0600)
… (same for all PEM files, jvm.options, log4j2.properties, opensearch-security/*.yml)
```

**Cause:** Files bind-mounted from the host into the container inherit host permissions (typically
`644` for files and `755` for directories), which are broader than the Security plugin expects.

**Fix (host side):** Tighten permissions on the `assets/` directory tree:
```bash
chmod 700 assets/opensearch/config assets/ssl
chmod 600 assets/opensearch/config/os*/opensearch.yml \
          assets/opensearch/config/os*/jvm.options \
          assets/opensearch/config/os*/log4j2.properties \
          assets/opensearch/config/os*/opensearch-security/*.yml \
          assets/ssl/*.pem
```

**Fix (Dockerfile for os01 built image):** Add a `RUN chmod` step:
```dockerfile
# Already handled by bind-mount permissions above, but for the built image:
RUN chmod 700 /usr/share/opensearch/config && \
    find /usr/share/opensearch/config -name "*.pem" -o -name "*.yml" -o -name "*.options" \
         -o -name "*.properties" | xargs chmod 600
```

---

### W2 — Compliance field-masking salt not configured (os01, os02)

**Status:** `[x]` fixed — 2026-04-17

**Log:**
```
[WARN][o.o.s.c.Salt] If you plan to use field masking pls configure compliance salt
  e1ukloTsQlOgPquJ to be a random string of 16 chars length identical on all nodes
```

**Why the salt is necessary:**

The OpenSearch Security plugin's compliance module can *mask* sensitive field values in
documents before returning them to the user (e.g. redacting credit card numbers or PII
fields based on an index mapping). Internally, masked values are replaced with an
**HMAC-SHA256 hash** of the original value, keyed with this salt.

Because the hash must be deterministic and equal across the entire cluster:

- Every node **must use the same salt**. Without it, each node generates an ephemeral
  random salt at startup. Shards on different nodes will then produce different hashes
  for the same original field value — searches and comparisons on masked fields will
  silently return inconsistent results.
- The salt must be set **before the first document is indexed** with field masking active.
  Changing it later invalidates all previously stored hashes and makes masked-field
  queries return no matches.
- The 16-character value must be treated as a secret; leaking it reduces the brute-force
  cost of reversing a masked value (since an attacker could pre-compute HMAC-SHA256 over
  the known candidate values).

**Fix applied:** `opensearch_local_certificates_creator.sh` now generates a fresh
16-character alphanumeric salt with `tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16`
and writes the same value to all five `opensearch.yml` files:

```yaml
plugins.security.compliance.salt: "<16-char-random-string>"
```

**Note:** In OpenSearch 2.x the setting was `opensearch_security.compliance.salt`; OpenSearch 3.x
renamed it to `plugins.security.compliance.salt` (under the standard `plugins.security.*` namespace).
Using the old key causes a hard `SettingsException` at startup and prevents all nodes from starting.

The script also sets secure file permissions immediately after certificate generation
(certs `600`, config dirs `700`, config files `600`), covering W1 as well. Re-run the
script only on a *fresh* cluster — regenerating the salt on an existing cluster that
already has indexed data with field masking active will break masked-field queries.

Generate a salt: `openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16`

---

### W3 — SQL Plugin datasource encryption master key not set (all nodes)
**Status:** `[x]` fixed — 2026-04-17

**Fix applied:** Added master key to all 5 `opensearch.yml` files:
```yaml
plugins.query.datasources.encryption.masterkey: "679528737e08ecf6b7db204cc523d62d"
```
**Note:** Key is identical on all nodes (required). Store the value securely — it cannot be changed without re-encrypting all datasource credentials.

**Log:**
```
[WARN][o.o.s.p.SQLPlugin] Master key is a required config for using create and update
  datasource APIs. Please set plugins.query.datasources.encryption.masterkey config
  in opensearch.yml in all the cluster nodes.
```

**Cause:** `plugins.query.datasources.encryption.masterkey` is not set. Without it the SQL
plugin's datasource create/update APIs are unavailable.

**Fix:** Add to every node's `opensearch.yml`:
```yaml
plugins.query.datasources.encryption.masterkey: "<32-char-AES-key>"
```
Generate: `openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32`

The key must be identical on all nodes and should be stored securely (e.g. in a `.env` variable
and referenced via Docker env).

---

### W4 — Missing `workload-management` plugin (os01, os02)
**Status:** `[ ]`

**Log:**
```
[WARN][o.o.p.PluginsService] Missing plugin [workload-management], dependency of [opensearch-security]
[WARN][o.o.p.PluginsService] Some features of this plugin may not function without the dependencies.
```

**Cause:** `opensearch-security` in OpenSearch 3.6 declares a soft dependency on the
`workload-management` plugin, which is not installed in the default OpenSearch image.

**Fix:** Install the plugin in the `Dockerfile`:
```dockerfile
RUN /usr/share/opensearch/bin/opensearch-plugin install --batch workload-management
```
Or accept the warning if workload-management features are not required (`[~]`).

---

### W5 — StreamTransportService not available (all nodes)
**Status:** `[~]` accepted if ML streaming is not needed

**Log:**
```
[WARN][o.o.m.a.p.TransportPredictionStreamTaskAction] StreamTransportService is not available.
[WARN][o.o.m.a.e.TransportExecuteStreamTaskAction] StreamTransportService is not available.
```

**Cause:** The ML streaming transport service requires additional configuration or a specific
node role. It is not active on any of the current nodes.

**Fix:** If streaming ML inference is required, configure the ML node with `node.roles: ml`.
Otherwise this warning can be suppressed or accepted.

---

### W6 — No audit log endpoint configured (os01, os02)
**Status:** `[ ]`

**Log:**
```
[WARN][o.o.s.a.r.AuditMessageRouter] No endpoint configured for categories
  [BAD_HEADERS, FAILED_LOGIN, MISSING_PRIVILEGES, …], using default endpoint
```

**Cause:** The audit log `config.yml` does not define explicit endpoints for any audit category.
All events fall back to the default `internal_opensearch` sink.

**Fix:** If external audit shipping is needed (e.g. to a SIEM), add an `endpoints` section to
the `opensearch-security/audit.yml` (or the `config.yml` audit block). Otherwise this is
informational — the default internal sink works.

---

### W7 — Repeated authentication failures from Dashboards healthcheck (os01)
**Status:** `[~]` transient — stops once security is initialised

**Log:**
```
[WARN][o.o.s.a.BackendRegistry] Authentication finally failed for null from 172.28.0.2:XXXXX
```

**Cause:** The `dashboards` container (172.28.0.2) performs health-check requests before the
security index is initialised. The Dashboards service does not wait for os01 to be fully ready
(the `depends_on` list only checks that containers are started, not healthy).

**Fix:** Add a proper healthcheck to the `dashboards` service and use `condition: service_healthy`
on its `depends_on` for os01/os02:
```yaml
# In docker-compose.yml, dashboards service:
depends_on:
  os01:
    condition: service_healthy
  os02:
    condition: service_healthy
```
Also add healthchecks to os02–os05 similar to os01.

---

### W8 — No resource usage stats for os02–os05 (os01)
**Status:** `[ ]` — caused by E1

**Log:**
```
[WARN][o.o.c.InternalClusterInfoService] No resource usage stats available for node: os02
[WARN][o.o.c.InternalClusterInfoService] No resource usage stats available for node: os03
… (os04, os05)
```

**Cause:** Performance Analyzer is disabled on all nodes (see **E1**). The cluster info service
cannot collect disk/memory stats from nodes that don't expose PA metrics.

**Fix:** Resolve **E1** (create the PA config directory and properties file on all nodes). If
Performance Analyzer is intentionally disabled, this warning can be suppressed by setting:
```yaml
# in opensearch.yml on os01
cluster.info.update.interval: 30s  # reduce polling frequency
```

---

### W9 — JVM / native access deprecation warnings (all nodes)
**Status:** `[~]` accepted — upstream library issue

**Log:**
```
WARNING: A restricted method in java.lang.System has been called
WARNING: java.lang.System::load has been called by org.bouncycastle.crypto.fips.NativeLoader$1
WARNING: sun.misc.Unsafe::objectFieldOffset has been called by net.bytebuddy…
WARNING: sun.misc.Unsafe::objectFieldOffset will be removed in a future release
WARNING: Unknown module: org.apache.arrow.memory.core specified to --add-opens
WARNING: Using incubator modules: jdk.incubator.vector
```

**Cause:** Third-party libraries (BouncyCastle FIPS, ByteBuddy, Apache Arrow) use deprecated
or restricted JVM APIs. These will be blocked in a future JDK release.

**Fix:** No action required now. These are upstream issues in dependencies bundled with
OpenSearch. Track the OpenSearch 3.x release notes for JDK compatibility updates.
Add `--enable-native-access=ALL-UNNAMED` to `jvm.options` to suppress the native-access
warning for now:
```
# In assets/opensearch/config/os*/jvm.options
--enable-native-access=ALL-UNNAMED
```

---

### W10 — SLF4J provider not found (all nodes)
**Status:** `[~]` accepted — upstream issue

**Log:**
```
[WARN][stderr] SLF4J: Failed to load class "org.slf4j.impl.StaticLoggerBinder".
[WARN][stderr] SLF4J(W): No SLF4J providers were found.
```

**Cause:** Some bundled libraries use SLF4J but OpenSearch does not ship an SLF4J binding.
Logging falls back to NOP (no-operation), meaning those libraries produce no log output.

**Fix:** No action needed unless debug logging from those specific libraries is required.

---

## docker-compose.yml Issues

### C1 — Duplicate `OPENSEARCH_INITIAL_ADMIN_PASSWORD` environment variable on os01
**Status:** `[x]` fixed — 2026-04-17

**Fix applied:** Removed the duplicate line from `docker-compose.yml` os01 `environment:` block.

**Location:** `docker-compose.yml`, `os01` service `environment:` block

**Issue:** The variable `OPENSEARCH_INITIAL_ADMIN_PASSWORD` is listed twice:
```yaml
- OPENSEARCH_INITIAL_ADMIN_PASSWORD=${OPENSEARCH_INITIAL_ADMIN_PASSWORD}
- OPENSEARCH_INITIAL_ADMIN_PASSWORD=${OPENSEARCH_INITIAL_ADMIN_PASSWORD}  # ← duplicate
```

**Fix:** Remove the duplicate line.

---

### C2 — os02 missing `node.roles` definition
**Status:** `[x]` fixed — 2026-04-17

**Fix applied:** Added to `docker-compose.yml` os02 `environment:` block:
```yaml
- node.roles=cluster_manager,data,ingest
```
os02 is a cluster manager candidate (`cluster.initial_cluster_manager_nodes=os01,os02`), so `cluster_manager` must be in its roles.

**Location:** `docker-compose.yml`, `os02` service `environment:` block

**Issue:** os01 explicitly sets `node.roles=cluster_manager`, os03–os05 set `data,ingest` or
`search`. os02 has no `node.roles` set, defaulting to **all roles** (cluster_manager + data +
ingest + remote_cluster_client), which may not be intended for a two-manager setup.

**Fix:** Add an explicit role definition to os02 matching the intended topology, e.g.:
```yaml
- node.roles=cluster_manager,data,ingest
```

---

### C3 — os02 missing `env_file: .env`
**Status:** `[x]` fixed — 2026-04-17

**Fix applied:** Added `env_file: .env` to os02, os03, os04, and os05 services in `docker-compose.yml`. All nodes now inherit `.env` variables consistently.

**Location:** `docker-compose.yml`, `os02` service

**Issue:** os01 loads `.env` via `env_file: .env`. os02–os05 rely solely on `environment:`
inline values. This means `OPENSEARCH_INITIAL_ADMIN_PASSWORD` is not passed to os02–os05,
and any future additions to `.env` won't be picked up automatically.

**Fix:** Add `env_file: .env` to all data/ingest nodes (os02–os05) for consistency:
```yaml
os02:
  …
  env_file: .env
  environment:
    …
```

---

### C4 — os03 `extra_hosts` maps its own hostname to `127.0.0.1`
**Status:** `[x]` fixed — 2026-04-17

**Fix applied:** Commented out the `extra_hosts` block on os03 in `docker-compose.yml` to match os04/os05.

**Location:** `docker-compose.yml`, `os03` service

**Issue:**
```yaml
extra_hosts:
  - "os03=127.0.0.1"
```
This forces os03 to resolve its own name to `localhost`. While it may work for self-connections,
it breaks the cluster transport layer if other containers attempt to connect to `os03` and the
DNS entry is overridden inside the container unexpectedly. It is also inconsistent with the
other nodes (os04, os05 have the equivalent line commented out).

**Fix:** Remove the `extra_hosts` block from os03, or comment it out to match the other nodes:
```yaml
# extra_hosts:
#   - "os03=127.0.0.1"
```

---

### C5 — os02 opensearch.yml has `enforce_hostname_verification` commented out
**Status:** `[x]` fixed — 2026-04-17

**Fix applied:** Uncommented `plugins.security.ssl.transport.enforce_hostname_verification: false` in `os02/opensearch.yml`. Also confirmed the same setting is present (commented-out) in os03–os05 — uncommented in all of them.

**Note:** Without this, os02 defaults to `true` and would fail transport-layer TLS with the self-signed SANs used by this cluster.

**Location:** `assets/opensearch/config/os02/opensearch.yml`

**Issue:** os01's config explicitly sets:
```yaml
plugins.security.ssl.transport.enforce_hostname_verification: false
```
os02's version has this line commented out:
```yaml
# plugins.security.ssl.transport.enforce_hostname_verification: false
```
With the default `true`, os02 will verify the hostname in the transport certificate, which may
fail with self-signed certs where the SAN does not exactly match the container hostname.

**Fix:** Uncomment the line in `os02/opensearch.yml` (and verify os03–os05 have the same):
```yaml
plugins.security.ssl.transport.enforce_hostname_verification: false
```

---

### C6 — os02 opensearch.yml missing security REST API settings present on os01
**Status:** `[x]` fixed — 2026-04-17

**Fix applied to `os02/opensearch.yml`:**
- Added `plugins.security.enable_snapshot_restore_privilege: true`
- Added `plugins.security.check_snapshot_restore_write_privileges: true`
- Added `plugins.security.restapi.password_validation_regex`, `password_min_length`, `password_score_based_validation_strength`
- Added `plugins.security.allow_default_init_securityindex: true`
- Fixed stale role reference: `kibana_server` → removed from `restapi.roles_enabled` (not a valid role in 3.6) — updated on **all 5 nodes** to match os01's list: `["all_access", "security_rest_api_access", "dashboards"]`

---

## NEW WARNINGS (startup-4, 2026-04-17)

### N1 — SecurityAnalyticsPlugin: Failed to initialize LogType config index
**Status:** `[~]` transient — accepted

**Log:**
```
[WARN][o.o.s.SecurityAnalyticsPlugin] [osXX] Failed to initialize LogType config index and builtin log types
```

**Cause:** On first start, the SecurityAnalytics plugin creates `.opensearch-sap-log-types-config` and immediately tries to write builtin log types to it. The index has `number_of_replicas: 2` which isn't satisfiable until shards are allocated. The write times out after the first attempt. The plugin retries automatically and succeeds — subsequent INFO lines in the log confirm the index is created and mapped correctly.

**Resolution:** No action needed. The warning disappears on subsequent starts once the shard is already allocated.

---

### N2 — DanglingIndicesState: `gateway.auto_import_dangling_indices` is disabled
**Status:** `[~]` accepted — informational

**Log:**
```
[WARN][o.o.g.DanglingIndicesState] gateway.auto_import_dangling_indices is disabled,
  dangling indices will not be automatically detected or imported
```

**Cause:** OpenSearch 3.x defaults `gateway.auto_import_dangling_indices: false`. This is the recommended secure default — dangling index auto-import is a potential data-integrity risk. The warning is informational; there are no actual dangling indices.

---

### N3 — ConfigOverridesClusterSettingHandler: empty config override string
**Status:** `[~]` accepted — benign

**Log:**
```
[WARN][o.o.p.c.s.h.ConfigOverridesClusterSettingHandler] Config override setting update called with empty string. Ignoring.
```

**Cause:** The Performance Analyzer plugin sends an empty override string when `performance-analyzer.enabled=false`. The handler logs and ignores it. No functional impact.

---

---

## NEW ISSUES (fresh cluster restart, 2026-04-17)

### E4 — `SettingsException: unknown setting [opensearch_security.compliance.salt]` (all nodes)
**Status:** `[x]` fixed — 2026-04-17

**Log:**
```
SettingsException[unknown setting [opensearch_security.compliance.salt]
  did you mean [plugins.security.compliance.salt]?]; nested: IllegalArgumentException[…]
```

**Cause:** In OpenSearch 3.x the entire security plugin namespace was renamed from
`opensearch_security.*` to `plugins.security.*`. The compliance salt setting that was added
during W2 used the old 2.x key name, causing a hard `SettingsException` at startup that
crashed every node before any index or network operation could happen.

**Fix applied:**
```bash
find assets/opensearch/config -name opensearch.yml | \
  xargs sed -i 's/^opensearch_security\.compliance\.salt:/plugins.security.compliance.salt:/'
```
Also updated `opensearch_local_certificates_creator.sh` to write the key under the correct
`plugins.security.compliance.salt` name going forward.

**Lesson:** When copying settings from OpenSearch 2.x docs/examples into a 3.x cluster, always
check for the `opensearch_security.*` → `plugins.security.*` rename. Any unknown setting in
opensearch.yml causes a hard crash on all nodes.

---

### E5 — Cluster formation failure: all nodes stuck in discovery loop (all nodes)
**Status:** `[x]` fixed — 2026-04-17

**Log:**
```
[WARN][o.o.c.c.Coordinator] [osXX] cluster-manager not discovered yet, …
  have discovered [{os01}{…}{172.27.0.2:9300}{m}…]; …
  NodeNotConnectedException[…]; discovery will continue using […]
[INFO][o.o.c.c.Coordinator] [osXX] starting an election with …
  term: 87 (and counting)
```

**Cause:** `os01` was configured with **two Docker networks**: `osearch` (172.28.x) and
`knonikl` (172.27.x). Docker assigns the container's primary interface from the **last network
it joins**, which for `os01` was `knonikl` (172.27.0.x). `os01` therefore published
`172.27.0.x:9300` as its transport address.

`os02`–`os05` are only connected to `osearch` (172.28.x) and cannot reach any address in the
`172.27.0.x` subnet. All discovery attempts to `os01` timed out, and the cluster-manager
election loop ran indefinitely (election term escalated past 80+).

**Fix applied:** Removed `knonikl` from `os01`'s `networks:` in `docker-compose.yml`:
```yaml
# Before:
os01:
  networks:
    - osearch
    - knonikl   # ← removed

# After:
os01:
  networks:
    - osearch
```
`os01` now resolves to the same `osearch` subnet as all other nodes.

**Note:** `dashboards` correctly remains on both `osearch` (to reach os01/os02) and `knonikl`
(to serve the host browser) — no change needed there.

**Lesson:** When a Docker service is attached to multiple networks, its published address
(used by other services for discovery) is determined by the network join order. For cluster
nodes that must reach each other, every node **must share exactly one common network** for
transport communication. Multi-homing should only be applied to edge/gateway services.

---

### C7 — `internal_users.yml` password hash does not match `OPENSEARCH_INITIAL_ADMIN_PASSWORD`
**Status:** `[x]` fixed — 2026-04-17

**Log:**
```
[WARN][o.o.s.a.BackendRegistry] [os01] Authentication finally failed for admin from 172.27.0.3:XXXXX
```
(Repeated every ~5 s — the `os01` healthcheck `curl … -u 'admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}'`
was rejected, and `dashboards` could not authenticate.)

**Cause:** `assets/opensearch/config/os01/opensearch-security/internal_users.yml` contained a
bcrypt hash generated from the old default password `admin`, not from the intended password
`test@Cici24#ANA` stored in `.env` as `OPENSEARCH_INITIAL_ADMIN_PASSWORD`.

Why the Docker auto-substitution did not help: the OpenSearch container entrypoint script
substitutes `$ADMIN_PASSWORD_HASH` **placeholder text** in `internal_users.yml` at container
start. Because our file already has a real bcrypt hash (not the placeholder), the substitution
finds nothing to replace and the old hash is used as-is.

**Fix applied:**
1. Generated the correct bcrypt hash for `test@Cici24#ANA`:
   ```bash
   docker exec os01 /usr/share/opensearch/plugins/opensearch-security/tools/hash.sh \
     -p 'test@Cici24#ANA'
   # → $2y$12$yhNT2gJk4FXQ7ZstjdqxWeh.ld55jnI2jC./euDVqsoaRt6kY/XSy
   ```
2. Updated all three users in `internal_users.yml` (`admin`, `dashboards`, `kibanaserver`)
   with the new hash.
3. Pushed the updated config to the live cluster without restart:
   ```bash
   docker exec os01 \
     /usr/share/opensearch/plugins/opensearch-security/tools/securityadmin.sh \
       -cd /usr/share/opensearch/config/opensearch-security \
       -icl -nhnv \
       -cacert /usr/share/opensearch/config/root-ca.pem \
       -cert  /usr/share/opensearch/config/admin.pem \
       -key   /usr/share/opensearch/config/admin-key.pem \
       -h os01 -p 9200
   ```

**Note on `securityadmin.sh` port:** In OpenSearch 3.x the tool uses the REST API (port 9200),
not the transport layer (port 9300). Passing `-p 9300` produces a `Connection is closed` error.

**Recommendation:** When `OPENSEARCH_INITIAL_ADMIN_PASSWORD` is changed in `.env`, regenerate
the bcrypt hash (using `hash.sh` inside any running node) and update `internal_users.yml`
before the next clean cluster start. Alternatively, add hash generation to
`opensearch_local_certificates_creator.sh`:
```bash
NEW_HASH=$(docker run --rm opensearchproject/opensearch:${VERSION} \
  /usr/share/opensearch/plugins/opensearch-security/tools/hash.sh -p "$OPENSEARCH_INITIAL_ADMIN_PASSWORD" \
  | tail -1)
# then sed-replace the hash in internal_users.yml
```

---

*Last updated: 2026-04-17 (E4: compliance salt namespace rename; E5: os01 dual-network transport split; C7: internal_users.yml password hash mismatch; C8: healthcheck password expansion + dashboards startup ordering)*

---

### C8 — os01 healthcheck single-quoted password + dashboards starts before security is ready
**Status:** `[x]` fixed — 2026-04-17

**Log (os01):**
```
[WARN][o.o.s.a.BackendRegistry] [os01] Authentication finally failed for null from 172.28.0.2:XXXXX
```
(Repeated every ~5 s immediately after `securityadmin.sh` was run on a fresh data directory.)

**Root cause — two compounding bugs:**

**Bug 1 — healthcheck password never expands (single-quote quoting error)**

The healthcheck in `docker-compose.yml` was:
```yaml
test: ["CMD-SHELL", "curl -k -XGET https://os01:9200/_cat/nodes?pretty -u 'admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}' || exit 1"]
```
POSIX single quotes prevent shell variable expansion. Docker runs CMD-SHELL via
`/bin/sh -c "..."`. The environment variable is never substituted; curl sends the literal
string `admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}` as the password, causing every
healthcheck attempt to fail with HTTP 401.

A second issue: curl exits with code **0** even on a 401 response (it received a valid HTTP
response). Without `--fail`, the `|| exit 1` is never triggered and the healthcheck always
reports success — even while the cluster is refusing authentication. Docker therefore marks
os01 as `(healthy)` before security is actually functional.

**Bug 2 — dashboards starts before the security index is initialized**

`dashboards` had:
```yaml
depends_on:
  - os01
  - os02
  - os03
```
Without `condition: service_healthy`, Docker only waits for the listed containers to *start*,
not for them to pass their healthcheck. On a fresh data reset (empty `.opendistro_security`
index), `dashboards` starts within ~1 s of os01, long before OpenSearch Security has
initialised the index from the YAML config files.

During this window, `o.o.s.a.BackendRegistry` has **no authenticators loaded** — the
authenticator chain has not yet been populated from the security index. Any HTTP request
that reaches the BackendRegistry at this point cannot have its username extracted, so it
is logged as `null`. The dashboards container probes `https://os01:9200/` every ~2–5 s
(its backend health check), generating the repeated `null` auth failures.

**Fix applied:**

1. Healthcheck: changed single quotes to `\"` (YAML-escaped double quotes) so the shell
   expands `${OPENSEARCH_INITIAL_ADMIN_PASSWORD}`; added `--fail` so curl exits non-zero on
   4xx/5xx; removed the now-redundant `|| exit 1`; increased `timeout` to 10s and `retries`
   to 30 to allow more time for a fresh security-index initialization:
   ```yaml
   healthcheck:
     test: ["CMD-SHELL", "curl -ks --fail https://os01:9200/_cat/nodes?pretty -u \"admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}\""]
     interval: 5s
     timeout: 10s
     retries: 30
   ```

2. Dashboards `depends_on`: changed to `condition: service_healthy` so dashboards only starts
   after os01's healthcheck passes (i.e., after the Security plugin has loaded its authenticators
   and the cluster is accepting authenticated requests):
   ```yaml
   depends_on:
     os01:
       condition: service_healthy
   ```

**Effect:** On a clean data reset, os01 is only marked healthy once `curl --fail` can get a
200 response from `/_cat/nodes` with valid credentials. Dashboards won't start connecting
until that point, so it never hits the BackendRegistry while the authenticators are absent.
The `null` auth failures no longer appear.

---

### E6 — SecurityPlugin fails to load — `root-ca.pem is a directory` (all nodes)
**Status:** `[x]` fixed — 2026-05-03

**Log:**

```
org.opensearch.bootstrap.StartupException: java.lang.IllegalStateException:
  failed to load plugin class [org.opensearch.security.OpenSearchSecurityPlugin]
Caused by: org.opensearch.OpenSearchException:
  /usr/share/opensearch/config/root-ca.pem - is a directory
```

**Cause:** The certificate files in `assets/ssl/` were missing (had never been generated).
When Docker bind-mounts a host path that does not exist, it auto-creates an empty
**directory** at that path. The Security plugin then tried to read `root-ca.pem` as a PEM
file and immediately failed because it was a directory, not a file. This affected every
node because all of them mount `root-ca.pem`, `root-ca-key.pem`, `admin.pem`, and their
own node cert from `assets/ssl/`.

**Root cause chain:**

1. `opensearch_local_certificates_creator.sh` had not been run before `docker compose up`.
2. Docker created empty directories for every missing bind-mount source.
3. The Security SSL loader threw `is a directory` instead of `file not found`, masking the
   real missing-cert cause.

**Fix applied (2026-05-03):**

1. Stopped all containers: `docker compose down`
2. Removed the root-owned empty stub directories:
   ```
   sudo rm -rf assets/ssl/root-ca.pem assets/ssl/root-ca-key.pem \
               assets/ssl/admin.pem assets/ssl/admin-key.pem \
               assets/ssl/os{01..05}.pem assets/ssl/os{01..05}-key.pem
   sudo chown -R nicolaie:nicolaie assets/ssl/
   ```
3. Generated all TLS certificates:
   ```
   bash opensearch_local_certificates_creator.sh
   ```
4. Restarted: `docker compose up -d` — all nodes came up healthy.

**Prevention:** Always run `opensearch_local_certificates_creator.sh` before the first `docker compose up` on a fresh clone or after `restart-to-clear-cluster.sh`.
The script also updates the compliance salt and SQL master key in all `opensearch.yml` files so those settings stay in sync with the newly generated certs.
