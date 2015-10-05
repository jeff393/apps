#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)


#
# TODO: uploads are not working because Let's Chat uses an absolute /files/ path.
# should be simple to submit as bug report and/or temporarily patch.
#


cat <<MONGOD >/etc/mongodb.conf
dbpath    = /data/mongodb
logpath   = /var/log/mongodb/mongod.log
logappend = true
bind_ip   = 127.0.0.1
MONGOD

# Packages
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python-software-properties 

apt-add-repository -y ppa:chris-lea/node.js
apt-get update

apt-get install -y build-essential nodejs git nginx pwgen

# Preserve existing /etc/mongodb.conf
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" mongodb

# Mongodb setup
if [ ! -d /data/mongodb ] ; then
    mkdir /data/mongodb
    chown mongodb:mongodb /data/mongodb
    start mongodb || restart mongodb
fi


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
        proxy_pass http://127.0.0.1:5000/;
    }
}
NGINX

service nginx restart


# Download
cd /opt/
git clone https://github.com/sdelements/lets-chat.git
cd lets-chat/

# Config
export LETSCHAT_COOKIE_SECRET_FILE="/data/letschat-cookie.secret"
[ -e $LETSCHAT_COOKIE_SECRET_FILE ] || pwgen 32 1 > $LETSCHAT_COOKIE_SECRET_FILE
export LETSCHAT_COOKIE_SECRET=$(cat $LETSCHAT_COOKIE_SECRET_FILE)

cat <<SETTINGS >settings.yml
env: production

http:
  enable: true
  host: 'localhost'
  port: 5000

https:
  enable: false
  port: 5001
  key: key.pem
  cert: certificate.pem

files:
  enable: false
  provider: local
  local:
    dir: /data/uploads

xmpp:
  enable: false
  port: $PUBLIC_PORT
  domain: $DOMAIN

database:
  uri: mongodb://localhost/letschat

secrets:
  cookie: $LETSCHAT_COOKIE_SECRET

auth:
  providers: [local]
  local:
    enableRegistration: true

SETTINGS

chown -R $USERNAME:$USERNAME /opt/lets-chat/

# NPM
su -l $USERNAME -s /bin/bash -c "unset NODE_PATH; cd /opt/lets-chat/ && npm install"

# Upload dir
if [ ! -d /data/uploads ] ; then
    mkdir /data/uploads
    chown $USERNAME:$USERNAME /data/uploads
fi

# lets-chat service
cat <<UPSTART >/etc/init/lets-chat.conf
description "lets-chat"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
script
    su -l $USERNAME -s /bin/bash -c "unset NODE_PATH; cd /opt/lets-chat/ && npm start"
end script
UPSTART

start lets-chat

# Flush file system buffers
sync

# Wait until it's up
until curl --output /dev/null --silent --fail "https://${DOMAIN}${PUBLIC_URI_WITHSLASH}"; do
    sleep 2
done

