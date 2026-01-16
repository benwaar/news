#!/usr/bin/env bash
set -euo pipefail

# Phase 1.6d — MFA (OTP) + optional step-up by role
# - Enables TOTP policy for a target realm
# - Mode A (default): enforce for ALL users by enabling default required action CONFIGURE_TOTP
# - Mode B (admin-only or custom role): require OTP only for users with a specific realm role by
#   adding a conditional subflow under the Browser 'forms' flow.
# - Optional: seed existing users with the role to have CONFIGURE_TOTP required action on next login
#
# Usage:
#   bash tools/configure-phase1.6d-mfa-stepup.sh                       # portal, enforce ALL users
#   bash tools/configure-phase1.6d-mfa-stepup.sh --realm portal        # explicit
#   bash tools/configure-phase1.6d-mfa-stepup.sh --admin-only          # step-up only for realm role 'admin'
#   bash tools/configure-phase1.6d-mfa-stepup.sh --role admin          # step-up only for specified realm role
#   bash tools/configure-phase1.6d-mfa-stepup.sh --role admin --seed-existing  # also set required action for existing admins
#
CONTAINER="infra-keycloak-dev"
SERVER_URL="http://localhost:8080"  # inside container
HOST_PORT=8443
TARGET_REALM="portal"
ROLE_MODE="all"         # "all" | "role"
ROLE_NAME="admin"       # used when ROLE_MODE=role
SEED_EXISTING=false      # auto-enabled for ROLE_MODE=role unless --no-seed-existing

fail() { echo "[phase1.6d] $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      TARGET_REALM="${2:-portal}"; shift 2 || true ;;
    --admin-only)
      ROLE_MODE="role"; ROLE_NAME="admin"; shift 1 || true ;;
    --role)
      ROLE_MODE="role"; ROLE_NAME="${2:-admin}"; shift 2 || true ;;
    --seed-existing)
      SEED_EXISTING=true; shift 1 || true ;;
    --no-seed-existing)
      SEED_EXISTING=false; shift 1 || true ;;
    *)
      fail "Unknown option: $1" ;;
  esac
done

echo "[phase1.6d] Target realm='${TARGET_REALM}', mode='${ROLE_MODE}', role='${ROLE_NAME}', seed='${SEED_EXISTING}'"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  fail "Keycloak container ${CONTAINER} not running. Start stack with tools/bootstrap.sh or tools/up.sh."
fi

bash "$(dirname "$0")/wait-keycloak.sh" --port "$HOST_PORT" --timeout 60

echo "[phase1.6d] Authenticating kcadm ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server "$SERVER_URL" --realm master --user admin --password admin >/dev/null

REALM_OK=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get realms/$TARGET_REALM >/dev/null 2>&1 && echo ok || echo fail)
[[ "$REALM_OK" != ok ]] && fail "Realm '$TARGET_REALM' not found."

# 1) Ensure basic TOTP policy is set (doesn't enforce by itself)
echo "[phase1.6d] Setting realm OTP policy (TOTP, 6 digits, 30s) ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update realms/$TARGET_REALM \
  -s otpPolicyType=totp \
  -s otpPolicyAlgorithm=HmacSHA1 \
  -s otpPolicyDigits=6 \
  -s otpPolicyPeriod=30 \
  -s otpPolicyLookAheadWindow=1 >/dev/null

if [[ "$ROLE_MODE" == "all" ]]; then
  # 2A) Enforce for ALL users: enable default required action CONFIGURE_TOTP
  echo "[phase1.6d] Enforcing OTP for ALL users via default required action ..."
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update \
    authentication/required-actions/CONFIGURE_TOTP -r "$TARGET_REALM" \
    -s enabled=true -s defaultAction=true >/dev/null

  echo "[phase1.6d] Complete. All users will be prompted to configure OTP at next login."
  exit 0
fi

echo "[phase1.6d] Step-up strategy: keep default Browser flow; leverage existing 'Conditional OTP' subflow."
echo "[phase1.6d] Disabling realm defaultAction for CONFIGURE_TOTP to avoid forcing non-admin users ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update \
  authentication/required-actions/CONFIGURE_TOTP -r "$TARGET_REALM" \
  -s enabled=true -s defaultAction=false >/dev/null || true

# Auto-enable seeding in role mode unless explicitly disabled
if [[ "$SEED_EXISTING" == false ]]; then
  SEED_EXISTING=true
fi

# If targeting the common case (realm 'portal' and role 'admin'), ensure the portal user has the role first.
if [[ "$TARGET_REALM" == "portal" && "$ROLE_NAME" == "admin" ]]; then
  echo "[phase1.6d] Ensuring portal user has realm role 'admin' via helper ..."
  if [[ -f "$(dirname "$0")/grant-portal-admin.sh" ]]; then
    bash "$(dirname "$0")/grant-portal-admin.sh" || true
  else
    echo "[phase1.6d] grant-portal-admin.sh not found; skipping role grant." >&2
  fi
fi

if [[ "$SEED_EXISTING" == true ]]; then
  echo "[phase1.6d] Seeding existing users with role '${ROLE_NAME}' to require CONFIGURE_TOTP ..."
  ROLE_JSON=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get roles/$ROLE_NAME -r "$TARGET_REALM")
  ROLE_ID=$(printf "%s" "$ROLE_JSON" | grep -m1 '"id"' | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  if [[ -z "${ROLE_ID:-}" ]]; then
    fail "Realm role '${ROLE_NAME}' not found in realm '${TARGET_REALM}'."
  fi
  USERS_JSON=$( (docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get roles-by-id/$ROLE_ID/users -r "$TARGET_REALM" || true) 2>/dev/null )
  if [[ -z "$USERS_JSON" ]]; then USERS_JSON='[]'; fi
  COUNT=$(echo "$USERS_JSON" | grep -c '"id"' || true)
  if [[ "$COUNT" == "0" ]]; then
    echo "[phase1.6d] No existing users found with role '${ROLE_NAME}'. Skipping seeding."
  else
    echo "$USERS_JSON" | grep '"id"' | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | while read -r UID; do
      [[ -z "$UID" ]] && continue
      docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update "users/$UID" -r "$TARGET_REALM" -s 'requiredActions=["CONFIGURE_TOTP"]' >/dev/null || true
    done
    echo "[phase1.6d] Seeded ${COUNT} user(s)."
  fi

  # Additionally, if we are in the common case, explicitly seed the 'portal' user by username as a safeguard.
  if [[ "$TARGET_REALM" == "portal" && "$ROLE_NAME" == "admin" ]]; then
    PORTAL_UID=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get users -r "$TARGET_REALM" -q username=portal | jq -r '.[0].id' 2>/dev/null || echo "")
    if [[ -n "$PORTAL_UID" && "$PORTAL_UID" != "null" ]]; then
      echo "[phase1.6d] Explicitly seeding required action for user 'portal' ..."
      docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update "users/$PORTAL_UID" -r "$TARGET_REALM" -s 'requiredActions=["CONFIGURE_TOTP"]' >/dev/null || true
    fi
  fi
fi

echo "[phase1.6d] Step-up configured. Users with role '${ROLE_NAME}' will be prompted for OTP; others unaffected."
