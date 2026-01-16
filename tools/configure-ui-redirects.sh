#!/usr/bin/env bash
set -euo pipefail

# Ensure Keycloak UI clients allow exact + slash + wildcard redirect URIs for prod UIs
# - news-web (realm 'news'): https://localhost, https://localhost/, https://localhost/*
# - portal-web (realm 'portal'): https://localhost:4443, https://localhost:4443/, https://localhost:4443/*
# Usage: tools/configure-ui-redirects.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
CONTAINER="infra-keycloak-dev"
SERVER_URL="http://localhost:8080"   # internal URL inside container
HOST_PORT=8443                        # external HTTPS port

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  echo "[ui-redirects] Keycloak container ${CONTAINER} not running. Start stack with ./tools/up.sh" >&2
  exit 1
fi

bash "${PROJECT_ROOT}/tools/wait-keycloak.sh" --port "$HOST_PORT" --timeout 60

echo "[ui-redirects] Authenticating via kcadm ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server "$SERVER_URL" --realm master --user admin --password admin >/dev/null

update_client() {
  local realm="$1" clientId="$2"; shift 2
  local uris=("$@")
  local cid
  cid=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get clients -r "$realm" -q clientId="$clientId" | jq -r '.[0].id // empty')
  if [[ -z "$cid" ]]; then
    echo "[ui-redirects] Client $clientId not found in realm $realm" >&2
    return 1
  fi
  echo "[ui-redirects] Updating $realm/$clientId ($cid) redirectUris ..."
  local tmp
  tmp=$(mktemp)
  # Build JSON arrays
  jq -n --argjson list "$(printf '%s\n' "${uris[@]}" | jq -R . | jq -s .)" '{redirectUris: $list, webOrigins: []}' > "$tmp"
  # Merge redirectUris with existing, keep webOrigins unchanged
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get clients/$cid -r "$realm" \
    | jq --slurpfile desired "$tmp" '{redirectUris: ((.redirectUris // []) + $desired[0].redirectUris | unique)}' \
    > "$tmp"
  docker exec -i "$CONTAINER" /opt/keycloak/bin/kcadm.sh update clients/$cid -r "$realm" -f - < "$tmp"
  rm -f "$tmp"
}

# news-web
update_client news news-web \
  "https://localhost" \
  "https://localhost/" \
  "https://localhost/*"

# portal-web
update_client portal portal-web \
  "https://localhost:4443" \
  "https://localhost:4443/" \
  "https://localhost:4443/*"

echo "[ui-redirects] Done."
