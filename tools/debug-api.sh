#!/usr/bin/env bash
set -euo pipefail

# debug-api.sh — Hit the local debug News API directly on http://localhost:9000
# using a bearer token from args/env/clipboard. Useful for triggering VS Code
# breakpoints in the Node server (launched via the "News API (Node)" config).
#
# Usage examples (macOS):
#   tools/debug-api.sh --validate              # use token from clipboard (pbpaste)
#   tools/debug-api.sh --validate --token "$(pbpaste)"
#   ACCESS_TOKEN="$(pbpaste)" tools/debug-api.sh --rss
#   tools/debug-api.sh --admin
#   tools/debug-api.sh --all
#   tools/debug-api.sh --token-file ~/token.txt --validate
#
# Flags:
#   --validate     Call /token/validate
#   --rss          Call /rss
#   --admin        Call /admin/ping
#   --all          Call validate, rss, admin in sequence
#   --token|-t     Provide token string
#   --token-file|-f Provide path to file containing token
#
# Defaults:
#   - If no call flag passed, defaults to --validate
#   - Token is resolved from --token/--token-file/ACCESS_TOKEN/pbpaste (macOS)

API_BASE="http://localhost:9000"
DO_VALIDATE=false
DO_RSS=false
DO_ADMIN=false

TOKEN_FROM_ARGS=""
TOKEN_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --validate) DO_VALIDATE=true; shift ;;
    --rss) DO_RSS=true; shift ;;
    --admin) DO_ADMIN=true; shift ;;
    --all) DO_VALIDATE=true; DO_RSS=true; DO_ADMIN=true; shift ;;
    --token|-t) TOKEN_FROM_ARGS="${2:-}"; shift 2 ;;
    --token-file|-f) TOKEN_FILE="${2:-}"; shift 2 ;;
    *) echo "[debug-api] Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if ! $DO_VALIDATE && ! $DO_RSS && ! $DO_ADMIN; then
  DO_VALIDATE=true
fi

resolve_token() {
  if [[ -n "$TOKEN_FROM_ARGS" ]]; then
    echo "$TOKEN_FROM_ARGS"; return 0
  fi
  if [[ -n "$TOKEN_FILE" ]]; then
    [[ -f "$TOKEN_FILE" ]] || { echo "[debug-api] Token file not found: $TOKEN_FILE" >&2; exit 2; }
    cat "$TOKEN_FILE"; return 0
  fi
  if [[ -n "${ACCESS_TOKEN:-}" ]]; then
    echo "$ACCESS_TOKEN"; return 0
  fi
  if command -v pbpaste >/dev/null 2>&1; then
    CLIP=$(pbpaste)
    if [[ -n "$CLIP" ]]; then
      echo "$CLIP"; return 0
    fi
  fi
  echo "[debug-api] No token provided. Use --token/--token-file/ACCESS_TOKEN or copy token to clipboard." >&2
  exit 2
}

ACCESS_TOKEN="$(resolve_token)"

call_json() {
  local path="$1"
  echo "[debug-api] GET ${API_BASE}${path}"
  set +e
  RESP=$(curl -sS -H "Authorization: Bearer $ACCESS_TOKEN" "${API_BASE}${path}")
  CODE=$?
  set -e
  if [[ $CODE -ne 0 ]]; then
    echo "[debug-api] curl failed with exit code $CODE" >&2
    exit $CODE
  fi
  # Pretty print when possible
  if command -v python3 >/dev/null 2>&1; then
    echo "$RESP" | python3 -m json.tool | sed 's/^/[api] /'
  else
    echo "$RESP"
  fi
}

$DO_VALIDATE && call_json "/token/validate"
$DO_RSS && call_json "/rss"
$DO_ADMIN && call_json "/admin/ping"

echo "[debug-api] Done."
