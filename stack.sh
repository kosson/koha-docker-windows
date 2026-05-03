#!/usr/bin/env bash
# stack.sh — Manage the full Koha ILS + OpenSearch 3.6 + MariaDB stack
#
# Usage: ./stack.sh <command> [options]
#   start     Build (if requested) and start the full stack (default)
#   stop      Stop all services gracefully
#   restart   Quick restart: reset DB + recreate Koha container (no OS restart)
#   status    Show running containers and OpenSearch cluster health
#   logs      Tail Koha container logs
#   build     Build images only (no start)
#
# Run './stack.sh --help' for full usage.

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths — all derived from this script's location
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSEARCH_DIR="${SCRIPT_DIR}/OpenSearch-3.6"
TRAEFIK_DIR="${SCRIPT_DIR}/traefik"
KOHA_COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
KOHA_ENV_FILE="${SCRIPT_DIR}/env/.env"
KOHA_PROJECT_DIR="${SCRIPT_DIR}"

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; RESET=''
fi

ts()   { date '+%H:%M:%S'; }
log()  { echo -e "${BLUE}[$(ts)]${RESET} $*"; }
ok()   { echo -e "${GREEN}[$(ts)] ✓${RESET} $*"; }
warn() { echo -e "${YELLOW}[$(ts)] ⚠${RESET}  $*"; }
die()  { echo -e "${RED}[$(ts)] ✗  $*${RESET}" >&2; exit 1; }
hdr()  { echo -e "\n${BOLD}${CYAN}── $* ──${RESET}"; }

