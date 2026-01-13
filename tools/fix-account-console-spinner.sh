#!/usr/bin/env bash
set -euo pipefail

# Dev helper: minimal fix for Account Console spinner/401
# Adds only the audience mapper so tokens include aud=account.

REALM=${REALM:-portal}
CONTAINER=${CONTAINER:-infra-keycloak-dev}
HOST_PORT=${HOST_PORT:-8081}
SERVER_URL=${SERVER_URL:-http://localhost:8080}

echo "[spinner-fix] Waiting for Keycloak on http://localhost:${HOST_PORT} ..."
ATTEMPTS=0
until curl -sSf "http://localhost:${HOST_PORT}" >/dev/null 2>&1 || curl -sSf "http://127.0.0.1:${HOST_PORT}" >/dev/null 2>&1; do
  sleep 1
  ATTEMPTS=$((ATTEMPTS+1))
  if [[ $ATTEMPTS -gt 60 ]]; then
    echo "[spinner-fix] Keycloak not ready after 60s on host port ${HOST_PORT}" >&2
    exit 1
  fi
done

echo "[spinner-fix] Authenticating kcadm ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server "$SERVER_URL" --realm master --user admin --password admin >/dev/null

echo "[spinner-fix] Resolving client IDs (realm='${REALM}') ..."
ACC_CONSOLE_ID=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId=account-console | jq -r '.[0].id')

if [[ -z "$ACC_CONSOLE_ID" || "$ACC_CONSOLE_ID" == "null" ]]; then
  echo "[spinner-fix] ERROR: Could not find clientId=account-console in realm '${REALM}'." >&2
  exit 2
fi

# Ensure account audience is present in tokens issued to account-console (v3 API expects it)
echo "[spinner-fix] Ensuring audience 'account' is included in account-console access tokens ..."
EXISTING_AUD=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get clients/$ACC_CONSOLE_ID/protocol-mappers/models -r "$REALM" | jq -r '.[] | select(.protocolMapper=="oidc-audience-mapper") | select(.config["included.client.audience"]=="account") | .id' | head -n1)
if [[ -z "$EXISTING_AUD" ]]; then
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create clients/$ACC_CONSOLE_ID/protocol-mappers/models -r "$REALM" \
    -s name="audience-account" \
    -s protocol="openid-connect" \
    -s protocolMapper="oidc-audience-mapper" \
    -s 'config."included.client.audience"=account' \
    -s 'config."id.token.claim"=false' \
    -s 'config."access.token.claim"=true'
else
  echo "[spinner-fix] Audience mapper already present (id=$EXISTING_AUD)."
fi

echo "[spinner-fix] Done. Added audience mapper for account-console."
