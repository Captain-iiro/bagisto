#!/bin/bash
set -e

APP_DIR="/var/www/bagisto"

# ==========================================================================
# Helper: log with timestamp
# ==========================================================================
log() {
    echo "[bagisto-entrypoint] $(date '+%Y-%m-%d %H:%M:%S') $*"
}

# ==========================================================================
# Write (or leave untouched) an APP_/DB_/REDIS_ override into .env
# ==========================================================================
set_env() {
    local key="$1"
    local value="${2:-}"

    [ -z "$value" ] && return 0

    # Escape characters that are special for the sed '|' delimiter
    value=$(printf '%s' "$value" | sed 's/[\\&|]/\\&/g')

    sed -i "s|^${key}=.*|${key}=${value}|" .env
}

# ==========================================================================
# Detect whether Bagisto has already been installed into the database
# ==========================================================================
db_initialized() {
    php -r '
        $host = $argv[1]; $port = $argv[2]; $db = $argv[3]; $user = $argv[4]; $pass = $argv[5];

        try {
            $pdo = new PDO("mysql:host=$host;port=$port;dbname=$db", $user, $pass);

            $count = (int) $pdo->query(
                "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = \"migrations\""
            )->fetchColumn();

            exit($count > 0 ? 0 : 1);
        } catch (Exception $e) {
            exit(1);
        }
    ' "$DB_HOST" "$DB_PORT" "$DB_DATABASE" "$DB_USERNAME" "$DB_PASSWORD"
}

# ==========================================================================
# Resolve database settings (from the container environment)
# ==========================================================================
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_DATABASE="${DB_DATABASE:-bagisto}"
DB_USERNAME="${DB_USERNAME:-bagisto}"
DB_PASSWORD="${DB_PASSWORD:-bagisto}"

cd "$APP_DIR"

# ==========================================================================
# Ensure the runtime directory skeleton exists. A mounted volume (Dokploy
# persistent storage) can shadow the directories baked into the image, so
# recreate anything missing before any artisan command runs.
# ==========================================================================
log "Ensuring storage directory skeleton..."
mkdir -p \
    storage/app/private \
    storage/app/public/data-transfer/samples/csv \
    storage/app/public/data-transfer/samples/images \
    storage/app/public/data-transfer/samples/xls \
    storage/app/public/data-transfer/samples/xlsx \
    storage/app/public/data-transfer/samples/xml \
    storage/debugbar \
    storage/fonts \
    storage/framework/cache/data \
    storage/framework/sessions \
    storage/framework/testing \
    storage/framework/views \
    storage/logs \
    bootstrap/cache

# ==========================================================================
# Apply runtime environment overrides to .env
# ==========================================================================
log "Applying runtime environment overrides..."
set_env DB_HOST "$DB_HOST"
set_env DB_PORT "$DB_PORT"
set_env DB_DATABASE "$DB_DATABASE"
set_env DB_USERNAME "$DB_USERNAME"
set_env DB_PASSWORD "$DB_PASSWORD"
set_env APP_URL "${APP_URL:-}"
set_env APP_KEY "${APP_KEY:-}"
set_env APP_ADMIN_URL "${APP_ADMIN_URL:-}"
set_env APP_LOCALE "${APP_LOCALE:-}"
set_env APP_CURRENCY "${APP_CURRENCY:-}"
set_env APP_TIMEZONE "${APP_TIMEZONE:-}"
set_env REDIS_HOST "${REDIS_HOST:-}"
set_env REDIS_PORT "${REDIS_PORT:-}"
set_env REDIS_PASSWORD "${REDIS_PASSWORD:-}"

# ==========================================================================
# Ensure a valid APP_KEY exists
# ==========================================================================
if [ -z "$(grep '^APP_KEY=.\+' .env | head -n1 | cut -d= -f2-)" ]; then
    log "No APP_KEY found, generating one..."
    php artisan key:generate --force --no-interaction
fi

# ==========================================================================
# Discover packages (composer ran with --no-scripts during the build)
# ==========================================================================
log "Discovering packages..."
php artisan package:discover --no-interaction || true

# ==========================================================================
# Wait for the external MySQL to accept connections
# ==========================================================================
log "Waiting for MySQL at ${DB_HOST}:${DB_PORT}..."
DB_READY=0
for i in $(seq 1 60); do
    if php -r 'try { new PDO("mysql:host=$argv[1];port=$argv[2]", $argv[3], $argv[4]); echo "ok"; } catch (Exception $e) { exit(1); }' \
        "$DB_HOST" "$DB_PORT" "$DB_USERNAME" "$DB_PASSWORD" 2>/dev/null; then
        DB_READY=1
        break
    fi

    if [ "$i" -eq 60 ]; then
        log "ERROR: cannot reach MySQL at ${DB_HOST}:${DB_PORT} after 60s"
        exit 1
    fi

    sleep 1
done

log "MySQL is reachable."

# ==========================================================================
# Install or migrate
# ==========================================================================
if db_initialized; then
    log "Database already initialized, running migrations..."
    php artisan migrate --force --no-interaction
else
    log "Fresh database detected, running Bagisto installer..."
    php artisan bagisto:install --no-interaction

    if ! db_initialized; then
        log "ERROR: the Bagisto installer did not create the database schema."
        log "This usually means APP_ENV=production blocked its destructive commands."
        exit 1
    fi
fi

# The installer cannot run with APP_ENV=production (Laravel cancels its
# destructive commands), so switch to production mode only now that the
# database has been set up. Do NOT export APP_ENV via the container
# environment — .env is the source of truth here.
sed -i 's/^APP_ENV=.*/APP_ENV=production/' .env

# ==========================================================================
# Post-install tasks
# ==========================================================================
log "Creating storage symlink..."
php artisan storage:link --no-interaction || true

log "Caching configuration, routes and views..."
php artisan optimize --no-interaction || true

# The artisan commands above run as root; hand the runtime storage back to
# www-data so PHP-FPM can write sessions, caches and uploads.
log "Restoring storage permissions..."
chown -R www-data:www-data storage bootstrap/cache
chmod -R 775 storage bootstrap/cache

log "Starting services via Supervisor..."

# ==========================================================================
# Hand off to CMD (supervisord)
# ==========================================================================
exec "$@"
