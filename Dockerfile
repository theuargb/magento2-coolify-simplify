# Stage 1: Build Stage
# Use PHP 8.3 with CLI and necessary extensions for Composer and Magento build commands
FROM php:8.3-cli AS builder

LABEL stage="magento-builder"

# Install system dependencies required for composer and extensions
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    libzip-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libicu-dev \
    libonig-dev \
    libxslt-dev \
    # libmcrypt-dev removed (deprecated) \
    libwebp-dev \
    libmagickwand-dev \
    # Added dependencies for required extensions
    libxml2-dev \
    libssl-dev \
    zlib1g-dev \
    libcurl4-openssl-dev \
    libsodium-dev \
    acl \
    --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# Install PHP extensions required by Magento
# Configure gd first
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp
# Install core extensions (zlib is usually enabled by zlib1g-dev, sodium added)
RUN docker-php-ext-install -j$(nproc) \
    bcmath \
    gd \
    intl \
    mbstring \
    opcache \
    pdo_mysql \
    soap \
    sockets \
    xsl \
    curl \
    fileinfo \
    ftp \
    iconv \
    sodium \
    zip

# Install Composer globally
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www/html

# Copy composer files and install dependencies
COPY . .
RUN composer install --no-dev --optimize-autoloader

# Copy the rest of the application code
COPY . .

# Run Magento build commands
# Note: Ensure your app/etc/env.php has DB connection details or use environment variables
# If DB is needed during build, ensure it's accessible
RUN php -d memory_limit=-1 bin/magento setup:di:compile
# RUN php -d memory_limit=-1 bin/magento setup:static-content:deploy -f -j $(nproc)

# Fix permissions for generated files (adjust user/group if needed)
RUN chown -R www-data:www-data generated/ var/ pub/static/ pub/media/ app/etc/

# Grant Nginx user (UID 101) read/execute access to pub directory for shared volume
RUN setfacl -R -m u:101:rx -m d:u:101:rx pub/

# Stage 2: Runtime Stage
# Use PHP 8.3 FPM image
FROM php:8.3-fpm

LABEL stage="magento-runtime"


# Install system dependencies required for composer and extensions
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    libzip-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libicu-dev \
    libonig-dev \
    libxslt-dev \
    # libmcrypt-dev removed (deprecated) \
    libwebp-dev \
    libmagickwand-dev \
    # Added dependencies for required extensions
    libxml2-dev \
    libssl-dev \
    zlib1g-dev \
    libcurl4-openssl-dev \
    libsodium-dev \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions required by Magento
# Configure gd first
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp
# Install core extensions (zlib is usually enabled by zlib1g-dev, sodium added)
RUN docker-php-ext-install -j$(nproc) \
    bcmath \
    gd \
    intl \
    mbstring \
    opcache \
    pdo_mysql \
    soap \
    sockets \
    xsl \
    curl \
    fileinfo \
    ftp \
    iconv \
    sodium \
    zip

# Set working directory
WORKDIR /var/www/html

# Copy built artifacts from the builder stage
COPY --from=builder /var/www/html/vendor ./vendor
COPY --from=builder /var/www/html/generated ./generated
COPY --from=builder /var/www/html/pub/static ./pub/static

# Copy the rest of the application code (excluding vendor/generated/pub/static already copied)
COPY . .

# Ensure correct ownership for runtime (FPM usually runs as www-data)
# The volume mount for pub/media will be handled by docker-compose
RUN chown -R www-data:www-data .

# Expose FPM port
EXPOSE 9000

# Ensure var directory is writable by www-data after volume mount, then start PHP-FPM
CMD chown www-data:www-data /var/www/html/var && php-fpm
