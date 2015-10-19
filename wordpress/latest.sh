#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

# Apparmor
echo 'alias /var/lib/mysql/ -> /data/mysql/,' >>/etc/apparmor.d/tunables/alias
service apparmor reload

mkdir /etc/mysql/
cat <<MYCNF >/etc/mysql/my.cnf
[client]
port                    = 3306
socket                  = /var/run/mysqld/mysqld.sock

[mysqld_safe]
socket                  = /var/run/mysqld/mysqld.sock
nice                    = 0

[mysqld]
user                    = mysql
pid-file                = /var/run/mysqld/mysqld.pid
socket                  = /var/run/mysqld/mysqld.sock
port                    = 3306
basedir                 = /usr
datadir                 = /data/mysql
tmpdir                  = /tmp
lc-messages-dir         = /usr/share/mysql
skip-external-locking
bind-address            = 127.0.0.1
key_buffer              = 16M
max_allowed_packet      = 16M
thread_stack            = 192K
thread_cache_size       = 8
myisam-recover          = BACKUP
query_cache_limit       = 1M
query_cache_size        = 16M
expire_logs_days        = 10
max_binlog_size         = 100M

[mysqldump]
quick
quote-names
max_allowed_packet      = 16M

[isamchk]
key_buffer              = 16M

!includedir /etc/mysql/conf.d/
MYCNF

# Packages
export DEBIAN_FRONTEND=noninteractive
apt-get update

# Tell dpkg to use existing /etc/mysql/my.cnf.
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    mysql-common \
    mysql-server \
    mysql-client 



apt-get install -y \
    ssmtp \
    nginx \
    pwgen \
    php5-fpm \
    php5-mysql \
    php-apc \
    php5-curl \
    php5-gd \
    php5-intl \
    php-pear \
    php5-imagick \
    php5-imap \
    php5-mcrypt \
    php5-ming \
    php5-ps \
    php5-pspell \
    php5-recode \
    php5-sqlite \
    php5-tidy \
    php5-xmlrpc \
    php5-xsl

# sstmp
cat <<SSMTP >/etc/ssmtp/ssmtp.conf
root=postmaster
mailhub=$DOMAIN
hostname=$HOSTNAME@$DOMAIN
FromLineOverride=YES
SSMTP


# PHP
sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 100M/g" /etc/php5/fpm/php.ini
sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 100M/g" /etc/php5/fpm/php.ini
sed -i -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" /etc/php5/fpm/pool.d/www.conf
sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php5/fpm/php.ini
sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php5/fpm/php.ini

service php5-fpm restart


# Initial setup.
if [ ! -e /data/mysql.pw ] ; then
    pwgen 15 1 >/data/mysql.pw
    mysql_pw=$(cat /data/mysql.pw)

    pwgen 15 1 >/data/db.pw
    export DB_PASSWORD=$(cat /data/db.pw)

    # Setup database.
    mysqladmin -uroot password "$mysql_pw"

    cat <<SQL | mysql -v -v -uroot "-p$mysql_pw"
DELETE FROM mysql.user WHERE User = 'root' AND Host NOT IN ('localhost', '127.0.0.1');
DELETE FROM mysql.user WHERE User = '';

CREATE DATABASE wordpress;
GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress'@'localhost' IDENTIFIED BY '$DB_PASSWORD';

FLUSH PRIVILEGES;
SQL
else
    export DB_PASSWORD=$(cat /data/db.pw)
fi

cat <<NGINX >/etc/nginx/sites-available/default
server {
    listen 81;
    return 302 https://${DOMAIN}${PUBLIC_URI_WITHSLASH}wp-admin/;
}

server {
    listen 80;
    server_name $DOMAIN;

    root /opt/wordpress;
    client_max_body_size 100m;
    charset utf-8;

    allow 127.0.0.1;
    allow $GATEWAY;
    deny all;

    gzip on;
    gzip_http_version 1.1;
    gzip_vary on;
    gzip_comp_level 6;
    gzip_proxied any;
    gzip_min_length  1100;
    gzip_buffers 16 8k;
    gzip_types text/plain text/css application/x-javascript text/xml application/xml application/xml+rss text/javascript;
    gzip_disable "MSIE [1-6].(?!.*SV1)";

    index index.php index.html;

    location $PUBLIC_URI_WITHSLASH {
        alias /opt/wordpress/;

        location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
            expires max;
        }

        try_files \$uri \$uri/ ${PUBLIC_URI_WITHSLASH}index.php?\$args;
    }

    location ~ [^/]\.php(/|$) {
        fastcgi_split_path_info ^${PUBLIC_URI_WITHSLASH}(.+\.php)(.*)$;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME /opt/wordpress/\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_intercept_errors on;
        fastcgi_pass unix:/var/run/php5-fpm.sock;
    }

}
NGINX
service nginx restart


# Download
cd /opt
wget http://wordpress.org/latest.tar.gz
echo "$(curl --silent https://wordpress.org/latest.tar.gz.sha1) latest.tar.gz" | sha1sum -c
tar xf latest.tar.gz

# Configure
cd wordpress/

cat <<CONFIG >wp-config.php
<?php
define('DB_NAME',          'wordpress');
define('DB_USER',          'wordpress');
define('DB_PASSWORD',      '$DB_PASSWORD');
define('DB_HOST',          'localhost');
define('DB_CHARSET',       'utf8');
define('AUTH_KEY',         '$(pwgen 65 1)');
define('SECURE_AUTH_KEY',  '$(pwgen 65 1)');
define('LOGGED_IN_KEY',    '$(pwgen 65 1)');
define('NONCE_KEY',        '$(pwgen 65 1)');
define('AUTH_SALT',        '$(pwgen 65 1)');
define('SECURE_AUTH_SALT', '$(pwgen 65 1)');
define('LOGGED_IN_SALT',   '$(pwgen 65 1)');
define('NONCE_SALT',       '$(pwgen 65 1)');
define('WP_DEBUG',         false);
\$table_prefix = 'wp_';
define('WP_SITEURL',       'https://${DOMAIN}${PUBLIC_URI_WITHSLASH}');
define('WP_HOME',          'https://${DOMAIN}${PUBLIC_URI_WITHSLASH}');
define('FORCE_SSL_ADMIN',  true);
\$_SERVER['HTTPS'] = 'on';


/* DO NOT EDIT. MUST BE LAST. */
define('ABSPATH',          '/opt/wordpress/');
require_once(ABSPATH.'wp-settings.php');
CONFIG

# Store wp-content/ on /data/.
if [ ! -d /data/wp-content ] ; then
    mv wp-content /data/
else
    rm -rf wp-content
fi

ln -s /data/wp-content .

chown -R www-data:www-data /opt/wordpress/ /data/wp-content/



