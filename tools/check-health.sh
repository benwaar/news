#!/bin/bash
# Check health endpoints for Phase 1 services

set -euo pipefail

function check_endpoint() {
  local url="$1"
  local name="$2"
  echo -n "Checking $name at $url ... "
  if curl -fsS "$url" > /dev/null; then
    echo "OK"
    return 0
  else
    echo "FAILED"
    return 1
  fi
}


function ensure_docker_up() {
  local running
  running=$(docker ps --format '{{.Names}}' | grep -E 'infra-keycloak-dev|infra-api-dev|infra-rss-mcp-dev|infra-db-dev' | wc -l || true)
  if [ "$running" -lt 4 ]; then
    echo "[health] Some services are not running. Starting core stack (keycloak, db, api, rss-mcp) ..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ROOT_DIR="$SCRIPT_DIR/.."
    docker compose -f "$ROOT_DIR/infra/docker-compose.yml" up -d keycloak db api rss-mcp
    sleep 3
  fi
}

function check_db() {
  echo -n "Checking Postgres (SELECT 1) ... "
  local attempts=0
  until docker exec -e PGPASSWORD=news infra-db-dev psql -U news -d news -c 'SELECT 1;' >/dev/null 2>&1; do
    attempts=$((attempts+1))
    if [[ $attempts -ge 10 ]]; then
      echo "FAILED"
      return 1
    fi
    sleep 1
  done
  echo "OK"
}

ensure_docker_up

check_endpoint "http://localhost:8081" "Keycloak (login page)"
check_endpoint "http://localhost:9000/healthz" "API service"
check_endpoint "http://localhost:9002/healthz" "RSS MCP"
check_db

echo "All health checks completed."
