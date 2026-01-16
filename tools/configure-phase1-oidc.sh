#!/usr/bin/env bash
set -euo pipefail

# Configure Phase 1: OIDC brokering (portal -> news)
# - Creates/updates confidential client 'news-broker' in realm 'portal'
# - Creates/updates OIDC Identity Provider in realm 'news' with alias 'portal-oidc'
# - Allows redirect URIs for news broker callback
#
# Prereqs: infra-keycloak-dev running, admin/admin

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER="infra-keycloak-dev"
SERVER_URL="http://localhost:8080" # inside container
HOST_PORT=8443

fail() { echo "[phase1] $*" >&2; exit 1; }

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  fail "Keycloak container ${CONTAINER} not running. Start stack with zsh tools/bootstrap.sh or compose up."
fi

bash "$(dirname "$0")/wait-keycloak.sh" --port "$HOST_PORT" --timeout 60

echo "[phase1] Authenticating kcadm ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server "$SERVER_URL" --realm master --user admin --password admin >/dev/null

PORTAL_REALM=portal
NEWS_REALM=news
BROKER_CLIENT_ID=news-broker
BROKER_REDIRECT='https://localhost:8443/realms/news/broker/*'

# Create or get client in portal
CLIENT_UID=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get clients -r "$PORTAL_REALM" -q clientId="$BROKER_CLIENT_ID" \
  | grep -o '"id"\s*:\s*"[^"]\+"' | head -n1 | cut -d '"' -f4 || true)

if [[ -z "$CLIENT_UID" ]]; then
  echo "[phase1] Creating client ${BROKER_CLIENT_ID} in realm ${PORTAL_REALM} ..."
  TMP_JSON=$(mktemp)
  cat >"$TMP_JSON" <<JSON
{
  "clientId": "${BROKER_CLIENT_ID}",
  "protocol": "openid-connect",
  "publicClient": false,
  "standardFlowEnabled": true,
  "directAccessGrantsEnabled": false,
  "redirectUris": ["${BROKER_REDIRECT}"],
  "webOrigins": [],
  "serviceAccountsEnabled": false
}
JSON
  docker exec -i "$CONTAINER" /opt/keycloak/bin/kcadm.sh create clients -r "$PORTAL_REALM" -f - < "$TMP_JSON" >/dev/null
  rm -f "$TMP_JSON"
  CLIENT_UID=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get clients -r "$PORTAL_REALM" -q clientId="$BROKER_CLIENT_ID" \
    | grep -o '"id"\s*:\s*"[^"]\+"' | head -n1 | cut -d '"' -f4)
else
  echo "[phase1] Client ${BROKER_CLIENT_ID} already exists (id=$CLIENT_UID). Ensuring redirect URI present ..."
  # Fetch current client, patch redirectUris to include broker redirect
  FULL=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get clients/$CLIENT_UID -r "$PORTAL_REALM")
  if ! echo "$FULL" | grep -q "$BROKER_REDIRECT"; then
    # Build patched JSON with redirect added
    PATCH=$(mktemp)
    echo "$FULL" | python3 - "$BROKER_REDIRECT" > "$PATCH" <<'PY'
import json,sys
client=json.load(sys.stdin)
redir=sys.argv[1]
uris=set(client.get('redirectUris') or [])
uris.add(redir)
client['redirectUris']=list(uris)
print(json.dumps(client))
PY
    docker exec -i "$CONTAINER" /opt/keycloak/bin/kcadm.sh update clients/$CLIENT_UID -r "$PORTAL_REALM" -f - < "$PATCH" >/dev/null
    rm -f "$PATCH"
  fi
fi

# Get client secret
SECRET_JSON=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get clients/$CLIENT_UID/client-secret -r "$PORTAL_REALM")
CLIENT_SECRET=$(echo "$SECRET_JSON" | grep -o '"value"\s*:\s*"[^"]\+"' | head -n1 | cut -d '"' -f4)
if [[ -z "$CLIENT_SECRET" ]]; then
  fail "Could not retrieve client secret for ${BROKER_CLIENT_ID}"
fi

echo "[phase1] Configuring OIDC Identity Provider in realm ${NEWS_REALM} ..."
ISSUER="https://localhost:8443/realms/${PORTAL_REALM}"
# Backchannel (token) can use internal HTTP to avoid TLS trust inside container
TOKEN_URL_INTERNAL="http://localhost:8080/realms/${PORTAL_REALM}/protocol/openid-connect/token"
EXISTS=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get identity-provider/instances -r "$NEWS_REALM" | grep -c '"alias"\s*:\s*"portal-oidc"' || true)
if [[ "$EXISTS" == "0" ]]; then
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create identity-provider/instances -r "$NEWS_REALM" \
    -s alias=portal-oidc \
    -s providerId=oidc \
    -s enabled=true \
    -s 'config.disableTrustManager=true' \
    -s 'config.useDiscovery=true' \
    -s 'config.useJwksUrl=true' \
    -s "config.issuer=${ISSUER}" \
    -s "config.authorizationUrl=${ISSUER}/protocol/openid-connect/auth" \
    -s "config.tokenUrl=${TOKEN_URL_INTERNAL}" \
    -s "config.clientId=${BROKER_CLIENT_ID}" \
    -s "config.clientSecret=${CLIENT_SECRET}" \
    -s 'config.defaultScope=openid profile email' >/dev/null
  echo "[phase1] Created IdP 'portal-oidc'."
else
  echo "[phase1] IdP 'portal-oidc' exists. Updating settings ..."
  IDP=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get identity-provider/instances/portal-oidc -r "$NEWS_REALM")
  # Update only issuer/client/secret/defaultScope flags to be safe
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update identity-provider/instances/portal-oidc -r "$NEWS_REALM" \
    -s enabled=true \
    -s 'config.disableTrustManager=true' \
    -s 'config.useDiscovery=true' \
    -s 'config.useJwksUrl=true' \
    -s "config.issuer=${ISSUER}" \
    -s "config.authorizationUrl=${ISSUER}/protocol/openid-connect/auth" \
    -s "config.tokenUrl=${TOKEN_URL_INTERNAL}" \
    -s "config.clientId=${BROKER_CLIENT_ID}" \
    -s "config.clientSecret=${CLIENT_SECRET}" \
    -s 'config.defaultScope=openid profile email' >/dev/null
fi

echo "[phase1] Done. Visit https://localhost and Login — you should see a 'Sign in with portal-oidc' option on the News realm login page (or enable the redirector flow to auto-redirect)."
