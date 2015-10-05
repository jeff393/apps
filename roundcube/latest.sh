#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

export DL_URL="https://downloads.sourceforge.net/project/roundcubemail/roundcubemail/1.1.3/roundcubemail-1.1.3-complete.tar.gz"

# Packages
export DEBIAN_FRONTEND="noninteractive"
apt-get update
apt-get install -y --no-install-recommends \
    pwgen nginx php5-fpm sqlite3 \
    php5-mcrypt php5-intl php5-sqlite php-pear \
    php-net-smtp php-mail-mime

# Roundcube settings
export ROUNDCUBE_DESKEY_FILE="/data/roundcube.deskey"
[ -e $ROUNDCUBE_DESKEY_FILE ] || pwgen 24 1 > $ROUNDCUBE_DESKEY_FILE
export ROUNDCUBE_DESKEY=$(cat $ROUNDCUBE_DESKEY_FILE)


# Download
cd /opt/
wget -O roundcube.tar.gz $DL_URL
tar xfz roundcube.tar.gz
mv roundcubemail-* roundcube

# Fill in the username with some brittle monkey patching.
perl -pi -e "s#'rcmloginuser',\s+'required'#'rcmloginuser', 'value' => '$DOMAIN', 'required'#" /opt/roundcube/program/include/rcmail_output_html.php 
perl -pi -e "s#'rcmloginpwd',\s+'required'#'rcmloginpwd', 'placeholder' => 'Check your email server', 'required'#" /opt/roundcube/program/include/rcmail_output_html.php 


# Configuration
cat <<CONFIG >/opt/roundcube/config/config.inc.php
<?php
\$config = array();
\$config['db_dsnw'] = 'sqlite:////data/roundcube.db?mode=0644';
\$config['default_host'] = 'imaps://$DOMAIN';
\$config['default_port'] = 993;
\$config['imap_auth_type'] = 'PLAIN';
\$config['imap_vendor'] = 'dovecot';
\$config['imap_timeout'] = 15;
\$config['login_autocomplete'] = 2;
\$config['imap_conn_options'] = array(
    'ssl' => array(
        'verify_peer'       => false,
        'verfify_peer_name' => false,
    ),
);
\$config['smtp_server'] = '$DOMAIN';
\$config['smtp_port'] = 25;
\$config['support_url'] = 'mailto:support@portal.cloud';
\$config['product_name'] = '$DOMAIN';
\$config['use_https'] = true;
\$config['des_key'] = '$ROUNDCUBE_DESKEY';
\$config['session_lifetime'] = 60;
\$config['plugins'] = array(
    'archive',
    'zipdownload',
);
\$config['skin'] = 'larry';
CONFIG

# PHP settings
if [ ! -d /data/roundcube.session ] ; then
    mkdir /data/roundcube.session
    chown www-data:www-data /data/roundcube.session
fi

cat <<PHP >/etc/php5/fpm/conf.d/90-roundcube.ini
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

session.cookie_path     = "$PRIVATE_URI"
session.hash_function   = sha256
session.auto_start      = Off
session.gc_maxlifetime  = 21600
session.gc_divisor      = 500
session.gc_probability  = 1
PHP
service php5-fpm restart


# Nginx
chown -R www-data:www-data /opt/roundcube/
cat <<NGINX >/etc/nginx/sites-enabled/default
server {
    listen 81;
    server_name $DOMAIN;

    client_max_body_size 100m;

    location $PRIVATE_URI {
        alias /opt/roundcube/;
        index index.php index.html;

        location ~ [^/]\.php(/|$) {
                fastcgi_split_path_info ^$PRIVATE_URI(.+?\.php)(.*)$;
                fastcgi_pass unix:/var/run/php5-fpm.sock;
                fastcgi_index index.php;
                include fastcgi_params;
                fastcgi_param SCRIPT_FILENAME /opt/roundcube/\$fastcgi_script_name;
                fastcgi_param PATH_INFO \$fastcgi_path_info;
        }
    }
}
NGINX
service nginx restart
