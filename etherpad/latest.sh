#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

export PASSWORD_FILE="/data/pw"

#
# Packages
#
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python-software-properties 
apt-add-repository -y ppa:chris-lea/node.js 
apt-get update
apt-get install -y nodejs unzip nginx-extras gzip git curl python libssl-dev pkg-config build-essential pwgen


#
# Generate admin password, if necessary.
#
[ -e $PASSWORD_FILE ] || pwgen 10 1 > $PASSWORD_FILE
export PASSWORD=$(cat $PASSWORD_FILE)
export PASSWORD_BASE64=$(echo -n "admin:$PASSWORD" | base64)


#
# Nginx proxy.
#
cat <<NGINX > /etc/nginx/sites-available/default
server {
    listen 81;
    return 302 https://${DOMAIN}${PUBLIC_URI_WITHSLASH};
}

server {
    listen 80;
    location $PUBLIC_URI_WITHSLASH {

        access_by_lua '
                headers = ngx.req.get_headers()
                if headers["X-Authenticated-User"] == "$USERNAME" then
                    ngx.req.set_header("Authorization", "Basic $PASSWORD_BASE64")
                end
        ';

        allow $GATEWAY;
        deny all;

        proxy_pass http://127.0.0.1:9001/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX

service nginx restart

#
# Download and setup Etherpad
#

npm install -g sqlite3

cd /opt/

git clone https://github.com/ether/etherpad-lite.git

cd etherpad-lite/

cat <<CONFIG >settings.json
{
    "title": "Etherpad",
    "favicon": "favicon.ico",
    "ip": "127.0.0.1",
    "port" : 9001,
    "dbType" : "sqlite",
    "dbSettings" : { "filename" : "/data/etherpad.db" },
    "defaultPadText" : "Welcome to Etherpad!\n\nThis pad text is synchronized as you type, so that everyone viewing this page sees the same text. This allows you to collaborate seamlessly on documents!\n\nGet involved with Etherpad at http:\/\/etherpad.org\n",
    "padOptions": {
        "noColors": false,
        "showControls": true,
        "showChat": true,
        "showLineNumbers": true,
        "useMonospaceFont": false,
        "userName": false,
        "userColor": false,
        "rtl": false,
        "alwaysShowChat": false,
        "chatAndUsers": false,
        "lang": "en-gb"
    },
    "users": {
        "admin": {
            "password": "$PASSWORD",
            "is_admin": true
        }
    },
    "suppressErrorsInPadText" : false,
    "requireSession" : false,
    "editOnly" : false,
    "sessionNoPassword" : false,
    "minify" : true,
    "maxAge" : 21600, // 60 * 60 * 6 = 6 hours
    "abiword" : null,
    "tidyHtml" : null,
    "allowUnknownFileEnds" : true,
    "requireAuthentication" : false,
    "requireAuthorization" : false,
    "trustProxy" : true,
    "disableIPlogging" : false,
    "socketTransportProtocols" : ["xhr-polling", "jsonp-polling", "htmlfile"],
    "loadTest": false,
    "loglevel": "INFO",
    "logconfig" : { "appenders": [ { "type": "console" } ] }
}
CONFIG

chown -R $USERNAME:$USERNAME ./


#
# Create and start the Ghost daemon.
#
cat <<UPSTART > /etc/init/etherpad.conf
description "Etherpad"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
script
    su -s /bin/sh -l $USERNAME -c 'cd /opt/etherpad-lite/ && export NODE_ENV=production && bin/run.sh'
end script
UPSTART

start etherpad

#
# Sync files in memory to disk.
#
sync


# Wait until it's up
until curl --output /dev/null --silent --fail "http://127.0.0.1:9001/"; do
    sleep 2
done

