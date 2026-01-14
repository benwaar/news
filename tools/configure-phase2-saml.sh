#!/usr/bin/env bash
set -euo pipefail

# Phase 2: Configure SAML brokering between realms
# - In portal (IdP side): create a SAML client for news SP
# - In news (broker/SP side): add SAML Identity Provider for portal
# Dev-safe: disables signature validation initially; turn on later

PORTAL_REALM=${PORTAL_REALM:-portal}
NEWS_REALM=${NEWS_REALM:-news}
CONTAINER=${CONTAINER:-infra-keycloak-dev}
HOST_PORT=${HOST_PORT:-8081}
SERVER_URL=${SERVER_URL:-http://localhost:8080}

# Constants
PORTAL_ISSUER="https://localhost:8443/realms/${PORTAL_REALM}"
NEWS_ISSUER="https://localhost:8443/realms/${NEWS_REALM}"
NEWS_BROKER_ALIAS="portal-saml"
NEWS_BROKER_ACS="https://localhost:8443/realms/${NEWS_REALM}/broker/${NEWS_BROKER_ALIAS}/endpoint"
# SP Entity ID expected by Portal (IdP) must match the Issuer in
# the AuthnRequest sent by the News realm SAML broker. Keycloak's
# default SP Entity ID for a brokered SAML IdP is the realm issuer.
# Per SP descriptor from News broker, the SP Entity ID is the
# Portal realm issuer (IdP alias descriptor uses IdP realm URI).
SAML_CLIENT_ID="${PORTAL_ISSUER%/}"

echo "[phase2-saml] Waiting for Keycloak on http://localhost:${HOST_PORT} ..."
ATTEMPTS=0
until curl -sSf "http://localhost:${HOST_PORT}" >/dev/null 2>&1 || curl -sSf "http://127.0.0.1:${HOST_PORT}" >/dev/null 2>&1; do
  sleep 1
  ATTEMPTS=$((ATTEMPTS+1))
  if [[ $ATTEMPTS -gt 60 ]]; then
    echo "[phase2-saml] Keycloak not ready after 60s on host port ${HOST_PORT}" >&2
    exit 1
  fi
done

echo "[phase2-saml] Authenticating kcadm ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server "$SERVER_URL" --realm master --user admin --password admin >/dev/null

echo "[phase2-saml] Creating SAML client in '${PORTAL_REALM}' for SP Entity ID: ${SAML_CLIENT_ID} ..."
EXISTING_CLIENT_ID=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get clients -r "$PORTAL_REALM" | jq -r '.[] | select(.clientId=="'"$SAML_CLIENT_ID"'") | .id')
if [[ -z "$EXISTING_CLIENT_ID" ]]; then
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create clients -r "$PORTAL_REALM" \
    -s clientId="$SAML_CLIENT_ID" -s protocol="saml" -s name="News SP (SAML)" \
    -s 'redirectUris=["'"$NEWS_BROKER_ACS"'"]' \
    -s 'attributes."logoutServicePostBindingUrl"="'"$NEWS_BROKER_ACS"'"' \
    -s 'attributes."logoutServiceRedirectBindingUrl"="'"$NEWS_BROKER_ACS"'"' \
    -s 'attributes."saml_single_logout_service_url_post"="'"$NEWS_BROKER_ACS"'"' \
    -s 'attributes."saml_single_logout_service_url_redirect"="'"$NEWS_BROKER_ACS"'"' \
    -s 'attributes."saml_name_id_format"="email"' \
    -s 'attributes."saml_force_name_id_format"="true"' \
    -s 'attributes."saml_assertion_signature"="true"' \
    -s 'attributes."saml.client.signature"="false"'
  EXISTING_CLIENT_ID=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get clients -r "$PORTAL_REALM" | jq -r '.[] | select(.clientId=="'"$SAML_CLIENT_ID"'") | .id')
else
  echo "[phase2-saml] SAML client already exists (id=$EXISTING_CLIENT_ID)."
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update clients/$EXISTING_CLIENT_ID -r "$PORTAL_REALM" \
    -s 'redirectUris=["'"$NEWS_BROKER_ACS"'"]' \
    -s 'attributes."logoutServicePostBindingUrl"="'"$NEWS_BROKER_ACS"'"' \
    -s 'attributes."logoutServiceRedirectBindingUrl"="'"$NEWS_BROKER_ACS"'"' \
    -s 'attributes."saml_single_logout_service_url_post"="'"$NEWS_BROKER_ACS"'"' \
    -s 'attributes."saml_single_logout_service_url_redirect"="'"$NEWS_BROKER_ACS"'"' \
    -s 'attributes."saml_name_id_format"="email"' \
    -s 'attributes."saml_force_name_id_format"="true"' \
    -s 'attributes."saml_assertion_signature"="true"' \
    -s 'attributes."saml.client.signature"="false"'
fi

