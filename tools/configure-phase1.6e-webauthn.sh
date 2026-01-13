#!/usr/bin/env bash
set -euo pipefail

# Configure WebAuthn (MFA/passwordless-ready) for local dev
# - Sets sensible WebAuthn policy with RP ID = localhost
# - Enables WebAuthn required actions (registration)
# This does not alter browser flows; use Account Console to register keys

REALM=${REALM:-portal}
CONTAINER=${CONTAINER:-infra-keycloak-dev}
HOST_PORT=${HOST_PORT:-8081}
SERVER_URL=${SERVER_URL:-http://localhost:8080}

echo "[webauthn] Waiting for Keycloak on http://localhost:${HOST_PORT} ..."
ATTEMPTS=0
until curl -sSf "http://localhost:${HOST_PORT}" >/dev/null 2>&1 || curl -sSf "http://127.0.0.1:${HOST_PORT}" >/dev/null 2>&1; do
  sleep 1
  ATTEMPTS=$((ATTEMPTS+1))
  if [[ $ATTEMPTS -gt 60 ]]; then
    echo "[webauthn] Keycloak not ready after 60s on host port ${HOST_PORT}" >&2
    exit 1
  fi
done

echo "[webauthn] Authenticating kcadm ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server "$SERVER_URL" --realm master --user admin --password admin >/dev/null

echo "[webauthn] Applying WebAuthn policy (realm='${REALM}', rpId='localhost') ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update realms/"$REALM" \
  -s webAuthnPolicyRpEntityName="${REALM} Realm" \
  -s webAuthnPolicyRpId="localhost" \
  -s webAuthnPolicyUserVerificationRequirement="preferred" \
  -s webAuthnPolicyAuthenticatorAttachment="not specified" \
  -s webAuthnPolicyRequireResidentKey="not specified" \
  -s webAuthnPolicyAttestationConveyancePreference="none" \
  -s webAuthnPolicyCreateTimeout=60 \
  -s webAuthnPolicyAvoidSameAuthenticatorRegister=false

echo "[webauthn] Applying WebAuthn Passwordless policy ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update realms/"$REALM" \
  -s webAuthnPolicyPasswordlessRpEntityName="${REALM} Realm" \
  -s webAuthnPolicyPasswordlessRpId="localhost" \
  -s webAuthnPolicyPasswordlessUserVerificationRequirement="required" \
  -s webAuthnPolicyPasswordlessAuthenticatorAttachment="not specified" \
  -s webAuthnPolicyPasswordlessRequireResidentKey="required" \
  -s webAuthnPolicyPasswordlessAttestationConveyancePreference="none" \
  -s webAuthnPolicyPasswordlessCreateTimeout=60 \
  -s webAuthnPolicyPasswordlessAvoidSameAuthenticatorRegister=false

echo "[webauthn] Enabling required actions for registration ..."
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update required-actions/webauthn-register -r "$REALM" -s enabled=true -s defaultAction=false || true
docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh update required-actions/webauthn-register-passwordless -r "$REALM" -s enabled=true -s defaultAction=false || true

echo "[webauthn] Done. Register a key via Account Console (Security → Signing In)."
echo "[webauthn] Tip: In Chrome DevTools → More tools → WebAuthn → Enable virtual authenticator to simulate keys."