# ---------------------------------------------------------------------------
# Config — read from env files, with safe fallbacks
# ---------------------------------------------------------------------------
_env_val() {
  # Usage: _env_val FILE KEY [DEFAULT]
  local file="$1" key="$2" default="${3:-}"
  local val
  val=$(grep -E "^${key}=" "${file}" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'" || true)
  echo "${val:-${default}}"
}

KOHA_INSTANCE="$(_env_val "${KOHA_ENV_FILE}" KOHA_INSTANCE kohadev)"
KOHA_DOMAIN="$(_env_val   "${KOHA_ENV_FILE}" KOHA_DOMAIN   .myDNSname.org)"
KOHA_INTRANET_SUFFIX="$(_env_val "${KOHA_ENV_FILE}" KOHA_INTRANET_SUFFIX -intra)"
KOHA_OPAC_PORT="$(_env_val      "${KOHA_ENV_FILE}" KOHA_OPAC_PORT      8080)"
KOHA_INTRANET_PORT="$(_env_val  "${KOHA_ENV_FILE}" KOHA_INTRANET_PORT  8081)"
KOHA_USER="$(_env_val "${KOHA_ENV_FILE}" KOHA_USER koha)"
KOHA_PASS="$(_env_val "${KOHA_ENV_FILE}" KOHA_PASS koha)"
TRAEFIK_HTTP_PORT="$(_env_val "${TRAEFIK_DIR}/.env" TRAEFIK_HTTP_PORT 80)"
TRAEFIK_DASHBOARD_PORT="$(_env_val "${TRAEFIK_DIR}/.env" TRAEFIK_DASHBOARD_PORT 8083)"
# Admin password: prefer the OS .env file (source of truth for the cluster)
OS_ADMIN_PASS="$(_env_val "${OPENSEARCH_DIR}/.env" OPENSEARCH_INITIAL_ADMIN_PASSWORD \
  "$(_env_val "${KOHA_ENV_FILE}" OPENSEARCH_INITIAL_ADMIN_PASSWORD 'changeme')")"

DB_NAME="koha_${KOHA_INSTANCE}"
DB_USER="koha_${KOHA_INSTANCE}"
KOHA_PROJECT="$(basename "${KOHA_PROJECT_DIR}")"   # → koha-docker
DB_CONTAINER="${KOHA_PROJECT}-db-1"

# ---------------------------------------------------------------------------
# Compose wrappers
# ---------------------------------------------------------------------------
koha_compose() {
  docker compose \
    -f "${KOHA_COMPOSE_FILE}" \
    --env-file "${KOHA_ENV_FILE}" \
    --project-directory "${KOHA_PROJECT_DIR}" \
    "$@"
}

os_compose() {
  docker compose \
    -f "${OPENSEARCH_DIR}/docker-compose.yml" \
    --env-file "${OPENSEARCH_DIR}/.env" \
    --project-directory "${OPENSEARCH_DIR}" \
    "$@"
}

traefik_compose() {
  docker compose \
    -f "${TRAEFIK_DIR}/docker-compose.yaml" \
    --env-file "${TRAEFIK_DIR}/.env" \
    --project-directory "${TRAEFIK_DIR}" \
    "$@"
}

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------
check_prereqs() {
  log "Checking prerequisites..."
  command -v docker   >/dev/null 2>&1 || die "docker not found in PATH"
  docker compose version >/dev/null 2>&1 || die "Docker Compose plugin not found"
  [[ -f "${KOHA_ENV_FILE}" ]] || die "env/.env not found — copy and configure it first"
  [[ -f "${OPENSEARCH_DIR}/docker-compose.yml" ]] \
    || die "OpenSearch-3.6/docker-compose.yml not found"
  [[ -f "${TRAEFIK_DIR}/docker-compose.yaml" ]] \
    || die "traefik/docker-compose.yaml not found"
  ok "Prerequisites OK"
}

# ---------------------------------------------------------------------------
# Docker network
# ---------------------------------------------------------------------------
ensure_frontend_network() {
  if ! docker network inspect frontend >/dev/null 2>&1; then
    log "Creating 'frontend' Docker network (required by Traefik)..."
    docker network create frontend
    ok "Network 'frontend' created."
  else
    ok "Network 'frontend' already exists."
  fi
}

# ---------------------------------------------------------------------------
# Traefik
# ---------------------------------------------------------------------------
start_traefik() {
  hdr "Starting Traefik reverse proxy"
  ensure_frontend_network
  # Bring up only if not already running
  if traefik_compose ps --status running traefik 2>/dev/null | grep -q traefik; then
    ok "Traefik is already running."
  else
    traefik_compose up -d traefik
    ok "Traefik started (HTTP :${TRAEFIK_HTTP_PORT}, dashboard :${TRAEFIK_DASHBOARD_PORT})."
  fi
}

stop_traefik() {
  hdr "Stopping Traefik"
  traefik_compose stop traefik 2>/dev/null || true
  ok "Traefik stopped."
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
build_opensearch() {
  hdr "Building OpenSearch images"
  log "Installing analysis-icu plugin into all 5 node images..."
  pushd "${OPENSEARCH_DIR}" > /dev/null
  docker compose build
  popd > /dev/null
  ok "OpenSearch images built."
}

build_koha() {
  hdr "Building Koha image"
  koha_compose build koha
  ok "Koha image built."
}

# ---------------------------------------------------------------------------
# OpenSearch
# ---------------------------------------------------------------------------
start_opensearch() {
  hdr "Starting OpenSearch 3.6 cluster"
  pushd "${OPENSEARCH_DIR}" > /dev/null
  docker compose up -d
  popd > /dev/null
  ok "OpenSearch containers started (os01–os05 + dashboards)."
}

wait_opensearch_green() {
  log "Waiting for OpenSearch cluster to reach green status..."
  warn "This may take up to 5 minutes on first start (security plugin initialises)."
  local attempts=0 max=72  # 6 minutes (72 × 5 s)
  while (( attempts < max )); do
    if curl -sk -u "admin:${OS_ADMIN_PASS}" \
        https://localhost:9200/_cluster/health 2>/dev/null \
        | grep -q '"status":"green"'; then
      echo ""
      ok "OpenSearch cluster is green."
      return 0
    fi
    (( ++attempts ))
    printf "\r  [%d/%d] waiting..." "${attempts}" "${max}"
    sleep 5
  done
  echo ""
  die "OpenSearch cluster did not reach green status after $(( max * 5 )) seconds."
}

stop_opensearch() {
  hdr "Stopping OpenSearch cluster"
  pushd "${OPENSEARCH_DIR}" > /dev/null
  docker compose down
  popd > /dev/null
  ok "OpenSearch stopped."
}

# ---------------------------------------------------------------------------
# MariaDB + Memcached
# ---------------------------------------------------------------------------
start_support_services() {
  hdr "Starting MariaDB + Memcached"
  koha_compose up -d db memcached
  ok "Support services started."
}

wait_db_ready() {
  log "Waiting for MariaDB to accept connections..."
  local attempts=0 max=30  # 60 seconds
  while (( attempts < max )); do
    if docker exec "${DB_CONTAINER}" \
        mysqladmin ping -uroot -ppassword --silent 2>/dev/null; then
      ok "MariaDB is ready."
      return 0
    fi
    (( ++attempts ))
    printf "\r  [%d/%d] waiting..." "${attempts}" "${max}"
    sleep 2
  done
  echo ""
  die "MariaDB did not become ready after $(( max * 2 )) seconds."
}

reset_database() {
  hdr "Recreating Koha database"
  log "Dropping and recreating '${DB_NAME}'..."
  docker exec "${DB_CONTAINER}" mysql -uroot -ppassword -e "
    DROP DATABASE IF EXISTS ${DB_NAME};
    CREATE DATABASE ${DB_NAME}
      CHARACTER SET utf8mb4
      COLLATE utf8mb4_unicode_ci;
    GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%';
    FLUSH PRIVILEGES;"
  ok "Database '${DB_NAME}' ready."
}

stop_support_services() {
  hdr "Stopping MariaDB + Memcached"
  koha_compose stop db memcached 2>/dev/null || true
  ok "Support services stopped."
}

# ---------------------------------------------------------------------------
# Koha container
# ---------------------------------------------------------------------------
start_koha() {
  hdr "Starting Koha container"
  # Export LOAD_DEMO_DATA so Docker Compose picks it up via the environment: block
  # in docker-compose.yml, overriding whatever is in env/.env at this point.
  export LOAD_DEMO_DATA
  local demo_label; demo_label="$( [[ "${LOAD_DEMO_DATA}" == "no" ]] && echo "clean (no demo data)" || echo "with demo data" )"
  log "Demo data mode: ${demo_label}"
  koha_compose up -d --force-recreate koha
  ok "Koha container started (${demo_label})."
}

stop_koha() {
  hdr "Stopping Koha container"
  koha_compose stop koha 2>/dev/null || true
  ok "Koha container stopped."
}

follow_logs() {
  hdr "Koha startup logs"
  warn "Startup takes 5–15 minutes. Watching for key milestones..."
  warn "Press Ctrl-C at any time to detach — the stack will keep running."
  echo ""

  # Stream logs and annotate milestones on the fly
  koha_compose logs -f koha 2>&1 | while IFS= read -r line; do
    echo "${line}"
    case "${line}" in
      *"koha-testing-docker has started up"*)
        local port_suffix=""
        [[ "${TRAEFIK_HTTP_PORT}" != "80" ]] && port_suffix=":${TRAEFIK_HTTP_PORT}"
        echo ""
        echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${GREEN}${BOLD}║   Stack fully started and ready!                         ║${RESET}"
        echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${GREEN}${BOLD}║${RESET}  Via Traefik (recommended):║${RESET}"
        echo -e "${GREEN}${BOLD}║${RESET}    OPAC    : http://${KOHA_INSTANCE}${KOHA_DOMAIN}${port_suffix}║${RESET}"
        echo -e "${GREEN}${BOLD}║${RESET}    Staff   : http://${KOHA_INSTANCE}${KOHA_INTRANET_SUFFIX}${KOHA_DOMAIN}${port_suffix}║${RESET}"
        echo -e "${GREEN}${BOLD}║${RESET}  Direct (fallback, no DNS needed):║${RESET}"
        echo -e "${GREEN}${BOLD}║${RESET}    OPAC    : http://localhost:${KOHA_OPAC_PORT}║${RESET}"
        echo -e "${GREEN}${BOLD}║${RESET}    Staff   : http://localhost:${KOHA_INTRANET_PORT}║${RESET}"
        echo -e "${GREEN}${BOLD}║${RESET}  Login     : ${KOHA_USER} / ${KOHA_PASS}║${RESET}"
        echo -e "${GREEN}${BOLD}║${RESET}  Dashbrd   : http://dashboards.localhost${port_suffix}║${RESET}"
        echo -e "${GREEN}${BOLD}║${RESET}  Traefik   : http://localhost:${TRAEFIK_DASHBOARD_PORT}║${RESET}"
        local demo_note; demo_note="$( [[ "${LOAD_DEMO_DATA:-yes}" == "no" ]] && echo "clean (no demo data)" || echo "with demo data" )"
        echo -e "${GREEN}${BOLD}║${RESET}  Catalogue : ${demo_note}║${RESET}"
        echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------
show_status() {
  hdr "Container status"
  echo ""
  echo -e "${BOLD}── Koha stack ──────────────────────────────${RESET}"
  koha_compose ps 2>/dev/null || echo "  (not running)"
  echo ""
  echo -e "${BOLD}── OpenSearch cluster ──────────────────────${RESET}"
  os_compose ps 2>/dev/null || echo "  (not running)"
  echo ""
  echo -e "${BOLD}── OpenSearch health ───────────────────────${RESET}"
  local health
  health=$(curl -sk -u "admin:${OS_ADMIN_PASS}" \
    https://localhost:9200/_cluster/health 2>/dev/null || echo '{"error":"unreachable"}')
  echo "${health}" | python3 -m json.tool 2>/dev/null || echo "${health}"
  echo ""
  echo -e "${BOLD}── Traefik ──────────────────────────────────${RESET}"
  traefik_compose ps 2>/dev/null || echo "  (not running)"
  echo ""
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF

${BOLD}stack.sh${RESET} — Manage the Koha ILS + OpenSearch 3.6 + MariaDB stack

${BOLD}Usage:${RESET}
  $(basename "$0") <command> [options]

${BOLD}Commands:${RESET}
  start       Start the full stack (default when no command given)
  stop        Stop all services (OpenSearch + Koha stack)
  restart     Quick restart: reset DB + recreate Koha container only
              (skips OpenSearch restart — use when OS is already running)
  status      Show running containers and OpenSearch cluster health
  logs        Tail Koha container logs
  build       Build images without starting anything

${BOLD}Options for 'start' and 'build':${RESET}
  --build-opensearch    Rebuild the custom OpenSearch images (analysis-icu)
  --build-koha          Rebuild the Koha dev container image
  --build               Rebuild both OpenSearch and Koha images
  --no-fresh-db         Skip the database drop/recreate (preserve existing data)
  --no-logs             Do not tail Koha startup logs after starting
  --with-demo-data      Load sample MARC records, items, and patron data (default)
  --no-demo-data        Start with an empty catalogue — superlibrarian account only

${BOLD}Examples:${RESET}
  $(basename "$0") start                    # Fresh DB + demo data, follow logs
  $(basename "$0") start --no-demo-data     # Fresh DB, clean catalogue (no sample records)
  $(basename "$0") start --with-demo-data   # Explicitly load demo data (same as default)
  $(basename "$0") start --build            # Rebuild all images, then start
  $(basename "$0") start --build-opensearch # Rebuild OS images only, then start
  $(basename "$0") start --no-fresh-db      # Restart without wiping the database
  $(basename "$0") start --no-logs          # Start without tailing logs
  $(basename "$0") restart                  # Quick restart (DB reset + koha only)
  $(basename "$0") restart --no-demo-data   # Quick restart, clean catalogue
  $(basename "$0") stop                     # Stop everything
  $(basename "$0") status                   # Check what's running
  $(basename "$0") logs                     # Attach to Koha logs
  $(basename "$0") build --build-opensearch # Build OS images only

EOF
}

# ---------------------------------------------------------------------------
# Command dispatcher
# ---------------------------------------------------------------------------

# Default command
COMMAND="start"
BUILD_OPENSEARCH=false
BUILD_KOHA=false
FRESH_DB=true
FOLLOW_LOGS=true
# Read LOAD_DEMO_DATA from env/.env (default 'yes'); --no-demo-data / --with-demo-data override
LOAD_DEMO_DATA="$(_env_val "${KOHA_ENV_FILE}" LOAD_DEMO_DATA yes)"

# Parse command (first positional arg)
if [[ $# -gt 0 ]]; then
  case "$1" in
    start|stop|restart|status|logs|build) COMMAND="$1"; shift ;;
    --help|-h) usage; exit 0 ;;
    --*) : ;;  # no subcommand given, use default "start"
    *) die "Unknown command: '$1'. Run '$(basename "$0") --help' for usage." ;;
  esac
fi

# Parse remaining options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-opensearch)  BUILD_OPENSEARCH=true ;;
    --build-koha)        BUILD_KOHA=true ;;
    --build)             BUILD_OPENSEARCH=true; BUILD_KOHA=true ;;
    --no-fresh-db)       FRESH_DB=false ;;
    --no-logs)           FOLLOW_LOGS=false ;;
    --no-demo-data)      LOAD_DEMO_DATA=no ;;
    --with-demo-data)    LOAD_DEMO_DATA=yes ;;
    --help|-h)           usage; exit 0 ;;
    *) die "Unknown option: '$1'. Run '$(basename "$0") --help' for usage." ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Execute
