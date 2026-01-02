#!/usr/bin/env zsh
set -euo pipefail

# Quick end-to-end API checks via Nginx proxy at https://localhost
# - AI service endpoints are under `/ai`

BASE="https://localhost"

echo "Checking UI root headers:"
curl -sI "$BASE" | head -n 5

echo "\nChecking AI health and hint:"
curl -sk -o /dev/null -D - "$BASE/ai/healthz" | head -n 5
curl -sk "$BASE/ai/hint" | head -n 5

echo "\nAPI via UI proxy (/api/healthz):"
curl -sk -D - "$BASE/api/healthz" -o - | head -n 20

echo "\nRSS MCP via UI proxy (/mcp/healthz):"
curl -sk -D - "$BASE/mcp/healthz" -o - | head -n 20

echo "\nAPI RSS via UI proxy (/api/rss):"
curl -sk -D - "$BASE/api/rss" -o - | head -n 30

echo "\nDone."
