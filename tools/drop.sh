#!/usr/bin/env zsh
set -euo pipefail

# drop.sh — Scratch EVERYTHING for the local stack.
# Removes containers, networks, images, and volumes for infra/docker-compose.yml.

REPO_ROOT="$(cd "$(dirname "$0")"/.. && pwd)"
COMPOSE_FILE="$REPO_ROOT/infra/docker-compose.yml"
VOLUME_NAME="infra_postgres_data"

echo "Using compose file: $COMPOSE_FILE"

echo "[drop] Bringing stack down and removing images + volumes ..."
docker compose -f "$COMPOSE_FILE" down --rmi all -v --remove-orphans || true

# Some older runs may leave a named volume; remove if present.
if docker volume ls --format '{{.Name}}' | grep -q "^${VOLUME_NAME}$"; then
  echo "[drop] Removing lingering volume ${VOLUME_NAME} ..."
  docker volume rm "${VOLUME_NAME}" >/dev/null || true
fi

echo "[drop] Pruning docker system (dangling resources) ..."
docker system prune -f || true
docker volume prune -f || true

echo "[drop] Scratch complete."

cd "$REPO_ROOT" || exit 0
