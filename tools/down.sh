#!/usr/bin/env zsh
set -euo pipefail

# Stop and remove containers and default network for the stack.

REPO_ROOT="$(cd "$(dirname "$0")"/.. && pwd)"
COMPOSE_FILE="$REPO_ROOT/infra/docker-compose.yml"

echo "Using compose file: $COMPOSE_FILE"

# down removes containers and the default network; add --remove-orphans to clean extras
docker compose -f "$COMPOSE_FILE" down --remove-orphans

echo "Stack is down."