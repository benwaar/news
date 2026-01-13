#!/usr/bin/env bash
set -euo pipefail

# Phase 1.6b — Login With Email (no MFA, no flows)
# - Enables login with email for a target realm
# - Ensures SMTP (Mailpit) is configured first for standalone testing
# - Does NOT modify authentication flows, required actions, or MFA
#
# Usage:
#   bash tools/configure-phase1.6b-login-with-email.sh                 # defaults to portal
#   bash tools/configure-phase1.6b-login-with-email.sh --realm news    # target news
#
CONTAINER="infra-keycloak-dev"
SERVER_URL="http://localhost:8080" # inside container
HOST_PORT=8081
TARGET_REALM="portal"
CREATE_TEST_USER=false
TEST_USERNAME="testuser"
TEST_EMAIL="test.user@example.com"
TEST_PASSWORD="Passw0rd!"
SMTP_HOST="mailpit"

fail() { echo "[phase1.6b] $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      TARGET_REALM="${2:-portal}"
      shift 2 || true
      ;;
    --create-test-user|--creat-test-user)
      CREATE_TEST_USER=true
      shift 1 || true
      ;;
    --user)
      TEST_USERNAME="${2:-testuser}"
      shift 2 || true
      ;;
    --email)
      TEST_EMAIL="${2:-test.user@example.com}"
      shift 2 || true
      ;;
    --password)
      TEST_PASSWORD="${2:-Passw0rd!}"
      shift 2 || true
      ;;
    --host)
      SMTP_HOST="${2:-mailpit}"
      shift 2 || true
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

# Ensure SMTP is configured (standalone behavior)
echo "[phase1.6b] Ensuring SMTP is configured for realm '$TARGET_REALM' (host=${SMTP_HOST}) ..."
bash tools/configure-smtp-dev.sh --realm "$TARGET_REALM" --host "$SMTP_HOST"

# Preconditions
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  fail "Keycloak container ${CONTAINER} not running. Start stack with tools/up.sh or tools/bootstrap.sh."
fi

echo "[phase1.6b] Waiting for Keycloak (host port ${HOST_PORT}) ..."
ATT=0; until curl -sSf "http://localhost:${HOST_PORT}" >/dev/null 2>&1 || curl -sSf "http://127.0.0.1:${HOST_PORT}" >/dev/null 2>&1; do
  sleep 1; ATT=$((ATT+1)); if [[ $ATT -gt 60 ]]; then fail "Keycloak not ready after 60s"; fi; done

echo "[phase1.6b] Authenticating kcadm ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server "$SERVER_URL" --realm master --user admin --password admin >/dev/null

REALM_OK=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get realms/$TARGET_REALM >/dev/null 2>&1 && echo ok || echo fail)
[[ "$REALM_OK" != ok ]] && fail "Realm '$TARGET_REALM' not found."

echo "[phase1.6b] Enabling loginWithEmailAllowed=true on realm '$TARGET_REALM' ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update realms/$TARGET_REALM \
  -s loginWithEmailAllowed=true >/dev/null

echo "[phase1.6b] Done. Current snippet:"
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get realms/$TARGET_REALM | grep -n 'loginWithEmailAllowed' || true

if [[ "$CREATE_TEST_USER" == true ]]; then
  echo "[phase1.6b] Creating test user in realm '$TARGET_REALM' (username=${TEST_USERNAME}, email=${TEST_EMAIL}) ..."
  # Check if user exists
  EXIST_JSON=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get users -r "$TARGET_REALM" -q username="$TEST_USERNAME" || true)
  HAS_USER=$(printf "%s" "$EXIST_JSON" | grep -c '"username"\s*:\s*"'"$TEST_USERNAME"'"' || true)
  if [[ "$HAS_USER" == "0" ]]; then
    docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create users -r "$TARGET_REALM" \
      -s username="$TEST_USERNAME" -s email="$TEST_EMAIL" -s enabled=true >/dev/null
  else
    echo "[phase1.6b] User '${TEST_USERNAME}' already exists; will update password."
  fi

  # Retrieve user id
  USER_JSON=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get users -r "$TARGET_REALM" -q username="$TEST_USERNAME")
  USER_ID=$(printf "%s" "$USER_JSON" | grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n1 | sed 's/.*"id"[[:space:]]*:[[:space:]]*"//; s/".*//')
  if [[ -z "$USER_ID" ]]; then
    fail "Could not determine user id for '${TEST_USERNAME}'."
  fi
  # Set password
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh set-password -r "$TARGET_REALM" --userid "$USER_ID" --new-password "$TEST_PASSWORD" >/dev/null
  echo "[phase1.6b] Test user ready. Try logging in at https://localhost:8443/realms/${TARGET_REALM}/account with email '${TEST_EMAIL}'."
fi
