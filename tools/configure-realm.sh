#!/usr/bin/env bash
set -euo pipefail

# Configure Keycloak realm from infra/realm-news.json if not already present.
# Usage: ./tools/configure-realm.sh [--force]
# Requires running infra-keycloak-dev container and admin credentials (admin/admin).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
REALM_FILE="${PROJECT_ROOT}/infra/keycloak/realm-news.json"
CONTAINER="infra-keycloak-dev"
# Keycloak listens on 8080 inside the container; host is mapped to 8081 in docker-compose.
SERVER_URL="http://localhost:8080" # internal
HOST_PORT=8081
FORCE=false

for arg in "$@"; do
	case "$arg" in
		--force) FORCE=true ;;
		-h|--help)
			echo "Usage: configure-realm.sh [--force]";
			echo "  --force  Delete existing realm then re-import";
			exit 0 ;;
		*) echo "Unknown argument: $arg" >&2; exit 1 ;;
	esac
done

if [[ ! -f "$REALM_FILE" ]]; then
	echo "Realm file not found: $REALM_FILE" >&2
	exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
	echo "Keycloak container ${CONTAINER} not running. Start stack with ./tools/up.sh" >&2
	exit 1
fi

echo "[realm] Waiting for Keycloak (host port $HOST_PORT) to be reachable..."
ATTEMPTS=0
until curl -sSf "http://localhost:${HOST_PORT}" >/dev/null 2>&1 || curl -sSf "http://127.0.0.1:${HOST_PORT}" >/dev/null 2>&1; do
  sleep 1
  ATTEMPTS=$((ATTEMPTS+1))
  if [[ $ATTEMPTS -gt 60 ]]; then
    echo "Keycloak not ready after 60s on host port ${HOST_PORT}" >&2; exit 1
  fi
done
echo "[realm] Host port is responding; proceeding with kcadm (internal URL $SERVER_URL)."

echo "[realm] Authenticating via kcadm..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
	--server "$SERVER_URL" --realm master --user admin --password admin >/dev/null

set +e
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get realms/news >/dev/null 2>&1
REALM_EXISTS=$?
set -e

if [[ $REALM_EXISTS -eq 0 && "$FORCE" == false ]]; then
	echo "[realm] Realm 'news' already exists. Use --force to re-import.";
	exit 0
fi

if [[ $REALM_EXISTS -eq 0 && "$FORCE" == true ]]; then
	echo "[realm] Deleting existing realm 'news'..."
	docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh delete realms/news
fi

echo "[realm] Importing realm from $REALM_FILE ..."
docker exec -i "$CONTAINER" /opt/keycloak/bin/kcadm.sh create realms -f - < "$REALM_FILE"

echo "[realm] Verifying import..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get realms/news | grep -q '"realm"\s*:\s*"news"'
echo "[realm] Realm 'news' configured successfully."
