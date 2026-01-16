#!/usr/bin/env bash
set -euo pipefail

# Configure Keycloak client 'news-web' in realm 'news' to allow Angular dev server at https://localhost:4200
# - Adds Redirect URIs: https://localhost:4200/*
# - Adds Web Origins:  https://localhost:4200
# Usage: tools/configure-ui-news-dev-redirects.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
REALM="news"
CLIENT_ID="news-web"
CONTAINER="infra-keycloak-dev"
SERVER_URL="http://localhost:8080"   # internal URL inside container
HOST_PORT=8443                        # external HTTPS port

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  echo "[ui-dev-redirects] Keycloak container ${CONTAINER} not running. Start stack with ./tools/up.sh" >&2
  exit 1
fi

bash "$PROJECT_ROOT/tools/wait-keycloak.sh" --port "$HOST_PORT" --timeout 60

echo "[ui-dev-redirects] Authenticating via kcadm ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server "$SERVER_URL" --realm master --user admin --password admin >/dev/null

CID=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$CLIENT_ID" | jq -r '.[0].id // empty')
if [[ -z "$CID" ]]; then
  echo "[ui-dev-redirects] Client $CLIENT_ID not found in realm $REALM" >&2
  exit 1
fi

echo "[ui-dev-redirects] Updating client $CLIENT_ID ($CID) for Angular dev https://localhost:4200 ..."
TMP=$(mktemp)
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get clients/$CID -r "$REALM" \
  | jq \
    --arg rid1 "https://localhost:4200" \
    --arg rid2 "https://localhost:4200/" \
    --arg rid3 "https://localhost:4200/*" \
    --arg origin "https://localhost:4200" \
    '{
      redirectUris: ((.redirectUris // []) + [$rid1, $rid2, $rid3] | unique),
      webOrigins: ((.webOrigins // []) + [$origin] | unique)
    }' > "$TMP"

docker exec -i "$CONTAINER" /opt/keycloak/bin/kcadm.sh update clients/$CID -r "$REALM" -f - < "$TMP"
rm -f "$TMP"

echo "[ui-dev-redirects] Done: client allows Redirect URIs (exact, slash, wildcard) + Web Origins for https://localhost:4200"
