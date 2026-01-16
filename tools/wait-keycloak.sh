#!/usr/bin/env bash
set -euo pipefail

# wait-keycloak.sh — wait until Keycloak HTTPS endpoint responds
# Defaults: port=8443, timeout=60s, proto=https, self-signed (-k)
# Usage:
#   bash tools/wait-keycloak.sh [--port 8443] [--timeout 60]
# Env overrides:
#   HOST_PORT, WAIT_TIMEOUT

PORT=${HOST_PORT:-8443}
TIMEOUT=${WAIT_TIMEOUT:-60}
PROTO=https

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PORT="${2:-$PORT}"; shift 2 || true ;;
    --timeout)
      TIMEOUT="${2:-$TIMEOUT}"; shift 2 || true ;;
    -h|--help)
      echo "Usage: wait-keycloak.sh [--port <port>] [--timeout <seconds>]";
      exit 0 ;;
    *)
      echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

echo "[wait-kc] Waiting for Keycloak on ${PROTO}://localhost:${PORT} (timeout=${TIMEOUT}s) ..."
ATT=0
until curl -fsS -k "${PROTO}://localhost:${PORT}" >/dev/null 2>&1 || \
      curl -fsS -k "${PROTO}://127.0.0.1:${PORT}" >/dev/null 2>&1; do
  sleep 1; ATT=$((ATT+1));
  if [[ $ATT -ge $TIMEOUT ]]; then
    echo "[wait-kc] Keycloak not ready after ${TIMEOUT}s on ${PROTO} port ${PORT}" >&2
    exit 1
  fi
done

echo "[wait-kc] Keycloak is responding on ${PROTO} port ${PORT}."
