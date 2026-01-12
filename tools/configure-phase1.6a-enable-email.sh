#!/usr/bin/env bash
set -euo pipefail

# Phase 1.6a — Email for Phase 1 only
# - Configure dev SMTP (Mailpit) for realms without changing flows or MFA
# - Defaults to applying to both 'portal' and 'news' realms
# - Does NOT enable verify-email, reset-password, or TOTP
# - Delegates to tools/configure-smtp-dev.sh to avoid duplication
#
# Usage examples:
#   bash tools/configure-phase1a-email.sh                 # both realms
#   bash tools/configure-phase1a-email.sh --realm portal  # only portal
#   bash tools/configure-phase1a-email.sh --realm news    # only news
#   bash tools/configure-phase1a-email.sh --host mailpit  # override SMTP host

SMTP_HOST="mailpit"
TARGET_REALMS=(portal news)

fail() { echo "[phase1a-email] $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      case "${2:-both}" in
        portal)
          TARGET_REALMS=(portal)
          ;;
        news)
          TARGET_REALMS=(news)
          ;;
        both|all)
          TARGET_REALMS=(portal news)
          ;;
        *)
          fail "Unknown realm value: ${2:-} (use portal|news|both)"
          ;;
      esac
      shift 2 || true
      ;;
    --host)
      SMTP_HOST="${2:-mailpit}"
      shift 2 || true
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

for REALM in "${TARGET_REALMS[@]}"; do
  echo "[phase1a-email] Configuring SMTP for realm '${REALM}' via tools/configure-smtp-dev.sh ..."
  bash tools/configure-smtp-dev.sh --realm "$REALM" --host "$SMTP_HOST"
done

echo "[phase1a-email] Complete. Open http://localhost:8025 to view captured emails."
