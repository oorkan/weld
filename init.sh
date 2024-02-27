#! /usr/bin/env bash

# disable acl operations when macOS
if [[ `cat /etc/host_ostype` != 'darwin'* ]]; then

    find /var/www/html/ -type d -exec setfacl -m default:user:www-data:rwx {} +
    find /var/www/html/ -type f -exec setfacl -m user:www-data:rw {} +

    find /var/www/html/ -type d -exec setfacl -m default:group:www-data:rwx {} +
    find /var/www/html/ -type f -exec setfacl -m group:www-data:rw {} +

    find /var/www/html/ -type f -exec chmod 664 {} +
    find /var/www/html/ -type f -name wp-config.php -exec chmod 644 {} +
    find /var/www/html/ -type d -exec chmod 775 {} +

fi

exec apache2-foreground
