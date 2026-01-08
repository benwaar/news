#!/usr/bin/env zsh
set -euo pipefail

# bootstrap.sh — Build and start the stack, configure Keycloak realm and Postgres DB.
# - Ensures mkcert dev certs exist for Keycloak HTTPS
# - Brings up keycloak + db (build)
# - Imports News realm via kcadm
# - Creates Postgres role/db 'news' if missing
# - Starts AI + UI services
# - Health checks: run at the end to verify endpoints

REPO_ROOT="$(cd "$(dirname "$0")"/.. && pwd)"
COMPOSE_FILE="$REPO_ROOT/infra/docker-compose.yml"
CERT_DIR="$REPO_ROOT/infra/keycloak/certs"
HOST_KC_PORT=8081

function ensure_mkcert() {
  if ! command -v mkcert >/dev/null 2>&1; then
    echo "[bootstrap] mkcert not found. Install via Homebrew: brew install mkcert nss" >&2
    exit 2
  fi
  mkcert -install >/dev/null || true
}

function ensure_keycloak_certs() {
  mkdir -p "$CERT_DIR"
  if [[ ! -f "$CERT_DIR/localhost.pem" || ! -f "$CERT_DIR/localhost-key.pem" ]]; then
    echo "[bootstrap] Generating Keycloak dev certs via mkcert ..."
    pushd "$CERT_DIR" >/dev/null
    mkcert localhost
    popd >/dev/null
  else
    echo "[bootstrap] Dev certs already present in $CERT_DIR"
  fi
}

function up_core() {
  echo "[bootstrap] Building and starting keycloak + db ..."
  docker compose -f "$COMPOSE_FILE" up -d --build keycloak db
}

function wait_keycloak() {
  echo "[bootstrap] Waiting for Keycloak on http://localhost:${HOST_KC_PORT} ..."
  local attempts=0
  until curl -sSf "http://localhost:${HOST_KC_PORT}" >/dev/null 2>&1 || curl -sSf "http://127.0.0.1:${HOST_KC_PORT}" >/dev/null 2>&1; do
    sleep 1
    attempts=$((attempts+1))
    if [[ $attempts -gt 60 ]]; then
      echo "[bootstrap] Keycloak not ready after 60s." >&2
      exit 3
    fi
  done
  echo "[bootstrap] Keycloak is responding."
}

function configure_realm() {
  echo "[bootstrap] Configuring 'news' realm ..."
  "$REPO_ROOT"/tools/configure-realm.sh --force || true
}

function configure_phase1() {
  echo "[bootstrap] Configuring Phase 1 (OIDC brokering) ..."
  if [[ -f "$REPO_ROOT/tools/configure-phase1-oidc.sh" ]]; then
    bash "$REPO_ROOT"/tools/configure-phase1-oidc.sh || true
  else
    echo "[bootstrap] Skipping: tools/configure-phase1-oidc.sh not found"
  fi
  # Always enable redirector flow (auto-redirect to IdP)
  if [[ -f "$REPO_ROOT/tools/configure-phase1-redirector.sh" ]]; then
    bash "$REPO_ROOT"/tools/configure-phase1-redirector.sh || true
  else
    echo "[bootstrap] Skipping: tools/configure-phase1-redirector.sh not found"
  fi
}

function configure_phase1_5() {
  echo "[bootstrap] Configuring Phase 1.5 (trustEmail, mapper, role) ..."
  if [[ -f "$REPO_ROOT/tools/configure-phase1-5.sh" ]]; then
    bash "$REPO_ROOT"/tools/configure-phase1-5.sh || true
  else
    echo "[bootstrap] Skipping: tools/configure-phase1-5.sh not found"
  fi
}

function ensure_db() {
  echo "[bootstrap] Ensuring Postgres role/db 'news' exist ..."
  docker exec -e PGPASSWORD=postgres infra-db-dev psql -U postgres -d postgres -c "DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='news') THEN CREATE ROLE news WITH LOGIN PASSWORD 'news' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION; END IF; END $$;" >/dev/null 2>&1 || true
  docker exec -e PGPASSWORD=postgres infra-db-dev psql -U postgres -d postgres -c "DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_database WHERE datname='news') THEN CREATE DATABASE news OWNER news; END IF; END $$;" >/dev/null 2>&1 || true
  docker exec -e PGPASSWORD=postgres infra-db-dev psql -U postgres -d news -c "GRANT CONNECT ON DATABASE news TO news; GRANT USAGE ON SCHEMA public TO news;" >/dev/null 2>&1 || true
}

function up_rest() {
  echo "[bootstrap] Starting API, RSS MCP, and both UIs ..."
  docker compose -f "$COMPOSE_FILE" up -d --build news-api rss-mcp ui-news ui-portal
}

function run_health() {
  echo "[bootstrap] Running health checks ..."
  if command -v bash >/dev/null 2>&1; then
    bash "$REPO_ROOT/tools/check-health.sh"
  else
    "$REPO_ROOT/tools/check-health.sh"
  fi
}

echo "Using compose file: $COMPOSE_FILE"
ensure_mkcert
ensure_keycloak_certs
up_core
wait_keycloak
configure_realm
ensure_db
up_rest
# Short delay to let TLS endpoints settle before health checks (always wait 12s)
echo "[bootstrap] Waiting 12s before health checks ..."
sleep 12 || true
run_health

echo "[bootstrap] Done. Admin: https://localhost:8443/admin | DB: news/news @ localhost:55432 | UI-News: https://localhost | UI-Portal: https://localhost:4443"
