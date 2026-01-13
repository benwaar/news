#!/usr/bin/env bash
set -euo pipefail

# Helper — Grant a realm role (default: 'admin') to a user (default: 'portal') in realm 'portal'.
#
# Usage examples:
#   bash tools/grant-portal-admin.sh                      # grant 'admin' to user 'portal' in realm 'portal'
#   bash tools/grant-portal-admin.sh --username alice     # grant 'admin' to user 'alice' in realm 'portal'
#   bash tools/grant-portal-admin.sh --realm portal --role admin --username portal
#
CONTAINER="infra-keycloak-dev"
SERVER_URL="http://localhost:8080"  # inside container
HOST_PORT=8081
TARGET_REALM="portal"
TARGET_USER="portal"
TARGET_ROLE="admin"

fail() { echo "[grant-role] $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      TARGET_REALM="${2:-portal}"; shift 2 || true ;;
    --username)
      TARGET_USER="${2:-portal}"; shift 2 || true ;;
    --role)
      TARGET_ROLE="${2:-admin}"; shift 2 || true ;;
    *)
      fail "Unknown option: $1" ;;
  esac
done

echo "[grant-role] realm='${TARGET_REALM}' user='${TARGET_USER}' role='${TARGET_ROLE}'"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  fail "Keycloak container ${CONTAINER} not running. Start stack with tools/bootstrap.sh or tools/up.sh."
fi

echo "[grant-role] Waiting for Keycloak (host port ${HOST_PORT}) ..."
ATT=0; until curl -sSf "http://localhost:${HOST_PORT}" >/dev/null 2>&1 || curl -sSf "http://127.0.0.1:${HOST_PORT}" >/dev/null 2>&1; do
  sleep 1; ATT=$((ATT+1)); if [[ $ATT -gt 60 ]]; then fail "Keycloak not ready after 60s"; fi; done

echo "[grant-role] Authenticating kcadm ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server "$SERVER_URL" --realm master --user admin --password admin >/dev/null

REALM_OK=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get realms/$TARGET_REALM >/dev/null 2>&1 && echo ok || echo fail)
[[ "$REALM_OK" != ok ]] && fail "Realm '$TARGET_REALM' not found."

echo "[grant-role] Locating user '${TARGET_USER}' ..."
USER_JSON=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get users -r "$TARGET_REALM" -q username="$TARGET_USER" 2>/dev/null || echo "[]")
USER_ID=$(printf "%s" "$USER_JSON" | grep -m1 '"id"' | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
[[ -z "${USER_ID:-}" ]] && fail "User '$TARGET_USER' not found in realm '$TARGET_REALM'."

echo "[grant-role] Ensuring role '${TARGET_ROLE}' exists ..."
ROLE_JSON=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get roles -r "$TARGET_REALM" -q search="$TARGET_ROLE" 2>/dev/null || echo "[]")
HAS_ROLE=$(printf "%s" "$ROLE_JSON" | grep -c '"name"[[:space:]]*:[[:space:]]*"'"$TARGET_ROLE"'"' || true)
if [[ "$HAS_ROLE" == "0" ]]; then
  echo "[grant-role] Role '${TARGET_ROLE}' not found; creating ..."
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create roles -r "$TARGET_REALM" -s name="$TARGET_ROLE" -s description="Created by helper" >/dev/null
fi

echo "[grant-role] Assigning role '${TARGET_ROLE}' to user '${TARGET_USER}' ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh add-roles -r "$TARGET_REALM" --uusername "$TARGET_USER" --rolename "$TARGET_ROLE" >/dev/null

echo "[grant-role] Verifying role mapping ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get users/$USER_ID/role-mappings/realm -r "$TARGET_REALM" | grep -E '"name"\s*:\s*"'