#!/usr/bin/env bash
set -euo pipefail

# Configure dev SMTP for a realm to use Mailpit
# By default configures the 'portal' realm; pass --realm news to update the 'news' realm.
# SMTP (Mailpit): host=mailpit, port=1025, no auth, no TLS
# Web UI: http://localhost:8025
#
# Usage:
#   zsh tools/configure-smtp-dev.sh               # portal realm
#   zsh tools/configure-smtp-dev.sh --realm news  # news realm
#
CONTAINER="infra-keycloak-dev"
SERVER_URL="http://localhost:8080" # inside container
HOST_PORT=8081
TARGET_REALM="portal"
SMTP_HOST="mailpit"

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
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

fail() { echo "[smtp-dev] $*" >&2; exit 1; }

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  fail "Keycloak container ${CONTAINER} not running. Start stack with tools/up.sh."
fi

echo "[smtp-dev] Waiting for Keycloak (host port $HOST_PORT) ..."
ATT=0; until curl -sSf "http://localhost:${HOST_PORT}" >/dev/null 2>&1 || curl -sSf "http://127.0.0.1:${HOST_PORT}" >/dev/null 2>&1; do
  sleep 1; ATT=$((ATT+1)); if [[ $ATT -gt 60 ]]; then fail "Keycloak not ready after 60s"; fi; done

echo "[smtp-dev] Authenticating kcadm ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server "$SERVER_URL" --realm master --user admin --password admin >/dev/null

REALM_OK=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get realms/$TARGET_REALM >/dev/null 2>&1 && echo ok || echo fail)
[[ "$REALM_OK" != ok ]] && fail "Realm '$TARGET_REALM' not found."

# Use per-property setters to avoid JSON quoting issues
# Reference keys: smtpServer.host, port, from, fromDisplayName, replyTo, starttls, ssl, auth
FROM_ADDR="dev@${TARGET_REALM}.local"
FROM_NAME="${TARGET_REALM} Dev"

echo "[smtp-dev] Configuring SMTP for realm '$TARGET_REALM' to ${SMTP_HOST} ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update realms/$TARGET_REALM \
  -s "smtpServer.host=${SMTP_HOST}" \
  -s 'smtpServer.port=1025' \
  -s "smtpServer.from=${FROM_ADDR}" \
  -s "smtpServer.fromDisplayName=${FROM_NAME}" \
  -s "smtpServer.replyTo=${FROM_ADDR}" \
  -s 'smtpServer.starttls=false' \
  -s 'smtpServer.ssl=false' \
  -s 'smtpServer.auth=false' >/dev/null

echo "[smtp-dev] Done. Open http://localhost:8025 to view captured emails."
