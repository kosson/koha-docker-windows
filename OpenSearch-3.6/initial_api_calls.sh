#!/bin/bash
# OpenSearch Security post-boot configuration script
# Updated for OpenSearch 3.6 — removes all deprecated 2.x / OpenDistro fields.
#
# WHEN TO RUN THIS SCRIPT:
#   On a normal first start you do NOT need this script — the cluster initialises the
#   security index automatically from the YAML files in opensearch-security/ because
#   plugins.security.allow_default_init_securityindex=true is set in opensearch.yml.
#
#   Run this script manually only when you need to push live changes to a running
#   cluster without restarting (e.g. after wiping data dirs but keeping the cluster up,
#   or when updating passwords/roles on an already-initialised cluster).
#
# USAGE:
#   cd OpenSearch-3.6
#   source .env          # exports OPENSEARCH_INITIAL_ADMIN_PASSWORD etc.
#   bash initial_api_calls.sh

set -euo pipefail

CONFIG_FILE="opensearch_installer_vars.cfg"
BASE_URL="https://localhost:9200"
CERT="assets/ssl/admin.pem"
KEY="assets/ssl/admin-key.pem"
CURL_BASE="-sk --cert ${CERT} --key ${KEY}"

# ---------------------------------------------------------------------------
# Helper: run an API call with pretty-printed status
# ---------------------------------------------------------------------------
api() {
    local method="$1" path="$2" desc="${3:-}" data="${4:-}"
    echo ""
    echo ">>> ${desc:-${method} ${path}}"
    if [[ -n "${data}" ]]; then
        curl ${CURL_BASE} -X"${method}" "${BASE_URL}${path}" \
             -H 'Content-Type: application/json' -d "${data}"
    else
        curl ${CURL_BASE} -X"${method}" "${BASE_URL}${path}"
    fi
    echo ""
}

# ---------------------------------------------------------------------------
# Wait until the cluster is at least yellow before doing anything
# ---------------------------------------------------------------------------
wait_for_cluster() {
    local max=30 attempt=0 status=""
    echo "Waiting for cluster health (yellow or green) ..."
    while (( attempt < max )); do
        status=$(curl ${CURL_BASE} -s "${BASE_URL}/_cluster/health" \
                 | grep -o '"status":"[^"]*"' | cut -d'"' -f4 2>/dev/null || true)
        if [[ "${status}" == "green" || "${status}" == "yellow" ]]; then
            echo "Cluster is ready (status: ${status})"
            return 0
        fi
        (( attempt++ ))
        echo "  attempt ${attempt}/${max}: status='${status}', retrying in 5s ..."
        sleep 5
    done
    echo "ERROR: cluster did not become ready after $(( max * 5 ))s" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: ${CONFIG_FILE} not found. Run from the OpenSearch-3.6 directory." >&2
    exit 1
fi
source "${CONFIG_FILE}"

# OPENSEARCH_INITIAL_ADMIN_PASSWORD must be exported (e.g. via `source .env`)
ADMIN_PASS="${OPENSEARCH_INITIAL_ADMIN_PASSWORD:-}"
if [[ -z "${ADMIN_PASS}" ]]; then
    echo "ERROR: OPENSEARCH_INITIAL_ADMIN_PASSWORD is not set." >&2
    echo "       Run:  source .env && bash initial_api_calls.sh" >&2
    exit 1
fi

wait_for_cluster

# ---------------------------------------------------------------------------
# 1. Internal users
#    - Use opensearch_security_roles (opendistro_security_roles removed in 3.x)
#    - "op":"add" works as upsert on the OpenSearch Security PATCH endpoint
# ---------------------------------------------------------------------------
api "PATCH" "/_plugins/_security/api/internalusers" "Update admin user" \
'[{"op":"add","path":"/admin","value":{
  "password":"'"${ADMIN_PASS}"'",
  "backend_roles":["admin"],
  "opendistro_security_roles":["all_access"]
}}]'

api "PATCH" "/_plugins/_security/api/internalusers" "Update dashboards user" \
'[{"op":"add","path":"/dashboards","value":{
  "password":"'"${ADMIN_PASS}"'",
  "backend_roles":["admin","dashboards"],
  "opendistro_security_roles":["dashboards","opensearch_dashboards_server"]
}}]'

# ---------------------------------------------------------------------------
# 2. Custom dashboards role
#    - tenant_permissions removed — multitenancy was removed in OpenSearch 3.0
# ---------------------------------------------------------------------------
api "PUT" "/_plugins/_security/api/roles/dashboards" "Create/update dashboards role" \
'{
  "cluster_permissions":["cluster_all","indices_monitor"],
  "index_permissions":[{
    "index_patterns":["*"],
    "dls":"",
    "fls":[],
    "masked_fields":[],
    "allowed_actions":["crud","search"]
  }]
}'

# ---------------------------------------------------------------------------
# 3. Role mappings
#    - hosts field is deprecated; use backend_roles + users instead
#    - kibana_server renamed to opensearch_dashboards_server in 3.x
# ---------------------------------------------------------------------------
api "PUT" "/_plugins/_security/api/rolesmapping/own_index" "Map own_index" \
'{
  "backend_roles":[],
  "users":["*"],
  "description":"Allow full access to an index named like the username"
}'

api "PUT" "/_plugins/_security/api/rolesmapping/opensearch_dashboards_server" \
    "Map opensearch_dashboards_server (Dashboards service account)" \
'{
  "backend_roles":["dashboards"],
  "users":["dashboards"]
}'

api "PUT" "/_plugins/_security/api/rolesmapping/all_access" "Map all_access" \
'{
  "backend_roles":["admin"],
  "users":["admin","CN=admin,OU=DFCTI,O=NIPNE,L=MAGURELE,ST=ILFOV,C=RO"]
}'

api "PUT" "/_plugins/_security/api/rolesmapping/dashboards" "Map custom dashboards role" \
'{
  "backend_roles":["admin","dashboards"],
  "users":["dashboards","admin"]
}'

api "PUT" "/_plugins/_security/api/rolesmapping/readall" "Map readall" \
'{
  "backend_roles":["admin","readall"],
  "users":["dashboards","admin"]
}'

echo ""
echo "=== Done. Security configuration applied to ${BASE_URL} ==="
