#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

# Packages
export DEBIAN_FRONTEND="noninteractive"
apt-get update
apt-get install -y --no-install-recommends \
    nginx git sqlite3 \
    php5-fpm php5-cli php5-gd php5-sqlite php5-curl

# Download
cd /opt/

git clone --depth 1 https://github.com/fguillot/kanboard.git

cd kanboard/

curl -sS https://getcomposer.org/installer | php

mv composer.phar /usr/local/bin/composer

COMPOSER_HOME=$(mktemp --directory --tmpdir=/opt) composer --prefer-source --no-dev --no-interaction --no-ansi install

cat <<CONFIG >config.php
<?php
define('DEBUG', false);
define('DEBUG_FILE', __DIR__.'/data/debug.log');
define('FILES_DIR', 'data/files');

// EMail
define('MAIL_FROM', 'kanboard@$DOMAIN');
define('MAIL_TRANSPORT', 'smtp');
define('MAIL_SMTP_HOSTNAME', '$DOMAIN');
define('MAIL_SMTP_PORT', 25);
define('MAIL_SMTP_USERNAME', '');
define('MAIL_SMTP_PASSWORD', '');
define('MAIL_SMTP_ENCRYPTION', null); // Valid values are "null", "ssl" or "tls"
define('MAIL_SENDMAIL_COMMAND', '/usr/sbin/sendmail -bs');

// Third-party email servers.
define('POSTMARK_API_TOKEN', '');
define('MAILGUN_API_TOKEN', '');
define('MAILGUN_DOMAIN', '');
define('SENDGRID_API_USER', '');
define('SENDGRID_API_KEY', '');
define('DB_DRIVER', 'sqlite');

// MySQL/PostgreSQL
define('DB_USERNAME', 'root');
define('DB_PASSWORD', '');
define('DB_HOSTNAME', 'localhost');
define('DB_NAME', 'kanboard');
define('DB_PORT', null);

// LDAP
define('LDAP_AUTH', false);
define('LDAP_SERVER', '');
define('LDAP_PORT', 389);
define('LDAP_SSL_VERIFY', true);
define('LDAP_START_TLS', false);
define('LDAP_BIND_TYPE', 'anonymous');
define('LDAP_USERNAME', null);
define('LDAP_PASSWORD', null);
define('LDAP_ACCOUNT_BASE', '');
define('LDAP_USER_PATTERN', '');
define('LDAP_ACCOUNT_FULLNAME', 'displayname');
define('LDAP_ACCOUNT_EMAIL', 'mail');
define('LDAP_ACCOUNT_ID', 'samaccountname');
define('LDAP_USERNAME_CASE_SENSITIVE', false);
define('LDAP_ACCOUNT_CREATION', true);

// APIs
define('GOOGLE_AUTH', false);
define('GOOGLE_CLIENT_ID', '');
define('GOOGLE_CLIENT_SECRET', '');
define('GITHUB_AUTH', false);
define('GITHUB_CLIENT_ID', '');
define('GITHUB_CLIENT_SECRET', '');
define('GITHUB_OAUTH_AUTHORIZE_URL', 'https://github.com/login/oauth/authorize');
define('GITHUB_OAUTH_TOKEN_URL', 'https://github.com/login/oauth/access_token');
define('GITHUB_API_URL', 'https://api.github.com/');
define('GITLAB_AUTH', false);
define('GITLAB_CLIENT_ID', '');
define('GITLAB_CLIENT_SECRET', '');
define('GITLAB_OAUTH_AUTHORIZE_URL', 'https://gitlab.com/oauth/authorize');
define('GITLAB_OAUTH_TOKEN_URL', 'https://gitlab.com/oauth/token');
define('GITLAB_API_URL', 'https://gitlab.com/api/v3/');

// Reverse Proxy
define('REVERSE_PROXY_AUTH', true);
// It's actually X-Authenticated-User but PHP converts to uppercase.
define('REVERSE_PROXY_USER_HEADER', 'HTTP_X_AUTHENTICATED_USER');
define('REVERSE_PROXY_DEFAULT_ADMIN', '$USERNAME');
define('REVERSE_PROXY_DEFAULT_DOMAIN', '$DOMAIN');
define('REMEMBER_ME_AUTH', true);
define('ENABLE_HSTS', false);
define('ENABLE_XFRAME', true);
define('MARKDOWN_ESCAPE_HTML', true);
define('API_AUTHENTICATION_HEADER', '');
define('ENABLE_URL_REWRITE', false);
define('HIDE_LOGIN_FORM', false);
define('BRUTEFORCE_CAPTCHA', 3);
define('BRUTEFORCE_LOCKDOWN', 6);
define('BRUTEFORCE_LOCKDOWN_DURATION', 15);
define('SESSION_DURATION', 200000);
CONFIG


rm -rf data
[ -d /data/kanboard ] || mkdir -p /data/kanboard/files
ln -s /data/kanboard data

chown -R www-data:www-data /data/
chown -R www-data:www-data /opt/


cat <<PHP >/etc/php5/fpm/conf.d/90-config.ini
display_errors          = Off
log_errors              = On
upload_max_filesize     = 100M
post_max_size           = 101M
memory_limit            = 128M
register_globals        = Off
zlib.output_compression = Off
magic_quotes_gpc        = Off
magic_quotes_runtime    = Off
suhosin.session.encrypt = Off

session.cookie_path     = "$PUBLIC_URI_WITHSLASH"
session.cookie_lifetime = 200000
session.hash_function   = sha256
session.auto_start      = Off
session.gc_maxlifetime  = 21600
session.gc_divisor      = 500
session.gc_probability  = 1
PHP
service php5-fpm restart


# Nginx
cat <<NGINX >/etc/nginx/sites-enabled/default
server {
    listen 81;
    server_name $DOMAIN;
    return 302 https://${DOMAIN}${PUBLIC_URI_WITHSLASH};
}

server {
    listen 80;
    server_name $DOMAIN;
    root /opt/kanboard/;

    client_max_body_size 100m;

    allow 127.0.0.1;
    allow $GATEWAY;
    deny all;

    location ${PUBLIC_URI_WITHSLASH}data/ {
        deny all;
    }

    location ~ /\.ht {
        deny all;
        return 404;
    }

    location $PUBLIC_URI_WITHSLASH {
        alias /opt/kanboard/;
        index index.php index.html;
    }

    location ~ [^/]\.php(/|$) {
        fastcgi_split_path_info ^$PUBLIC_URI_WITHSLASH(.+?\.php)(.*)$;
        fastcgi_pass unix:/var/run/php5-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME /opt/kanboard/\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }
}
NGINX
service nginx restart


if [ ! -e /data/kanboard/db.sqlite ] ; then

    until curl --output /dev/null --silent --fail "http://localhost$PUBLIC_URI_WITHSLASH" ; do
        sleep 1
    done

    echo "DELETE FROM users WHERE username = 'admin';" | sqlite3 /data/kanboard/db.sqlite
fi

