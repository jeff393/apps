#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

export DEBIAN_FRONTEND=noninteractive
apt-get install python-software-properties

# Add some PPAs
apt-add-repository -y ppa:andrewrk/libgroove
apt-add-repository -y ppa:chris-lea/node.js
apt-get update -y
apt-get install -y build-essential git nginx
apt-get install -y libgroove-dev libgrooveplayer-dev libgrooveloudness-dev libgroovefingerprinter-dev
apt-get install -y nodejs

# Nginx
cat <<NGINX >/etc/nginx/sites-enabled/default
server {
    listen 81;
    server_name $DOMAIN;
    return 302 https://${DOMAIN}${PUBLIC_URI_WITHSLASH};
}
server {
    listen 80;
    location $PUBLIC_URI_WITHSLASH {
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_redirect / $PUBLIC_URI_WITHSLASH;
        proxy_pass http://127.0.0.1:16242/;
    }
}
NGINX

service nginx restart


# Music directory
[ -d /data/music ] || mkdir /data/music

# Download
cd /opt/
git clone https://github.com/andrewrk/groovebasin.git

cd groovebasin/

cat <<CONFIG >config.json
{
    "host": "127.0.0.1",
    "port": 16242,
    "dbPath": "/data/groovebasin.db",
    "musicDirectory": "/data/music",
    "lastFmApiKey": "bb9b81026cd44fd086fa5533420ac9b4",
    "lastFmApiSecret": "2309a40ae3e271de966bf320498a8f09",
    "mpdHost": "0.0.0.0",
    "mpdPort": 6600,
    "acoustidAppKey": "bgFvC4vW",
    "encodeQueueDuration": 8,
    "encodeBitRate": 256,
    "sslKey": null,
    "sslCert": null,
    "sslCaDir": null,
    "googleApiKey": "AIzaSyDdTDD8-gu_kp7dXtT-53xKcVbrboNAkpM",
    "ignoreExtensions": [
        ".jpg", ".jpeg", ".txt", ".png", ".log", ".cue", ".pdf", ".m3u", ".nfo", ".ini", ".xml", ".zip"
    ]
}
CONFIG

chown -R $USERNAME:$USERNAME /opt/ /data/

# Setup
su -l $USERNAME -s /bin/bash -c "unset NODE_PATH; cd /opt/groovebasin/ && npm run build"

# Service
cat <<UPSTART >/etc/init/groovebasin.conf
description "groovebasin"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
script
    su -l $USERNAME -s /bin/bash -c "unset NODE_PATH; cd /opt/groovebasin/ && npm start"
end script
UPSTART

start groovebasin

# Flush file system buffers
sync

# Wait until it's up
until curl --output /dev/null --silent --fail "https://${DOMAIN}${PUBLIC_URI_WITHSLASH}"; do
    sleep 2
done

