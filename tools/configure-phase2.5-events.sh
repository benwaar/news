#!/usr/bin/env bash
set -euo pipefail

# Phase 2.5: Enable realm events (LOGIN/LOGOUT) for quick audit/testing
# Applies to both realms: news and portal

PORTAL_REALM=${PORTAL_REALM:-portal}
NEWS_REALM=${NEWS_REALM:-news}
CONTAINER=${CONTAINER:-infra-keycloak-dev}
HOST_PORT=${HOST_PORT:-8081}
SERVER_URL=${SERVER_URL:-http://localhost:8080}

echo "[phase2.5-events] Waiting for Keycloak on http://localhost:${HOST_PORT} ..."
ATTEMPTS=0
until curl -sSf "http://localhost:${HOST_PORT}" >/dev/null 2>&1 || curl -sSf "http://127.0.0.1:${HOST_PORT}" >/dev/null 2>&1; do
  sleep 1
  ATTEMPTS=$((ATTEMPTS+1))
  if [[ $ATTEMPTS -gt 60 ]]; then
    echo "[phase2.5-events] Keycloak not ready after 60s on host port ${HOST_PORT}" >&2
    exit 1
  fi
done

echo "[phase2.5-events] Authenticating kcadm ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server "$SERVER_URL" --realm master --user admin --password admin >/dev/null

enable_events() {
  local realm="$1"
  echo "[phase2.5-events] Enabling events in realm '$realm' (LOGIN/LOGOUT) ..."
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update realms/$realm \
    -s eventsEnabled=true \
    -s 'enabledEventTypes=["LOGIN","LOGOUT"]' >/dev/null
}

enable_events "$NEWS_REALM"
enable_events "$PORTAL_REALM"

echo "[phase2.5-events] Done. Fetch events with:"
echo "  docker exec $CONTAINER /opt/keycloak/bin/kcadm.sh get events -r $NEWS_REALM | jq -r '.[] | select(.type==\"LOGIN\" or .type==\"LOGOUT\") | {time,type,details}'"
