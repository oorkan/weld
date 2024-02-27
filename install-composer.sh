#!/bin/sh
# Forked and modified from https://getcomposer.org/doc/faqs/how-to-install-composer-programmatically.md

EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
php -r "copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');"
ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');")"

if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]
then
    >&2 echo "ERROR: Invalid installer checksum"
    rm /tmp/composer-setup.php
    exit 1
fi

php /tmp/composer-setup.php --install-dir=/tmp --quiet
RESULT=$?
rm /tmp/composer-setup.php

if [ -f "/tmp/composer.phar" ]
then
    mv /tmp/composer.phar /usr/local/bin/composer
    exit $RESULT
fi

>&2 echo "ERROR: Composer installation failed"
exit 1