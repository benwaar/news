#!/usr/bin/env bash
set -euo pipefail

# Set Keycloak access token lifespan to 30 seconds for the 'news' realm (dev-only).
# Usage: ./tools/configure-access-30s.sh
# Revert: re-import realm (./tools/configure-realm.sh --force) or set a different value via kcadm.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
CONTAINER="infra-keycloak-dev"
SERVER_URL="http://localhost:8080" # inside container
HOST_PORT=8443
REALM="news"
TTL=30

if ! command -v docker >/dev/null; then
  echo "Docker is required." >&2; exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  echo "Keycloak container ${CONTAINER} not running. Start stack with ./tools/up.sh" >&2
  exit 1
fi

bash "${PROJECT_ROOT}/tools/wait-keycloak.sh" --port "$HOST_PORT" --timeout 60

echo "[ttl] Authenticating kcadm ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server "$SERVER_URL" --realm master --user admin --password admin >/dev/null

# Show current (for info only)
CURRENT=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get realms/${REALM} | grep -o '"accessTokenLifespan"\s*:\s*[0-9]\+' || true)
[ -n "$CURRENT" ] && echo "[ttl] Before: $CURRENT" || echo "[ttl] Before: (not set, Keycloak default applies)"

echo "[ttl] Updating realm '${REALM}' accessTokenLifespan -> ${TTL}s ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update realms/${REALM} -s accessTokenLifespan=${TTL} >/dev/null

UPDATED=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get realms/${REALM} | grep -o '"accessTokenLifespan"\s*:\s*[0-9]\+' || true)
echo "[ttl] After: ${UPDATED:-unknown}"

echo "[ttl] Done. New access tokens issued will have ~${TTL}s lifespan. Existing tokens are unchanged."