#!/usr/bin/env bash
set -euo pipefail
#!/usr/bin/env bash
set -euo pipefail
# Simple helper to run or open a psql session into the dev Postgres container.
# Usage: ./tools/psql.sh [database] [user] [psql_args...]
# Defaults: database=news user=postgres

DB_NAME="${1:-news}"
DB_USER="${2:-postgres}"
shift 2 || true

CONTAINER="infra-db-dev"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  echo "Container ${CONTAINER} not running. Start stack with ./tools/up.sh" >&2
  exit 1
fi

# Determine password based on user (defaults: postgres->postgres, news->news)
PGPASSWORD_VAL="postgres"
if [[ "$DB_USER" == "news" ]]; then
  PGPASSWORD_VAL="news"
fi

docker exec -e "PGPASSWORD=${PGPASSWORD_VAL}" -it "${CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" "$@"
