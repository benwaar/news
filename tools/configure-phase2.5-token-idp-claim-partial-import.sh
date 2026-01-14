#!/usr/bin/env bash
set -euo pipefail

# Phase 2.5 (Partial Import): Add IdP alias claim via protocol mapper
# - Uses Keycloak partialImport (REST) to create/update a client scope 'idp-claim'
# - Adds a "User Session Note" mapper emitting claim "idp" from note "identity_provider"
# - Attaches 'idp-claim' as a default client scope to news-web and portal-web

PORTAL_REALM=${PORTAL_REALM:-portal}
NEWS_REALM=${NEWS_REALM:-news}
CONTAINER=${CONTAINER:-infra-keycloak-dev}
HOST_PORT=${HOST_PORT:-8081}
ADMIN_BASE=${ADMIN_BASE:-https://localhost:8443}

echo "[phase2.5-idp-claim-partial] Waiting for Keycloak on http://localhost:${HOST_PORT} ..."
ATTEMPTS=0
until curl -sSf "http://localhost:${HOST_PORT}" >/dev/null 2>&1 || curl -sSf "http://127.0.0.1:${HOST_PORT}" >/dev/null 2>&1; do
  sleep 1
  ATTEMPTS=$((ATTEMPTS+1))
  if [[ $ATTEMPTS -gt 60 ]]; then
    echo "[phase2.5-idp-claim-partial] Keycloak not ready after 60s on host port ${HOST_PORT}" >&2
    exit 1
  fi
done

mktempfile() { mktemp 2>/dev/null || mktemp -t kc; }

get_admin_token() {
  curl -sS -k -L "${ADMIN_BASE}/realms/master/protocol/openid-connect/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data 'grant_type=password&client_id=admin-cli&username=admin&password=admin' \
    | jq -r '.access_token'
}

partial_import() {
  local realm="$1"; local payload_file="$2"; local token="$3";
  curl -sS -k -L -o /dev/null -w '%{http_code}' -X POST "${ADMIN_BASE}/admin/realms/${realm}/partialImport" \
    -H "Authorization: Bearer ${token}" -H 'Content-Type: application/json' --data-binary @"${payload_file}"
}

ensure_scope_with_mapper() {
  local realm="$1"; local scopeName="idp-claim";
  echo "[phase2.5-idp-claim-partial] Ensuring client-scope '${scopeName}' with mapper in realm '${realm}' ..."
  local tmp
  tmp=$(mktempfile)
  cat >"$tmp" <<'JSON'
{
  "ifResourceExists": "OVERWRITE",
  "clientScopes": [
    {
      "name": "idp-claim",
      "protocol": "openid-connect",
      "protocolMappers": [
        {
          "name": "idp",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usersessionmodel-note-mapper",
          "consentRequired": false,
          "consentText": "",
          "config": {
            "user.session.note": "identity_provider",
            "claim.name": "idp",
            "jsonType.label": "String",
            "id.token.claim": "true",
            "access.token.claim": "true"
          }
        }
      ]
    }
  ]
}
JSON
  # If scope already exists, include its id to force full overwrite including mappers
  local existing_sid
  existing_sid=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get client-scopes -r "$realm" | jq -r '.[] | select(.name=="'"$scopeName"'") | .id // empty')
  if [[ -n "$existing_sid" ]]; then
    local tmp2
    tmp2=$(mktempfile)
    jq --arg sid "$existing_sid" '.clientScopes[0].id=$sid' "$tmp" > "$tmp2" && mv "$tmp2" "$tmp"
  fi

  local token status
  token=$(get_admin_token)
  status=$(partial_import "$realm" "$tmp" "$token")
  if [[ "$status" != "200" && "$status" != "204" ]]; then
    echo "[phase2.5-idp-claim-partial] ERROR: partialImport (clientScopes) returned HTTP $status for realm '$realm'" >&2
  else
    echo "[phase2.5-idp-claim-partial] Client scope upserted (HTTP $status)."
  fi

  # Ensure mapper exists on the scope even if partialImport didn't apply nested mappers
  local sid mid
  sid=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get client-scopes -r "$realm" | jq -r '.[] | select(.name=="'"$scopeName"'") | .id // empty')
  if [[ -z "$sid" ]]; then
    # Fallback: create the client-scope explicitly via kcadm
    if docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create client-scopes -r "$realm" -s name="$scopeName" -s protocol=openid-connect >/dev/null 2>&1; then
      echo "[phase2.5-idp-claim-partial] Created client-scope '$scopeName' in realm '$realm' via kcadm fallback."
      sid=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get client-scopes -r "$realm" | jq -r '.[] | select(.name=="'"$scopeName"'") | .id // empty')
    else
      echo "[phase2.5-idp-claim-partial] ERROR: Failed to create client-scope '$scopeName' in realm '$realm'." >&2
    fi
  fi
  if [[ -n "$sid" ]]; then
    mid=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get client-scopes/$sid/protocol-mappers/models -r "$realm" | jq -r '.[] | select(.name=="idp") | .id // empty')
    if [[ -z "$mid" ]]; then
      local mapper_tmp
      mapper_tmp=$(mktempfile)
      cat >"$mapper_tmp" <<'MAP'
{
  "name": "idp",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usersessionmodel-note-mapper",
  "config": {
    "user.session.note": "identity_provider",
    "claim.name": "idp",
    "jsonType.label": "String",
    "id.token.claim": "true",
    "access.token.claim": "true"
  }
}
MAP
      docker cp "$mapper_tmp" "$CONTAINER":/tmp/kc-idp-mapper.json
      rm -f "$mapper_tmp"
      # Create mapper using file inside container (more reliable than -s flags)
      if docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh create client-scopes/$sid/protocol-mappers/models -r "$realm" -f /tmp/kc-idp-mapper.json >/dev/null 2>&1; then
        echo "[phase2.5-idp-claim-partial] Mapper 'idp' created on scope '${scopeName}' in realm '${realm}'."
      else
        echo "[phase2.5-idp-claim-partial] WARN: Mapper 'idp' may already exist or creation failed; proceeding." >&2
      fi
    else
      echo "[phase2.5-idp-claim-partial] Mapper 'idp' already present on scope '${scopeName}' in realm '${realm}'."
    fi
  else
    echo "[phase2.5-idp-claim-partial] WARN: Scope '${scopeName}' not found in realm '${realm}' after import." >&2
  fi
}

