# Following official WordPress dockerfile:
# https://github.com/docker-library/wordpress/blob/master/latest/php7.4/apache/Dockerfile
# The main modification starts at the beginning of the file by changing the image, see the FROM stmt.
# Other important modifications start at the end of the file (MOD section).
# See overall description below.
# Modifications:
# └─ Replaces PHP image with php:${PHP_VERSION}-apache-<debian-version>
# └─ Drops the WordPress installation completely because WordPress being pulled from GitHub
# └─ Installs additional Linux packages
# └─ Installs Composer and WP-CLI
# └─ Installs additional PHP extensions (pdo_mysql)
# └─ Adds SSL support
# └─ Replaces Entrypoint script, see `init.sh`

ARG PHP_VERSION

FROM php:${PHP_VERSION}-apache-buster

# Don't move these args to top, otherwise they will be collected by
# the "FROM" statement and will not be visible at the bottom
ARG WORDPRESS_VERSION
ARG SSL_SUBJECT
ARG XDEBUG_VERSION
ARG XDEBUG_PORT

# Host OSTYPE
COPY host_ostype /etc

# persistent dependencies
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
# Ghostscript is required for rendering PDF previews
		ghostscript \
	; \
	rm -rf /var/lib/apt/lists/*

# install the PHP extensions we need (https://make.wordpress.org/hosting/handbook/handbook/server-environment/#php-extensions)
RUN set -ex; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libfreetype6-dev \
		libicu-dev \
		libjpeg-dev \
		libmagickwand-dev \
		libpng-dev \
		libwebp-dev \
		libzip-dev \
	; \
	\
	docker-php-ext-configure gd \
		--with-freetype \
		--with-jpeg \
		--with-webp \
	; \
	docker-php-ext-install -j "$(nproc)" \
		bcmath \
		exif \
		gd \
		intl \
		mysqli \
		zip \
	; \
# https://pecl.php.net/package/imagick
	pecl install imagick-3.6.0; \
	docker-php-ext-enable imagick; \
	rm -r /tmp/pear; \
	\
# some misbehaving extensions end up outputting to stdout 🙈 (https://github.com/docker-library/wordpress/issues/669#issuecomment-993945967)
	out="$(php -r 'exit(0);')"; \
	[ -z "$out" ]; \
	err="$(php -r 'exit(0);' 3>&1 1>&2 2>&3)"; \
	[ -z "$err" ]; \
	\
	extDir="$(php -r 'echo ini_get("extension_dir");')"; \
	[ -d "$extDir" ]; \
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$extDir"/*.so \
		| awk '/=>/ { print $3 }' \
		| sort -u \
		| xargs -r dpkg-query -S \
		| cut -d: -f1 \
		| sort -u \
		| xargs -rt apt-mark manual; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	\
	! { ldd "$extDir"/*.so | grep 'not found'; }; \
# check for output like "PHP Warning:  PHP Startup: Unable to load dynamic library 'foo' (tried: ...)
	err="$(php --version 3>&1 1>&2 2>&3)"; \
	[ -z "$err" ]

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN set -eux; \
	docker-php-ext-enable opcache; \
	{ \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=2'; \
		echo 'opcache.fast_shutdown=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini
# https://wordpress.org/support/article/editing-wp-config-php/#configure-error-logging
RUN { \
# https://www.php.net/manual/en/errorfunc.constants.php
# https://github.com/docker-library/wordpress/issues/420#issuecomment-517839670
		echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
		echo 'display_errors = Off'; \
		echo 'display_startup_errors = Off'; \
		echo 'log_errors = On'; \
		echo 'error_log = /dev/stderr'; \
		echo 'log_errors_max_len = 1024'; \
		echo 'ignore_repeated_errors = On'; \
		echo 'ignore_repeated_source = Off'; \
		echo 'html_errors = Off'; \
	} > /usr/local/etc/php/conf.d/error-logging.ini

RUN set -eux; \
	a2enmod rewrite expires; \
	\
# https://httpd.apache.org/docs/2.4/mod/mod_remoteip.html
	a2enmod remoteip; \
	{ \
		echo 'RemoteIPHeader X-Forwarded-For'; \
# these IP ranges are reserved for "private" use and should thus *usually* be safe inside Docker
		echo 'RemoteIPTrustedProxy 10.0.0.0/8'; \
		echo 'RemoteIPTrustedProxy 172.16.0.0/12'; \
		echo 'RemoteIPTrustedProxy 192.168.0.0/16'; \
		echo 'RemoteIPTrustedProxy 169.254.0.0/16'; \
		echo 'RemoteIPTrustedProxy 127.0.0.0/8'; \
	} > /etc/apache2/conf-available/remoteip.conf; \
	a2enconf remoteip; \
# https://github.com/docker-library/wordpress/issues/383#issuecomment-507886512
# (replace all instances of "%h" with "%a" in LogFormat)
	find /etc/apache2 -type f -name '*.conf' -exec sed -ri 's/([[:space:]]*LogFormat[[:space:]]+"[^"]*)%h([^"]*")/\1%a\2/g' '{}' +


# MOD

# Additional Linux Packages (install if necessary => curl, libcurl4-gnutls-dev)
# └─ Archive management => zip, unzip
# └─ A basic Text Editor => nano
# └─ Permission management => acl
# └─ Packages needed for WP Unit Testing => subversion, mariadb-client
# └─ Git
RUN apt update && apt install -y --no-install-recommends zip unzip nano acl subversion mariadb-client git iputils-ping
COPY init.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init.sh

# Get the WordPress
# └─ This is needed only for WordPress platform updates with weld command-line tool, see `weld wp update`
RUN cd /usr/src && \
curl -O https://wordpress.org/wordpress-${WORDPRESS_VERSION}.zip && \
unzip -o wordpress-${WORDPRESS_VERSION}.zip && \
rm wordpress-${WORDPRESS_VERSION}.zip

# Composer
COPY install-composer.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/install-composer.sh && install-composer.sh

# WP Cli
RUN cd /tmp && \
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
php wp-cli.phar --info && \
chmod +x wp-cli.phar && \
mv wp-cli.phar /usr/local/bin/wp

# Additional PHP Extensions
RUN docker-php-ext-install pdo_mysql

# SSL
RUN openssl \
req -newkey rsa:2048 -nodes \
-keyout /etc/ssl/private/ssl-cert-snakeoil.key -x509 -days 1095 \
-out /etc/ssl/certs/ssl-cert-snakeoil.pem \
-subj ${SSL_SUBJECT} && \
# └─ Apache Modules needed for SSL
ln -fs /etc/apache2/sites-available/default-ssl.conf /etc/apache2/sites-enabled/default-ssl.conf && \
ln -fs /etc/apache2/mods-available/ssl.conf /etc/apache2/mods-enabled/ssl.conf && \
ln -fs /etc/apache2/mods-available/ssl.load /etc/apache2/mods-enabled/ssl.load && \
ln -fs /etc/apache2/mods-available/socache_shmcb.load /etc/apache2/mods-enabled/socache_shmcb.load

# XDebug
RUN pecl install xdebug-${XDEBUG_VERSION} && \
{ \
    echo "zend_extension=xdebug"; \
    echo "\n"; \
    echo "[xdebug]"; \
} > /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini && \
{ \
    echo "html_errors = On"; \
} > /usr/local/etc/php/conf.d/error-logging.xdebug.ini && \
docker-php-ext-enable xdebug

ENTRYPOINT ["bash", "-c", "/usr/local/bin/init.sh"]