# Also update the alternate SP client (if present) that may be used by the broker
ALT_SP_CLIENT_ID=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get clients -r "$PORTAL_REALM" | jq -r '.[] | select(.protocol=="saml" and .clientId=="'"$NEWS_ISSUER"'") | .id')
if [[ -n "$ALT_SP_CLIENT_ID" ]]; then
  echo "[phase2-saml] Aligning alternate SP client (id=$ALT_SP_CLIENT_ID) with logout bindings ..."
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update clients/$ALT_SP_CLIENT_ID -r "$PORTAL_REALM" \
    -s frontchannelLogout=true \
    -s 'attributes."logoutServicePostBindingUrl"="'"$NEWS_BROKER_ACS"'"' \
    -s 'attributes."logoutServiceRedirectBindingUrl"="'"$NEWS_BROKER_ACS"'"' \
    -s 'attributes."saml_single_logout_service_url_post"="'"$NEWS_BROKER_ACS"'"' \
    -s 'attributes."saml_single_logout_service_url_redirect"="'"$NEWS_BROKER_ACS"'"' \
    -s 'attributes."saml_name_id_format"="email"' \
    -s 'attributes."saml_force_name_id_format"="true"' \
    -s 'attributes."saml_assertion_signature"="true"'
fi

echo "[phase2-saml] Adding SAML mappers (email, firstName, lastName) ..."
for NAME in email firstName lastName; do
  HAS=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get clients/$EXISTING_CLIENT_ID/protocol-mappers/models -r "$PORTAL_REALM" | jq -r '.[] | select(.protocol=="saml" and .name=="'"$NAME"'") | .id' | head -n1)
  if [[ -z "$HAS" ]]; then
    docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create clients/$EXISTING_CLIENT_ID/protocol-mappers/models -r "$PORTAL_REALM" \
      -s name="$NAME" -s protocol="saml" -s protocolMapper="saml-user-attribute-mapper" \
      -s 'config."user.attribute"="'"$NAME"'"' \
      -s 'config."friendly.name"="'"$NAME"'"' \
      -s 'config."attribute.name"="'"$NAME"'"' \
      -s 'config."attribute.nameformat"="Basic"'
  else
    echo "[phase2-saml] Mapper '$NAME' already present (id=$HAS)."
  fi
done

echo "[phase2-saml] Configuring SAML Identity Provider '${NEWS_BROKER_ALIAS}' in '${NEWS_REALM}' ..."
EXISTING_IDP=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get identity-provider/instances -r "$NEWS_REALM" | jq -r '.[] | select(.alias=="'"$NEWS_BROKER_ALIAS"'") | .alias')
if [[ -z "$EXISTING_IDP" ]]; then
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create identity-provider/instances -r "$NEWS_REALM" \
    -s alias="$NEWS_BROKER_ALIAS" -s displayName="Portal (SAML)" -s providerId="saml" -s enabled=true \
    -s trustEmail=true -s updateProfileFirstLoginMode="off" \
    -s firstBrokerLoginFlowAlias="first broker login" \
    -s 'config."singleSignOnServiceUrl"="'"$PORTAL_ISSUER"'/protocol/saml"' \
    -s 'config."singleLogoutServiceUrl"="'"$PORTAL_ISSUER"'/protocol/saml"' \
    -s 'config."entityId"="'"$PORTAL_ISSUER"'"' \
    -s 'config."nameIDPolicyFormat"="email"' \
    -s 'config."wantAuthnRequestsSigned"="false"' \
    -s 'config."validateSignature"="false"' \
    -s 'config."postBindingResponse"="true"' \
    -s 'config."postBindingAuthnRequest"="true"' \
    -s 'config."trustEmail"="true"'
else
  echo "[phase2-saml] Identity Provider '${NEWS_BROKER_ALIAS}' already exists. Updating core settings ..."
  docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update identity-provider/instances/$NEWS_BROKER_ALIAS -r "$NEWS_REALM" \
    -s displayName="Portal (SAML)" -s trustEmail=true -s updateProfileFirstLoginMode="off" \
    -s firstBrokerLoginFlowAlias="first broker login" \
    -s 'config."singleSignOnServiceUrl"="'"$PORTAL_ISSUER"'/protocol/saml"' \
    -s 'config."singleLogoutServiceUrl"="'"$PORTAL_ISSUER"'/protocol/saml"' \
    -s 'config."entityId"="'"$PORTAL_ISSUER"'"' \
    -s 'config."nameIDPolicyFormat"="email"' \
    -s 'config."wantAuthnRequestsSigned"="false"' \
    -s 'config."validateSignature"="false"' \
    -s 'config."postBindingResponse"="true"' \
    -s 'config."postBindingAuthnRequest"="true"' \
    -s 'config."trustEmail"="true"'
fi

echo "[phase2-saml] Done. Next: set redirector default to '${NEWS_BROKER_ALIAS}' and test SAML SSO."
echo "[phase2-saml] Tip: Turn on signature validation once keys are aligned (validateSignature=true)."
