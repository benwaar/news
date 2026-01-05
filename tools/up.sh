#!/usr/bin/env zsh
set -euo pipefail

# Bring up the full stack defined in infra/docker-compose.yml.
# Usage:
#   zsh tools/up.sh            # build and start all services detached
#   zsh tools/up.sh --no-build # start without building
#   zsh tools/up.sh --logs     # tail logs after up

REPO_ROOT="$(cd "$(dirname "$0")"/.. && pwd)"
COMPOSE_FILE="$REPO_ROOT/infra/docker-compose.yml"

NO_BUILD=false
SHOW_LOGS=false

for arg in "$@"; do
  case "$arg" in
    --no-build)
      NO_BUILD=true
      ;;
    --logs)
      SHOW_LOGS=true
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

echo "Using compose file: $COMPOSE_FILE"

# Warn if UI certs are missing for either UI (will fall back to self-signed)
for UI_DIR in "$REPO_ROOT/services/ui-news/certs" "$REPO_ROOT/services/ui-portal/certs"; do
  if [[ ! -f "$UI_DIR/localhost.pem" || ! -f "$UI_DIR/localhost-key.pem" ]]; then
    echo "[warn] mkcert certs not found in $UI_DIR (localhost.pem/key)."
    echo "       UI will use a self-signed cert and browsers may warn."
  fi
done

if [[ "$NO_BUILD" == true ]]; then
  docker compose -f "$COMPOSE_FILE" up -d
else
  docker compose -f "$COMPOSE_FILE" up -d --build
fi

echo "Stack is up."

if [[ "$SHOW_LOGS" == true ]]; then
  echo "Tailing logs (Ctrl+C to stop)..."
  docker compose -f "$COMPOSE_FILE" logs -f
fi