#!/usr/bin/with-contenv bashio

export PATH="/usr/lib/postgresql/17/bin:${PATH}"

# --- Create persistent data directories (HA mounts /data fresh) ---
mkdir -p /data/postgres /data/redis /data/dawarich/storage /data/dawarich/public
mkdir -p /var/app/tmp/imports/watched
mkdir -p /run/postgresql && chown postgres:postgres /run/postgresql

# --- Hardcoded infrastructure env vars ---
for kv in \
  "DATABASE_HOST=localhost" \
  "DATABASE_PORT=5432" \
  "DATABASE_USERNAME=dawarich" \
  "DATABASE_NAME=dawarich_production" \
  "REDIS_URL=redis://localhost:6379/0" \
  "RAILS_ENV=production" \
  "SELF_HOSTED=true" \
  "STORE_GEODATA=true" \
  "APPLICATION_PROTOCOL=http" \
  "RAILS_LOG_TO_STDOUT=true"; do
  key="${kv%%=*}"
  val="${kv#*=}"
  printf '%s' "$val" > "/var/run/s6/container_environment/${key}"
done

# --- User-configurable env vars ---
printf '%s' "$(bashio::config 'database_password')" > /var/run/s6/container_environment/DATABASE_PASSWORD
printf '%s' "$(bashio::config 'time_zone')" > /var/run/s6/container_environment/TIME_ZONE
printf '%s' "$(bashio::config 'application_hosts')" > /var/run/s6/container_environment/APPLICATION_HOSTS
printf '%s' "$(bashio::config 'background_processing_concurrency')" > /var/run/s6/container_environment/BACKGROUND_PROCESSING_CONCURRENCY

# DOMAIN is what Dawarich uses to build absolute URLs in mails (Devise unlock and
# password-reset instructions). Unset, rendering those mails raises "Missing host
# to link to!" and the request 500s — which is what a locked-out account hits on
# its next login attempt, instead of being told the account is locked.
PRIMARY_HOST="$(bashio::config 'application_hosts' | cut -d',' -f1 | xargs)"
[ -z "$PRIMARY_HOST" ] && PRIMARY_HOST="homeassistant.local"
printf '%s' "$PRIMARY_HOST" > /var/run/s6/container_environment/DOMAIN

# Admin user credentials
printf '%s' "$(bashio::config 'admin_email')" > /var/run/s6/container_environment/ADMIN_EMAIL
printf '%s' "$(bashio::config 'admin_password')" > /var/run/s6/container_environment/ADMIN_PASSWORD

