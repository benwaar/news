#!/usr/bin/env bash
set -euo pipefail

# Enable auto-redirect to portal-oidc by creating a copy of the browser flow
# and adding Identity Provider Redirector with default IdP=portal-oidc, then binding it.
# Realm: news

CONTAINER="infra-keycloak-dev"
REALM="news"
BASE_FLOW="browser"
NEW_FLOW="browser-with-idp"
IDP_ALIAS="portal-oidc"
SERVER_URL="http://localhost:8080"
HOST_PORT=8443

fail() { echo "[redirector] $*" >&2; exit 1; }

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  fail "Keycloak container ${CONTAINER} not running. Start stack with zsh tools/bootstrap.sh or compose up."
fi

bash "$(dirname "$0")/wait-keycloak.sh" --port "$HOST_PORT" --timeout 60

echo "[redirector] Authenticating kcadm ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server "$SERVER_URL" --realm master --user admin --password admin >/dev/null

# Validate IdP exists
IDP_EXISTS=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get identity-provider/instances -r "$REALM" | grep -c '"alias"\s*:\s*"'"$IDP_ALIAS"'"' || true)
if [[ "$IDP_EXISTS" == "0" ]]; then
  fail "Identity Provider '$IDP_ALIAS' not found in realm '$REALM'. Run tools/configure-phase1-oidc.sh first."
fi

# Check if target flow exists; if not, copy from base
FLOW_EXISTS=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get authentication/flows -r "$REALM" | grep -c '"alias"\s*:\s*"'"$NEW_FLOW"'"' || true)
if [[ "$FLOW_EXISTS" == "0" ]]; then
  echo "[redirector] Copying flow '$BASE_FLOW' -> '$NEW_FLOW' ..."
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create "authentication/flows/$BASE_FLOW/copy" -r "$REALM" -s "newName=$NEW_FLOW" >/dev/null
  # Poll until the new flow is visible
  echo "[redirector] Waiting for new flow '$NEW_FLOW' to be available ..."
  ATT=0
  until docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get authentication/flows -r "$REALM" | grep -q '"alias"\s*:\s*"'"$NEW_FLOW"'"'; do
    sleep 1; ATT=$((ATT+1)); if [[ $ATT -gt 30 ]]; then fail "Flow '$NEW_FLOW' not visible after 30s"; fi
  done
else
  echo "[redirector] Flow '$NEW_FLOW' already exists."
fi

# Ensure identity-provider-redirector execution exists and capture its id
echo "[redirector] Ensuring Identity Provider Redirector is present and configured ..."
EXECUTIONS_JSON=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get "authentication/flows/$NEW_FLOW/executions" -r "$REALM" 2>/dev/null || echo "[]")
EXEC_ID=$(echo "$EXECUTIONS_JSON" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(next((e.get("id","") for e in j if e.get("providerId")=="identity-provider-redirector"), ""))')
if [[ -z "${EXEC_ID:-}" ]]; then
  echo "[redirector] Adding identity-provider-redirector execution ..."
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create "authentication/flows/$NEW_FLOW/executions/execution" -r "$REALM" -s provider=identity-provider-redirector >/dev/null
  # Poll for execution to appear
  ATT=0
  until EXECUTIONS_JSON=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get "authentication/flows/$NEW_FLOW/executions" -r "$REALM" 2>/dev/null || echo "[]"); \
        EXEC_ID=$(echo "$EXECUTIONS_JSON" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(next((e.get("id","") for e in j if e.get("providerId")=="identity-provider-redirector"), ""))'); \
        [[ -n "$EXEC_ID" ]]; do
    sleep 1; ATT=$((ATT+1)); if [[ $ATT -gt 30 ]]; then fail "identity-provider-redirector execution not found after 30s"; fi
  done
fi

# Check for existing authenticator config for this execution
AUTH_CFG_ID=$(echo "$EXECUTIONS_JSON" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(next((e.get("authenticationConfig","") for e in j if e.get("providerId")=="identity-provider-redirector"), ""))')

if [[ -z "${AUTH_CFG_ID:-}" ]]; then
  echo "[redirector] Creating authenticator config for defaultProvider=$IDP_ALIAS ..."
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create "authentication/executions/$EXEC_ID/config" -r "$REALM" \
    -s alias="idp-redirector-$NEW_FLOW" -s "config.defaultProvider=$IDP_ALIAS" >/dev/null
else
  echo "[redirector] Updating authenticator config ($AUTH_CFG_ID) defaultProvider=$IDP_ALIAS ..."
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update "authentication/config/$AUTH_CFG_ID" -r "$REALM" \
    -s "config.defaultProvider=$IDP_ALIAS" >/dev/null
fi

# Ensure requirement is ALTERNATIVE (typical for redirector)
# Try to set requirement; tolerate eventual consistency by re-trying
ATT=0
until docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update "authentication/executions/$EXEC_ID" -r "$REALM" -s requirement=ALTERNATIVE >/dev/null 2>&1; do
  sleep 1; ATT=$((ATT+1)); if [[ $ATT -gt 10 ]]; then echo "[redirector] Warning: could not update requirement for execution $EXEC_ID" >&2; break; fi
done

# Bind the new flow as the realm's Browser Flow
echo "[redirector] Binding '$NEW_FLOW' as Browser Flow for realm '$REALM' ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update realms/$REALM -s "browserFlow=$NEW_FLOW" >/dev/null

echo "[redirector] Done. Hitting https://localhost should now auto-redirect to '$IDP_ALIAS'."