# =============================================================================
# Bagisto App Image — Nginx + PHP 8.3 FPM + Supervisor
#
# Intended for Dokploy Docker Compose deployments. Expects EXTERNAL MySQL and
# Redis services (no bundled database). The application is installed at
# RUNTIME on first boot by docker/deploy/entrypoint.sh.
#
# Build context: repository root (see root .dockerignore).
# =============================================================================

FROM ubuntu:24.04

ARG PHP_VERSION=8.3

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# ---------------------------------------------------------------------------
# System packages + PHP PPA + Composer
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        git \
        gnupg \
        nano \
        software-properties-common \
        unzip \
    && add-apt-repository ppa:ondrej/php -y \
    && apt-get update && apt-get install -y \
        imagemagick \
        nginx \
        supervisor \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# PHP 8.3 + extensions
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
        php${PHP_VERSION}-bcmath \
        php${PHP_VERSION}-calendar \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-exif \
        php${PHP_VERSION}-fpm \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-gmp \
        php${PHP_VERSION}-imagick \
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-pdo \
        php${PHP_VERSION}-redis \
        php${PHP_VERSION}-soap \
        php${PHP_VERSION}-sockets \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-zip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# ---------------------------------------------------------------------------
# Application source + dependencies
# ---------------------------------------------------------------------------
WORKDIR /var/www/bagisto

COPY . .

# Mirror (copy) path repositories instead of symlinking them — safer in a
# container image where relative symlinks can otherwise dangle.
ENV COMPOSER_MIRROR_PATH_REPOS=1

RUN composer install \
        --no-dev \
        --no-interaction \
        --prefer-dist \
        --optimize-autoloader \
        --no-scripts \
    && rm -rf /root/.composer/cache

# ---------------------------------------------------------------------------
# Runtime directory skeleton (storage/ and bootstrap/cache/ are excluded from
# the build context; a fresh empty layout is created here)
# ---------------------------------------------------------------------------
RUN mkdir -p \
        /run/php \
        /var/log/supervisor \
        /var/log/bagisto \
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

# ---------------------------------------------------------------------------
# Prepare .env with production defaults (overridden at runtime by entrypoint)
#
# NOTE: APP_ENV deliberately stays as shipped in .env.example (`local`): the
# Bagisto installer runs during the container's first boot, and Laravel
# cancels its `migrate:fresh`/`db:wipe`/`key:generate` steps when the app is
# in production mode. The entrypoint flips APP_ENV to production right after
# installation completes.
# ---------------------------------------------------------------------------
RUN cp .env.example .env \
    && sed -i 's/^APP_DEBUG=.*/APP_DEBUG=false/' .env \
    && php artisan key:generate --force --no-interaction

# ---------------------------------------------------------------------------
# PHP configuration
# ---------------------------------------------------------------------------
COPY docker/production/shared/php.ini /etc/php/${PHP_VERSION}/fpm/conf.d/99-production.ini
COPY docker/production/nginx/config/php-fpm.conf /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf

# ---------------------------------------------------------------------------
# Nginx configuration
# ---------------------------------------------------------------------------
RUN rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf
COPY docker/production/nginx/config/nginx.conf /etc/nginx/conf.d/bagisto.conf

# ---------------------------------------------------------------------------
# Supervisor configuration
# ---------------------------------------------------------------------------
COPY docker/deploy/supervisord.conf /etc/supervisor/conf.d/bagisto.conf

# ---------------------------------------------------------------------------
# Permissions
# ---------------------------------------------------------------------------
RUN chown -R www-data:www-data /var/www/bagisto \
    && chmod -R 775 storage bootstrap/cache \
    && find storage bootstrap/cache -type d -exec chmod g+s {} +

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
COPY docker/deploy/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
RUN apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
