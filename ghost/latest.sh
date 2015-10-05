#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

export DAEMON_URL="https://ghost.org/zip/ghost-0.6.4.zip"

# Packages
# TODO: test and switch to sourcenode repo.
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python-software-properties 
apt-add-repository -y ppa:chris-lea/node.js 

apt-get update
apt-get install -y nodejs unzip nginx

# Allow nodejs to bind to privileged ports as non-root.
setcap cap_net_bind_service=+ep /usr/bin/nodejs

# Nginx redirect.
cat <<NGINX >/etc/nginx/sites-available/default
server {
    listen 81 default_server;
    return 302 https://${DOMAIN}${PUBLIC_URI_WITHSLASH}ghost;
}
NGINX

service nginx restart

# Download and setup Ghost
cd /opt/ && wget $DAEMON_URL && unzip $(basename $DAEMON_URL)

# TODO: Failing sometimes with:
# npm ERR! cb() never called!
# npm ERR! not ok code 0
until npm install --production ; do
    echo "Trying npm again!"
    npm cache clean
    rm -rf node_modules/
done

[ -d /data/content/ ] || mv content/ /data/
chown -R $USERNAME:$USERNAME /data/content/

cat <<CONFIG >config.js
var path = require('path'), config;

config = {
    production: {
        url: 'https://${DOMAIN}${PUBLIC_URI_WITHSLASH}',
        mail: {
            transport: 'SMTP',
            options: {
                host: '$DOMAIN',
                port: 25,
                service: 'email'
            }
        },
        
        database: {
            client: 'sqlite3',
            connection: {
                filename: '/data/ghost.db'
            },
            debug: false
        },
        paths: {
            contentPath: '/data/content/'
        },
        privacy: {
            useTinfoil: true,
            useUpdateCheck: false
        },
        server: {
            host: '0.0.0.0',
            port: '80'
        }
    }
};

// Export config
module.exports = config;
CONFIG


# Create the Ghost service.
cat <<UPSTART >/etc/init/ghost.conf
description "Ghost"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
script
    su -s /bin/sh -l $USERNAME -c 'cd /opt && export NODE_ENV=production && /usr/bin/nodejs index.js'
end script
UPSTART

start ghost

# Sync files in memory to disk.
sync

# Wait until it's up
until curl --output /dev/null --silent --fail "https://${DOMAIN}${PUBLIC_URI_WITHSLASH}" ; do
    sleep 2
done