attach_scope_default() {
  local realm="$1"; local clientName="$2"; local scopeName="idp-claim";
  local cid
  cid=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get clients -r "$realm" -q clientId="$clientName" | jq -r '.[0].id // empty')
  if [[ -z "$cid" ]]; then
    echo "[phase2.5-idp-claim-partial] WARN: missing client id for realm '$realm' (client='$clientName')." >&2
    return 0
  fi
  local current_defaults
  current_defaults=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get clients/$cid/default-client-scopes -r "$realm" | jq -r 'map(.name)')
  if [[ -z "$current_defaults" || "$current_defaults" == "null" ]]; then
    current_defaults='[]'
  fi
  if echo "$current_defaults" | jq -e '. | index("'"$scopeName"'")' >/dev/null; then
    echo "[phase2.5-idp-claim-partial] Default scope '$scopeName' already present for client '$clientName' in realm '$realm'."
    return 0
  fi
  local merged
  merged=$(jq -cn --argjson arr "$current_defaults" --arg name "$scopeName" '$arr + [$name]')
  local tmp
  tmp=$(mktempfile)
  jq -cn --argjson scopes "$merged" --arg client "$clientName" '{ifResourceExists:"OVERWRITE", clients:[{clientId:$client, defaultClientScopes:$scopes}]}' > "$tmp"
  local token status
  token=$(get_admin_token)
  status=$(partial_import "$realm" "$tmp" "$token")
  rm -f "$tmp"
  if [[ "$status" == "200" || "$status" == "204" ]]; then
    echo "[phase2.5-idp-claim-partial] Attached default scope '$scopeName' to client '$clientName' in realm '$realm' via partial import."
  else
    echo "[phase2.5-idp-claim-partial] WARN: Failed to set default scopes for client '$clientName' (HTTP $status)." >&2
  fi
}

verify() {
  local realm="$1"; local clientName="$2";
  local cid
  cid=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get clients -r "$realm" -q clientId="$clientName" | jq -r '.[0].id // empty')
  echo "[phase2.5-idp-claim-partial] Defaults for $clientName:" $(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get clients/$cid/default-client-scopes -r "$realm" | jq -r 'map(.name) | join(", ")')
  local scope_id
  scope_id=$(docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get client-scopes -r "$realm" | jq -r '.[] | select(.name=="idp-claim") | .id // empty')
  if [[ -n "$scope_id" ]]; then
    echo "[phase2.5-idp-claim-partial] Mappers on scope 'idp-claim':"
    docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh get client-scopes/$scope_id/protocol-mappers/models -r "$realm" | jq -r '.[] | [.name, .protocolMapper, (.config["user.session.note"]//""), (.config["claim.name"]//"")] | @tsv'
  fi
}

ensure_scope_with_mapper "$NEWS_REALM"
ensure_scope_with_mapper "$PORTAL_REALM"

attach_scope_default "$NEWS_REALM" news-web
attach_scope_default "$PORTAL_REALM" portal-web

verify "$NEWS_REALM" news-web
verify "$PORTAL_REALM" portal-web

echo "[phase2.5-idp-claim-partial] Done. Re-login; tokens should include claim 'idp' after a brokered login."
