#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

export USER_UID=$(id -u $USERNAME)

# Packages
export DEBIAN_FRONTEND=noninteractive
curl --silent https://syncthing.net/release-key.txt | sudo apt-key add -
echo 'deb http://apt.syncthing.net/ syncthing release' > /etc/apt/sources.list.d/syncthing-release.list
sudo apt-get update
sudo apt-get install -y syncthing nginx

# Nginx
cat <<NGINX > /etc/nginx/sites-available/default
server {
    listen 81;
    location $PRIVATE_URI {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_pass http://localhost:8384/;
    }
}
NGINX
service nginx restart

# Generate config on first run.
if [ ! -e /data/config.xml ] ; then
    su -s /bin/sh -l $USERNAME -c 'syncthing -generate="/data"'
    perl -pi -e "s#/home/$USERNAME/#/data/#" /data/config.xml
fi

# Create the Syncthing service.
cat <<UPSTART >/etc/init/syncthing.conf
description "syncthing"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
script
    su -s /bin/sh -l $USERNAME -c 'syncthing -home=/data -no-browser -no-restart'
end script
UPSTART

start syncthing

# Sync files in memory to disk.
sync

# Wait until it's up
until curl --output /dev/null --silent --fail "http://localhost:8384/"; do sleep 2 done

