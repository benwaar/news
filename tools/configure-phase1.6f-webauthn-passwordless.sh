#!/usr/bin/env bash
set -euo pipefail

# Configure WebAuthn Browser flows and bind them
# Modes:
#  - passwordless: passkey-only (WebAuthn Passwordless REQUIRED)
#  - mixed (default): passkey or username/password (both ALTERNATIVE)
# Idempotent: creates flow/executions if missing, sets requirements, and binds

REALM=${REALM:-portal}
CONTAINER=${CONTAINER:-infra-keycloak-dev}
HOST_PORT=${HOST_PORT:-8081}
SERVER_URL=${SERVER_URL:-http://localhost:8080}
MODE=${1:-${MODE:-mixed}}
PROVIDER_ID="webauthn-authenticator-passwordless"
FLOW_ALIAS=""

if [[ "$MODE" == "passwordless" ]]; then
  FLOW_ALIAS=${FLOW_ALIAS:-browser-passwordless}
elif [[ "$MODE" == "mixed" ]]; then
  FLOW_ALIAS=${FLOW_ALIAS:-browser-passwordless-mixed}
else
  echo "[passwordless] Unknown MODE '$MODE' (expected 'passwordless' or 'mixed')." >&2
  exit 2
fi

echo "[passwordless] Waiting for Keycloak on http://localhost:${HOST_PORT} ..."
ATTEMPTS=0
until curl -sSf "http://localhost:${HOST_PORT}" >/dev/null 2>&1 || curl -sSf "http://127.0.0.1:${HOST_PORT}" >/dev/null 2>&1; do
  sleep 1
  ATTEMPTS=$((ATTEMPTS+1))
  if [[ $ATTEMPTS -gt 60 ]]; then
    echo "[passwordless] Keycloak not ready after 60s on host port ${HOST_PORT}" >&2
    exit 1
  fi
done

echo "[passwordless] Authenticating kcadm ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server "$SERVER_URL" --realm master --user admin --password admin >/dev/null

EXISTS=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get authentication/flows -r "$REALM" | jq -r '.[] | select(.alias=="'"$FLOW_ALIAS"'") | .id')
if [[ -z "$EXISTS" ]]; then
  echo "[passwordless] Creating flow '$FLOW_ALIAS' ..."
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create authentication/flows -r "$REALM" \
    -s alias="$FLOW_ALIAS" -s providerId=basic-flow -s topLevel=true -s description="Passwordless browser flow"
else
  echo "[passwordless] Flow '$FLOW_ALIAS' already exists (id=$EXISTS)."
fi

echo "[passwordless] Ensuring WebAuthn Passwordless execution exists ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create authentication/flows/"$FLOW_ALIAS"/executions/execution -r "$REALM" -s provider="$PROVIDER_ID" >/dev/null || true

WEBEXEC_ID=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get authentication/flows/"$FLOW_ALIAS"/executions -r "$REALM" | jq -r '.[] | select(.providerId=="'"$PROVIDER_ID"'") | .id')

if [[ "$MODE" == "passwordless" ]]; then
  REQ=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get authentication/flows/"$FLOW_ALIAS"/executions -r "$REALM" | jq -r '.[] | select(.providerId=="'"$PROVIDER_ID"'") | .requirement')
  if [[ "$REQ" != "REQUIRED" ]]; then
    echo "[passwordless] Setting execution requirement to REQUIRED (id=$WEBEXEC_ID) ..."
    docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update authentication/flows/"$FLOW_ALIAS"/executions -r "$REALM" -b '{"id":"'"$WEBEXEC_ID"'","requirement":"REQUIRED"}'
  else
    echo "[passwordless] Requirement already REQUIRED."
  fi
else
  echo "[passwordless] Ensuring Username/Password execution exists ..."
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create authentication/flows/"$FLOW_ALIAS"/executions/execution -r "$REALM" -s provider=auth-username-password-form >/dev/null || true
  USEREXEC_ID=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get authentication/flows/"$FLOW_ALIAS"/executions -r "$REALM" | jq -r '.[] | select(.providerId=="auth-username-password-form") | .id')
  echo "[passwordless] Setting both executions to ALTERNATIVE ..."
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update authentication/flows/"$FLOW_ALIAS"/executions -r "$REALM" -b '{"id":"'"$WEBEXEC_ID"'","requirement":"ALTERNATIVE"}'
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update authentication/flows/"$FLOW_ALIAS"/executions -r "$REALM" -b '{"id":"'"$USEREXEC_ID"'","requirement":"ALTERNATIVE"}'
fi

echo "[passwordless] Binding '$FLOW_ALIAS' as Browser flow ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update realms/"$REALM" -s browserFlow="$FLOW_ALIAS"

echo "[passwordless] Done. Browser flow is now '$FLOW_ALIAS'."
echo "[passwordless] Revert: kcadm.sh update realms/$REALM -s browserFlow=browser"
echo "[passwordless] Usage: $0 [passwordless|mixed] (default: mixed)"