# Dawarich rejects passwords shorter than 12 characters. Creating the admin user
# would fail with "Password is too short" and leave the app with no account to
# log in with, so warn about it here rather than at the point of failure.
ADMIN_PW="$(bashio::config 'admin_password')"
if [ -n "$ADMIN_PW" ] && [ ${#ADMIN_PW} -lt 12 ]; then
  bashio::log.warning "admin_password is only ${#ADMIN_PW} characters — Dawarich requires at least 12."
  bashio::log.warning "The admin user cannot be created until you set a longer password in the app configuration."
fi

# HA location tracker settings
printf '%s' "$(bashio::config 'ha_tracked_entities')" > /var/run/s6/container_environment/HA_TRACKED_ENTITIES
printf '%s' "$(bashio::config 'ha_min_distance')" > /var/run/s6/container_environment/HA_MIN_DISTANCE

# Reverse geocoding
if bashio::config.true 'reverse_geocoding'; then
  GEOAPIFY_KEY="$(bashio::config 'geoapify_api_key')"
  if [ -n "$GEOAPIFY_KEY" ]; then
    printf '%s' "$GEOAPIFY_KEY" > /var/run/s6/container_environment/GEOAPIFY_API_KEY
    bashio::log.info "Reverse geocoding: enabled (Geoapify)"
    # Verify Geoapify API key works
    GEOAPIFY_TEST_URL="https://api.geoapify.com/v1/geocode/reverse?lat=48.8584&lon=2.2945&apiKey=${GEOAPIFY_KEY}"
    # Force IPv4 to mirror the path Ruby's geocoder takes (see /etc/gai.conf).
    # A plain curl uses Happy Eyeballs and can succeed over IPv4 even when IPv6
    # egress is dead, masking the failure the real geocoding jobs would hit.
    GEOAPIFY_RESPONSE=$(curl -4 -sf "${GEOAPIFY_TEST_URL}" 2>&1) || true
    GEOAPIFY_CITY=$(echo "$GEOAPIFY_RESPONSE" | jq -r '.features[0].properties.city // empty' 2>/dev/null)
    if [ -n "$GEOAPIFY_CITY" ]; then
      bashio::log.info "Reverse geocoding: API reachable (test: ${GEOAPIFY_CITY})"
    else
      GEOAPIFY_HTTP_CODE=$(curl -4 -s -o /dev/null -w "%{http_code}" "${GEOAPIFY_TEST_URL}" 2>/dev/null)
      bashio::log.warning "Reverse geocoding: Geoapify API test failed (HTTP ${GEOAPIFY_HTTP_CODE})"
      bashio::log.debug "Reverse geocoding: response: ${GEOAPIFY_RESPONSE}"
    fi
  else
    PHOTON_URL="$(bashio::config 'photon_api_host')"
    PHOTON_KEY="$(bashio::config 'photon_api_key')"
    # Strip protocol — Dawarich expects just the hostname and uses PHOTON_API_USE_HTTPS separately
    PHOTON_HOST="${PHOTON_URL#https://}"
    PHOTON_HOST="${PHOTON_HOST#http://}"
    printf '%s' "$PHOTON_HOST" > /var/run/s6/container_environment/PHOTON_API_HOST
    if [[ "$PHOTON_URL" == https://* ]]; then
      printf '%s' "true" > /var/run/s6/container_environment/PHOTON_API_USE_HTTPS
    else
      printf '%s' "false" > /var/run/s6/container_environment/PHOTON_API_USE_HTTPS
    fi
    if [ -n "$PHOTON_KEY" ]; then
      printf '%s' "$PHOTON_KEY" > /var/run/s6/container_environment/PHOTON_API_KEY
      bashio::log.info "Reverse geocoding: enabled (Photon: ${PHOTON_HOST}, API key set)"
    else
      bashio::log.info "Reverse geocoding: enabled (Photon: ${PHOTON_HOST})"
      # Verify Photon reverse geocoding is reachable (skip when API key is set — can't test auth)
      PHOTON_TEST_URL="${PHOTON_URL}/reverse?lat=48.8584&lon=2.2945"
      bashio::log.debug "Reverse geocoding: testing API at ${PHOTON_TEST_URL}"
      PHOTON_RESPONSE=$(curl -sf "${PHOTON_TEST_URL}" 2>&1) || true
      PHOTON_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${PHOTON_TEST_URL}" 2>/dev/null)
      PHOTON_CITY=$(echo "$PHOTON_RESPONSE" | jq -r '.features[0].properties.city // empty' 2>/dev/null)
      if [ -n "$PHOTON_CITY" ]; then
        bashio::log.info "Reverse geocoding: API reachable (test: ${PHOTON_CITY})"
      else
        bashio::log.warning "Reverse geocoding: API test failed (HTTP ${PHOTON_HTTP_CODE})"
        bashio::log.debug "Reverse geocoding: response: ${PHOTON_RESPONSE}"
      fi
    fi
  fi
else
  bashio::log.info "Reverse geocoding: disabled"
fi

# --- SECRET_KEY_BASE: auto-generate on first run, persist to /data ---
if [ -f /data/dawarich/secret_key_base ]; then
  cat /data/dawarich/secret_key_base > /var/run/s6/container_environment/SECRET_KEY_BASE
else
  openssl rand -hex 64 | tee /data/dawarich/secret_key_base > /var/run/s6/container_environment/SECRET_KEY_BASE
fi

# --- Ingress auto-login: shared secret between nginx and Rails ---
# nginx stamps this on requests it has verified came from Supervisor, and Rails
# trusts a Home Assistant identity header only when it matches. Anything reaching
# Rails another way (port 3000, another container on the hassio network) carries
# no secret and therefore no identity, so it lands on the normal login form.
if [ -f /data/dawarich/ingress_auth_secret ]; then
  INGRESS_AUTH_SECRET="$(cat /data/dawarich/ingress_auth_secret)"
else
  INGRESS_AUTH_SECRET="$(openssl rand -hex 32)"
  printf '%s' "$INGRESS_AUTH_SECRET" > /data/dawarich/ingress_auth_secret
fi
printf '%s' "$INGRESS_AUTH_SECRET" > /var/run/s6/container_environment/INGRESS_AUTH_SECRET

# --- PostgreSQL init on first run ---
# A missing cluster means either a first install or a restored backup (HA backups
# exclude postgres/**). svc-dawarich needs to tell those apart to decide whether
# it may import a SQL dump, so record it here.
printf '%s' "false" > /var/run/s6/container_environment/PG_FRESH_INIT
if [ ! -f /data/postgres/PG_VERSION ]; then
  bashio::log.info "Initializing PostgreSQL database..."
  printf '%s' "true" > /var/run/s6/container_environment/PG_FRESH_INIT
  chown -R postgres:postgres /data/postgres
  su - postgres -c "PATH=/usr/lib/postgresql/17/bin:\$PATH initdb -D /data/postgres"
  # Trust auth: safe because PG binds to localhost only, port 5432 not exposed
  cat > /data/postgres/pg_hba.conf <<'PGEOF'
# Trust is safe here: PostgreSQL is only accessible via localhost within
# this container. Port 5432 is NOT exposed to the host or other containers.
local   all   all                 trust
host    all   all   127.0.0.1/32  trust
host    all   all   ::1/128       trust
PGEOF
fi

# Ensure ownership is correct on restarts
chown -R postgres:postgres /data/postgres
chown -R postgres:postgres /run/postgresql

# --- Ingress auto-login: resolve the mode for this install ---
# "auto" means on for a fresh install and off for one that predates this feature,
# because an update must never change how people log in. Which side of that line
# an install is on is only visible on the one boot that creates the database, so
# that boot records the answer and every later boot reads the record. Inferring
# it from the absence of the legacy marker instead would say "fresh" on boot 1
# and "legacy" on boot 2 of the very same install, silently turning auto-login
# off again the first time Home Assistant restarts the add-on.
#
# An empty PostgreSQL directory does not by itself mean a new install. Home
# Assistant backups exclude postgres/** and carry a pg_dumpall instead, so a
# restore onto new hardware arrives with no database but with that dump, and
# svc-dawarich imports it moments later. Every account and every point comes
# back, so this is the user's existing install and its login flow must not
# change. The dump is the thing that tells the two apart, and it is only ever
# on disk here when there is something to restore.
PG_FRESH_INIT_NOW="$(cat /var/run/s6/container_environment/PG_FRESH_INIT 2>/dev/null || echo false)"
LEGACY_INSTALL_MARKER=/data/dawarich/.pre_ingress_auth_install
FRESH_INSTALL_MARKER=/data/dawarich/.ingress_auth_fresh_install
if [ ! -f "$LEGACY_INSTALL_MARKER" ] && [ ! -f "$FRESH_INSTALL_MARKER" ]; then
  if [ "$PG_FRESH_INIT_NOW" = "true" ] && [ ! -s /data/dawarich/backup.sql ]; then
    touch "$FRESH_INSTALL_MARKER"
  else
    touch "$LEGACY_INSTALL_MARKER"
  fi
fi

case "$(bashio::config 'ingress_auto_login')" in
  on)  INGRESS_AUTO_LOGIN="on" ;;
  off) INGRESS_AUTO_LOGIN="off" ;;
  *)   if [ -f "$FRESH_INSTALL_MARKER" ]; then INGRESS_AUTO_LOGIN="on"; else INGRESS_AUTO_LOGIN="off"; fi ;;
esac

printf '%s' "$INGRESS_AUTO_LOGIN" > /var/run/s6/container_environment/INGRESS_AUTO_LOGIN
bashio::log.info "Ingress auto-login: ${INGRESS_AUTO_LOGIN}"

# Only Supervisor may present a Home Assistant identity, so nginx is given the
# addresses it answers on. Every address is listed, IPv4 and IPv6 alike, because
# which family a request arrives on is not ours to predict. An empty list fails
# closed: no request is trusted, rather than every request being trusted.
TRUSTED_LIST=/etc/nginx/ingress_trusted_addresses.conf
: > "$TRUSTED_LIST"
SUPERVISOR_ADDRESSES="$( { getent ahosts supervisor; getent ahostsv6 supervisor; } 2>/dev/null | awk '{print $1}' | sort -u)"
for addr in $SUPERVISOR_ADDRESSES; do
  printf '%s 1;\n' "$addr" >> "$TRUSTED_LIST"
done

if [ -s "$TRUSTED_LIST" ]; then
  [ "$INGRESS_AUTO_LOGIN" = "on" ] && \
    bashio::log.info "Trusting ingress identity from: $(echo $SUPERVISOR_ADDRESSES | tr '\n' ' ')"
else
  [ "$INGRESS_AUTO_LOGIN" = "on" ] && \
    bashio::log.warning "Could not resolve Supervisor, so no request will be trusted and auto-login stays inactive."
fi

# --- Generate nginx ingress proxy config ---
# Fetch the ingress entry path from Supervisor API (e.g. /api/hassio_ingress/<token>)
INGRESS_ENTRY=$(curl -s -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
  http://supervisor/addons/self/info 2>/dev/null | jq -r '.data.ingress_entry // empty')

if [ -n "$INGRESS_ENTRY" ]; then
  # Remove trailing slash
  INGRESS_ENTRY="${INGRESS_ENTRY%/}"
  bashio::log.info "Ingress path: ${INGRESS_ENTRY}"
  sed -e "s|INGRESS_PATH|${INGRESS_ENTRY}|g" \
      -e "s|INGRESS_AUTH_SECRET|${INGRESS_AUTH_SECRET}|g" \
    /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
else
  bashio::log.warning "Could not determine ingress path, using passthrough"
  sed -e "s|INGRESS_PATH||g" \
      -e "s|INGRESS_AUTH_SECRET|${INGRESS_AUTH_SECRET}|g" \
    /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
fi
