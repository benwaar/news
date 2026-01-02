# Extended Postgres image for News
# Adds initialization scripts to ensure application role & database exist.

FROM postgres:16.4

# Ensure UTF-8 locale (optional enhancement)
ENV LANG en_US.utf8

# Copy initialization scripts. These run only on first container start (empty data directory).
COPY init/ /docker-entrypoint-initdb.d/

# Nothing else required; official entrypoint handles execution.
