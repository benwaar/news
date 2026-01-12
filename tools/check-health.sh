#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

KEYCLOAK_OIDC="https://localhost:8443/realms/news/.well-known/openid-configuration"
KEYCLOAK_ADMIN="https://localhost:8443/admin"
UI_NEWS="https://localhost/"
UI_PORTAL="https://localhost:4443/"
NEWS_API="http://localhost:9000/healthz"
RSS_MCP="http://localhost:9002/healthz"
MAILPIT_UI="http://localhost:8025/"

PASS=0
FAIL=0

log() {
	printf "%s\n" "$*"
}

check() {
	local name="$1"; shift
	local url="$1"; shift
	local opts=("-fsS" "--max-time" "6" "-k" "-o" "/dev/null" "-w" "%{http_code}")

	local code
	code="$(curl "${opts[@]}" "$url" || true)"
	if [[ "$code" == 2* || "$code" == 3* ]]; then
		log "✅ ${name}: OK (${code}) — ${url}"
		((PASS++)) || true
	else
		log "❌ ${name}: FAIL (${code:-curl error}) — ${url}"
		((FAIL++)) || true
	fi
}

section() {
	printf "\n== %s ==\n" "$*"
}

section "Docker status"
if command -v docker >/dev/null 2>&1; then
	if docker compose version >/dev/null 2>&1; then
		docker compose -f "$ROOT_DIR/infra/docker-compose.yml" ps || true
	else
		docker ps || true
	fi
else
	log "Docker not installed or not on PATH; skipping container status."
fi

section "Endpoint checks"
check "Keycloak OIDC" "$KEYCLOAK_OIDC"
check "Keycloak Admin" "$KEYCLOAK_ADMIN"
check "UI: news" "$UI_NEWS"
check "UI: portal" "$UI_PORTAL"
check "news-api /healthz" "$NEWS_API"
check "rss-mcp /healthz" "$RSS_MCP"
check "mailpit UI" "$MAILPIT_UI"

section "Summary"
log "Passed: ${PASS}  Failed: ${FAIL}"
if [[ "$FAIL" -gt 0 ]]; then
	log "Some checks failed. Common fixes:"
	log "- Ensure the stack is up: docker compose -f infra/docker-compose.yml up -d"
	log "- Wait 10-20s for Keycloak to finish starting on first run"
	log "- If TLS errors occur, note that -k is used for self-signed certs"
	exit 1
fi

exit 0
