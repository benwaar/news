#!/usr/bin/env bash
set -euo pipefail

# test-news-api.sh — Acquire an access token via PKCE for client `news-web`
# and call the protected News API endpoint through Nginx: https://localhost/api/rss
#
# Prereqs: Keycloak + UIs up (bootstrap.sh). macOS environment.

ISSUER_BASE="https://localhost:8443/realms/news"
CLIENT_ID="news-web"
REDIRECT_URI="https://localhost/"
REDIRECT_URI_ENC="https%3A%2F%2Flocalhost%2F"
SCOPE="openid profile email"

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

echo "[test] Calling API with bearer token (rss) ..."
curl -fsSk -H "Authorization: Bearer $ACCESS_TOKEN" https://localhost/api/rss | python3 -m json.tool | sed 's/^/[api] /'

echo "[test] Validating token via /api/token/validate ..."
curl -fsSk -H "Authorization: Bearer $ACCESS_TOKEN" https://localhost/api/token/validate | python3 -m json.tool | sed 's/^/[validate] /'
echo "[test] Done."
