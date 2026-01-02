# Extended Keycloak image for News
# Adds placeholder theme directory for future customization.

FROM quay.io/keycloak/keycloak:25.0.0

# Copy custom themes (currently placeholder).
COPY themes/ /opt/keycloak/themes/

# Copy realm for auto-import (Keycloak reads from /opt/keycloak/data/import when --import-realm is used)
COPY realm-news.json /opt/keycloak/data/import/realm-news.json

# Runtime command provided via docker-compose (start-dev --import-realm)
