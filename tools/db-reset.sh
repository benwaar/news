#!/usr/bin/env bash
set -euo pipefail
# Reset ONLY the Postgres container & volume, then bring full stack back up.
# Usage: ./tools/db-reset.sh
# Optional flags:
#   --no-up    Perform reset but do not start containers afterward
#
# This will:
#   1. Stop stack (using down.sh)
#   2. Remove Postgres volume (infra_postgres_data)
#   3. Start stack (unless --no-up provided)
#
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
VOLUME_NAME="infra_postgres_data"

START_AFTER=true
for arg in "$@"; do
  case "$arg" in
    --no-up) START_AFTER=false ;;
    -h|--help)
      echo "Usage: db-reset.sh [--no-up]"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

pushd "$PROJECT_ROOT" > /dev/null

echo "[db-reset] Stopping stack..."
./tools/down.sh || true

if docker volume ls --format '{{.Name}}' | grep -q "^${VOLUME_NAME}$"; then
  echo "[db-reset] Removing volume ${VOLUME_NAME}..."
  docker volume rm "${VOLUME_NAME}" >/dev/null
else
  echo "[db-reset] Volume ${VOLUME_NAME} not present; skipping removal."
fi

if $START_AFTER; then
  echo "[db-reset] Starting stack..."
  ./tools/up.sh
  echo "[db-reset] Stack restarted. You can connect via: PGPASSWORD=news psql -h localhost -p 55432 -U news -d news"
else
  echo "[db-reset] Reset complete. Stack not started (--no-up)."
fi

popd > /dev/null
