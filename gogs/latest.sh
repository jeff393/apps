#!/bin/bash -x

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

# Settings
export GOGS_VERSION="v0.6.15"
export GOGS_REPO="/data/git/gogs-repositories"
export GOGS_USER="git"
export PASSWORD_FILE="/data/pw"


# User
useradd --shell /bin/bash --system --home /data/git git

# Packages
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y unzip git nginx pwgen

# Generate password, if necessary.
[ -e $PASSWORD_FILE ] || pwgen 10 1 > $PASSWORD_FILE
export PASSWORD=$(cat $PASSWORD_FILE)

# Nginx
cat <<NGINX >/etc/nginx/sites-available/default
server {
    listen 81;
    server_name $DOMAIN;
    return 302 https://${DOMAIN}${PUBLIC_URI_WITHSLASH};
}
server {
    listen 80;
    server_name $DOMAIN;

    allow $GATEWAY;
    deny all;

    location $PUBLIC_URI_WITHSLASH {
        proxy_set_header Host            \$host;
        proxy_set_header X-Real-IP       \$remote_addr;
        proxy_set_header X-Forwarded-for \$remote_addr;
        proxy_pass http://127.0.0.1:3000/;
    }
}
NGINX
service nginx restart

# Download
cd /opt/
wget https://github.com/gogits/gogs/releases/download/${GOGS_VERSION}/linux_amd64.zip
unzip linux_amd64.zip
cd gogs/

# Setup
mkdir -p custom/conf/
cat <<GOGS >custom/conf/app.ini
APP_NAME = $DOMAIN
RUN_USER = $GOGS_USER
RUN_MODE = prod

[server]
DOMAIN = $DOMAIN
ROOT_URL = http://${DOMAIN}${PUBLIC_URI_WITHSLASH}
HTTP_ADDR = 127.0.0.1
HTTP_PORT = 3000
SSH_PORT = $PUBLIC_PORT
OFFLINE_MODE = true
LANDING_PAGE = home

[database]
DB_TYPE = sqlite3
PATH = /data/gogs.db

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = true
ENABLE_REVERSE_PROXY_AUTHENTICATION = true
ENABLE_REVERSE_PROXY_AUTO_REGISTRATION = false

[picture]
DISABLE_GRAVATAR = true

[repository]
ROOT = $GOGS_REPO

[security]
REVERSE_PROXY_AUTHENTICATION_USER = X-Authenticated-User

[mailer]
ENABLED = true
HOST = $DOMAIN

GOGS

# Repo dir
[ -d $GOGS_REPO ] || mkdir -p $GOGS_REPO

# Set permissions
chown -R $GOGS_USER:$GOGS_USER /opt/
chown -R $GOGS_USER:$GOGS_USER /data/

# Create gogs upstart config.
cat <<UPSTART >/etc/init/gogs.conf
description "gogs"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
exec su -s /bin/bash -l $GOGS_USER -c 'cd /opt/gogs/ && ./gogs web --config /opt/gogs/custom/conf/app.ini'
UPSTART

# Start services
service gogs start

# Submit installer form
wget -O /opt/submit-gogs-install-form "https://raw.githubusercontent.com/portalplatform/apps/master/gogs/submit-gogs-install-form"
chmod 755 /opt/submit-gogs-install-form

# Wait until it's up
until curl --output /dev/null --silent --fail "https://${DOMAIN}${PUBLIC_URI_WITHSLASH}" ; do
    sleep 1
done

sleep 1

/opt/submit-gogs-install-form $GOGS_USER $USERNAME $PASSWORD "https://${DOMAIN}${PUBLIC_URI_WITHSLASH}install"

