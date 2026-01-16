#!/usr/bin/env bash
set -euo pipefail

# Configure Phase 1.5: CIAM app fundamentals atop Phase 1
# - NEWS realm IdP (portal-oidc): trustEmail=true, firstBrokerLoginFlowAlias=review profile
# - Ensure IdP mapper for email claim -> user email
# - Create realm role 'news:admin'
#
# Prereqs: infra-keycloak-dev running, admin/admin, Phase 1 OIDC set up

CONTAINER="infra-keycloak-dev"
SERVER_URL="http://localhost:8080" # inside container
HOST_PORT=8443
NEWS_REALM="news"
IDP_ALIAS="portal-oidc"
ROLE_NAME="news:admin"

fail() { echo "[phase1.5] $*" >&2; exit 1; }

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  fail "Keycloak container ${CONTAINER} not running. Start stack with tools/bootstrap.sh or tools/up.sh."
fi

bash "$(dirname "$0")/wait-keycloak.sh" --port "$HOST_PORT" --timeout 60

echo "[phase1.5] Authenticating kcadm ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server "$SERVER_URL" --realm master --user admin --password admin >/dev/null

# Validate NEWS realm exists
REALM_OK=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get realms/$NEWS_REALM >/dev/null 2>&1 && echo ok || echo fail)
[[ "$REALM_OK" != ok ]] && fail "Realm '$NEWS_REALM' not found. Import via tools/configure-realm.sh first."

# Validate IdP exists
IDP_EXISTS=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get identity-provider/instances -r "$NEWS_REALM" | grep -c '"alias"\s*:\s*"'"$IDP_ALIAS"'"' || true)
[[ "$IDP_EXISTS" == "0" ]] && fail "Identity Provider '$IDP_ALIAS' not found in realm '$NEWS_REALM'. Run tools/configure-phase1-oidc.sh first."

# Update IdP settings: trustEmail, firstBrokerLoginFlowAlias, defaultScope
echo "[phase1.5] Updating IdP settings: trustEmail=true, firstBrokerLoginFlowAlias=first broker login ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update identity-provider/instances/$IDP_ALIAS -r "$NEWS_REALM" \
  -s enabled=true \
  -s 'config.trustEmail=true' \
  -s 'config.defaultScope=openid profile email' \
  -s firstBrokerLoginFlowAlias='first broker login' >/dev/null

# Ensure IdP mapper for email claim exists
MAP_JSON=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get identity-provider/instances/$IDP_ALIAS/mappers -r "$NEWS_REALM")
HAS_EMAIL_MAP=$(echo "$MAP_JSON" | grep -c '"name"\s*:\s*"email"' || true)
if [[ "$HAS_EMAIL_MAP" == "0" ]]; then
  echo "[phase1.5] Creating IdP mapper: email claim -> user email ..."
  set +e
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create identity-provider/instances/$IDP_ALIAS/mappers -r "$NEWS_REALM" \
    -s name=email \
    -s identityProviderAlias=$IDP_ALIAS \
    -s identityProviderMapper=oidc-user-email-idp-mapper >/dev/null
  CREATE_RC=$?
  set -e
  if [[ $CREATE_RC -ne 0 ]]; then
    echo "[phase1.5] Fallback: creating generic OIDC attribute mapper for email ..."
    docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create identity-provider/instances/$IDP_ALIAS/mappers -r "$NEWS_REALM" \
      -s name=email \
      -s identityProviderAlias=$IDP_ALIAS \
      -s identityProviderMapper=oidc-user-attribute-idp-mapper \
      -s 'config.claim=email' \
      -s 'config.user.attribute=email' >/dev/null
  fi
else
  echo "[phase1.5] Email mapper already present."
fi

# Ensure IdP mapper for preferred_username claim exists (map to username)
HAS_PREFUSER_MAP=$(echo "$MAP_JSON" | grep -c '"identityProviderMapper"\s*:\s*"oidc-username-idp-mapper"' || true)
if [[ "$HAS_PREFUSER_MAP" == "0" ]]; then
  echo "[phase1.5] Creating IdP mapper: preferred_username claim -> username ..."
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create identity-provider/instances/$IDP_ALIAS/mappers -r "$NEWS_REALM" \
    -s name=pref-username \
    -s identityProviderAlias=$IDP_ALIAS \
    -s identityProviderMapper=oidc-username-idp-mapper \
    -s 'config.claim=preferred_username' >/dev/null
else
  echo "[phase1.5] preferred_username (username) mapper already present."
fi

# Create realm role 'news:admin' if missing (handle ':' safely)
ROLE_PRESENT=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get roles -r "$NEWS_REALM" | grep -c '"name"\s*:\s*"'"$ROLE_NAME"'"' || true)
if [[ "$ROLE_PRESENT" == "0" ]]; then
  echo "[phase1.5] Creating realm role '$ROLE_NAME' ..."
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create roles -r "$NEWS_REALM" \
    -s name="$ROLE_NAME" \
    -s description="Admin role for News API protected endpoints" >/dev/null
  echo "[phase1.5] Created realm role '$ROLE_NAME'."
else
  echo "[phase1.5] Realm role '$ROLE_NAME' already exists."
fi

echo "[phase1.5] Done. Assign '$ROLE_NAME' to desired users in realm '$NEWS_REALM' to access /api/admin/ping."
