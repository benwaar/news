#!/usr/bin/env bash
set -euo pipefail

# Phase 1.6c — Reset Password (Phase 1 only)
# - Enables reset password capability for a target realm
# - Ensures SMTP (Mailpit) is configured first for standalone testing
# - Does NOT modify flows, required actions, verify-email, or MFA
#
# Usage:
#   bash tools/configure-phase1.6c-reset-password.sh                 # defaults to portal
#   bash tools/configure-phase1.6c-reset-password.sh --realm news    # target news
#
CONTAINER="infra-keycloak-dev"
SERVER_URL="http://localhost:8080" # inside container
HOST_PORT=8081
TARGET_REALM="portal"
SMTP_HOST="mailpit"

fail() { echo "[phase1.6c] $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      TARGET_REALM="${2:-portal}"
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
echo "[phase1.6c] Ensuring SMTP is configured for realm '$TARGET_REALM' (host=${SMTP_HOST}) ..."
bash tools/configure-smtp-dev.sh --realm "$TARGET_REALM" --host "$SMTP_HOST"

# Preconditions
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  fail "Keycloak container ${CONTAINER} not running. Start stack with tools/up.sh or tools/bootstrap.sh."
fi

echo "[phase1.6c] Waiting for Keycloak (host port ${HOST_PORT}) ..."
ATT=0; until curl -sSf "http://localhost:${HOST_PORT}" >/dev/null 2>&1 || curl -sSf "http://127.0.0.1:${HOST_PORT}" >/dev/null 2>&1; do
  sleep 1; ATT=$((ATT+1)); if [[ $ATT -gt 60 ]]; then fail "Keycloak not ready after 60s"; fi; done

echo "[phase1.6c] Authenticating kcadm ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server "$SERVER_URL" --realm master --user admin --password admin >/dev/null

REALM_OK=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get realms/$TARGET_REALM >/dev/null 2>&1 && echo ok || echo fail)
[[ "$REALM_OK" != ok ]] && fail "Realm '$TARGET_REALM' not found."

echo "[phase1.6c] Enabling resetPasswordAllowed=true on realm '$TARGET_REALM' ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update realms/$TARGET_REALM \
  -s resetPasswordAllowed=true >/dev/null

echo "[phase1.6c] Done. Current snippet:"
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get realms/$TARGET_REALM | grep -n 'resetPasswordAllowed' || true

echo "[phase1.6c] Test: In a private window, go to https://localhost:8443/realms/${TARGET_REALM}/account, click 'Forgot password', enter your email. Check http://localhost:8025 for the email."
