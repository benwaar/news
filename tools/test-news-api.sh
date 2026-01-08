#!/usr/bin/env bash
set -euo pipefail

# test-news-api.sh — Acquire an access token via PKCE for client `news-web`
# and call the protected News API endpoint through Nginx: https://localhost/api/rss
#
# Prereqs: Keycloak + UIs up (bootstrap.sh). macOS environment.

# Usage:
#   tools/test-news-api.sh                    # interactive PKCE browser flow
#   tools/test-news-api.sh --token "<JWT>"    # use provided token
#   tools/test-news-api.sh --token "$(pbpaste)" # macOS: use token from clipboard
#   ACCESS_TOKEN="<JWT>" tools/test-news-api.sh   # use token from env
#   tools/test-news-api.sh --token-file /path/to/token.txt

ISSUER_BASE="https://localhost:8443/realms/news"
CLIENT_ID="news-web"
REDIRECT_URI="https://localhost/"
REDIRECT_URI_ENC="https%3A%2F%2Flocalhost%2F"
SCOPE="openid profile email"

ACCESS_TOKEN_FROM_ARGS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --token|-t)
      ACCESS_TOKEN_FROM_ARGS="${2:-}"; shift 2 ;;
    --token-file|-f)
      [[ -f "${2:-}" ]] || { echo "[test] Token file not found: $2" >&2; exit 2; }
      ACCESS_TOKEN_FROM_ARGS="$(cat "$2")"; shift 2 ;;
    *) echo "[test] Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -n "${ACCESS_TOKEN_FROM_ARGS}" ]]; then
  ACCESS_TOKEN="$ACCESS_TOKEN_FROM_ARGS"
  echo "[test] Using token from args."
elif [[ -n "${ACCESS_TOKEN:-}" ]]; then
  echo "[test] Using token from ACCESS_TOKEN env var."
else
  echo "[test] Generating PKCE verifier/challenge ..."
  PKCE_JSON=$(python3 tools/pkce.py --json)
  VERIFIER=$(python3 - <<'PY'
import json,sys
print(json.loads(sys.stdin.read())["code_verifier"]) 
PY
<<< "$PKCE_JSON")
  CHALLENGE=$(python3 - <<'PY'
import json,sys
print(json.loads(sys.stdin.read())["code_challenge"]) 
PY
<<< "$PKCE_JSON")

  AUTH_URL="${ISSUER_BASE}/protocol/openid-connect/auth?client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI_ENC}&response_type=code&scope=$(python3 - <<'PY'
import urllib.parse; print(urllib.parse.quote("openid profile email"))
PY
)&code_challenge_method=S256&code_challenge=${CHALLENGE}"

  echo "[test] Opening browser to authenticate ..."
  echo "[test] URL: $AUTH_URL"
  open "$AUTH_URL" >/dev/null 2>&1 || true

  echo "[test] After login, you will be redirected to ${REDIRECT_URI}."
  echo "[test] Copy the full URL from the address bar and paste it below."
  read -r -p "Paste redirect URL: " REDIRECTED

  CODE=$(python3 - <<'PY'
import sys,urllib.parse
url=sys.stdin.read().strip()
qs=urllib.parse.urlparse(url).query
params=urllib.parse.parse_qs(qs)
code=params.get('code',[None])[0]
print(code if code else "")
PY
<<< "$REDIRECTED")

  if [[ -z "$CODE" ]]; then
    echo "[test] Could not parse 'code' from pasted URL." >&2
    exit 2
  fi

  echo "[test] Exchanging code for tokens ..."
  TOKEN_JSON=$(curl -fsSk -X POST \
    -d "grant_type=authorization_code" \
    -d "client_id=${CLIENT_ID}" \
    -d "code=${CODE}" \
    -d "redirect_uri=${REDIRECT_URI}" \
    -d "code_verifier=${VERIFIER}" \
    "${ISSUER_BASE}/protocol/openid-connect/token")

  ACCESS_TOKEN=$(python3 - <<'PY'
import json,sys
print(json.loads(sys.stdin.read()).get("access_token",""))
PY
<<< "$TOKEN_JSON")

  if [[ -z "$ACCESS_TOKEN" ]]; then
    echo "[test] No access_token in token response:" >&2
    echo "$TOKEN_JSON" >&2
    exit 3
  fi
fi

echo "[test] Calling API with bearer token (rss) ..."
curl -fsSk -H "Authorization: Bearer $ACCESS_TOKEN" https://localhost/api/rss | python3 -m json.tool | sed 's/^/[api] /'

echo "[test] Validating token via /api/token/validate ..."
curl -fsSk -H "Authorization: Bearer $ACCESS_TOKEN" https://localhost/api/token/validate | python3 -m json.tool | sed 's/^/[validate] /'
echo "[test] Trying admin-only endpoint /api/admin/ping (expect 403 unless role assigned) ..."
STATUS=$(curl -sk -w "%{http_code}" -o /tmp/admin_resp.json -H "Authorization: Bearer $ACCESS_TOKEN" https://localhost/api/admin/ping)
cat /tmp/admin_resp.json | python3 -m json.tool | sed 's/^/[admin] /'
echo "[test] HTTP status: $STATUS"
echo "[test] Done."