# ---------------------------------------------------------------------------

echo ""
echo -e "${BOLD}${CYAN}╔════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║   Koha + OpenSearch Stack Manager  ║${RESET}"
echo -e "${BOLD}${CYAN}╚════════════════════════════════════╝${RESET}"
echo ""

case "${COMMAND}" in

  start)
    check_prereqs
    [[ "${BUILD_OPENSEARCH}" == true ]] && build_opensearch
    [[ "${BUILD_KOHA}"       == true ]] && build_koha
    start_traefik
    start_opensearch
    wait_opensearch_green
    start_support_services
    wait_db_ready
    [[ "${FRESH_DB}" == true ]] && reset_database
    start_koha
    echo ""
    log "Koha container is running and initialising."
    [[ "${FOLLOW_LOGS}" == true ]] && follow_logs
    ;;

  stop)
    stop_koha
    stop_support_services
    stop_opensearch
    stop_traefik
    ok "All services stopped."
    ;;

  restart)
    check_prereqs
    hdr "Quick restart (OpenSearch stays up)"
    warn "Assumes OpenSearch cluster is already running and green."
    wait_db_ready
    [[ "${FRESH_DB}" == true ]] && reset_database
    start_koha
    [[ "${FOLLOW_LOGS}" == true ]] && follow_logs
    ;;

  status)
    show_status
    ;;

  logs)
    follow_logs
    ;;

  build)
    check_prereqs
    if [[ "${BUILD_OPENSEARCH}" == false && "${BUILD_KOHA}" == false ]]; then
      # No specific target → build everything
      BUILD_OPENSEARCH=true; BUILD_KOHA=true
    fi
    [[ "${BUILD_OPENSEARCH}" == true ]] && build_opensearch
    [[ "${BUILD_KOHA}"       == true ]] && build_koha
    ok "Build complete."
    ;;

esac

exit 0
