#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

export USER_UID=$(id -u $USERNAME)
export HOSTNAME=$(hostname)
export PASSWORD_FILE="/data/pw"
export SSL_CERT="/data/ssl.crt"
export SSL_KEY="/data/ssl.key"
export DAEMON_URL="https://raw.githubusercontent.com/portalplatform/apps/master/pchat/latest.tar.gz"

# Packages
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y prosody pwgen

# Allow lua to bind to privileged ports (port 80).
setcap cap_net_bind_service=+ep /usr/bin/lua5.1 

# Generate password, if necessary.
[ -e $PASSWORD_FILE ] || pwgen 10 1 > $PASSWORD_FILE
export PASSWORD=$(cat $PASSWORD_FILE)

# Generate self-signed cert, if necessary.
if [ ! -e $SSL_CERT ] ; then
    openssl req \
        -new \
        -newkey rsa:2048 \
        -days 1000 \
        -nodes \
        -x509 \
        -subj "/C=US/ST=Personal/L=Cloud/O=IT/CN=$DOMAIN" \
        -keyout $SSL_KEY \
        -out $SSL_CERT

    chown prosody:prosody $SSL_KEY
    chmod 400 $SSL_KEY

    chown prosody:prosody $SSL_CERT
    chmod 600 $SSL_CERT

fi

# Copy certs to /etc/prosody/certs/
# TODO: figure out why we it wasn't reading from /data (dir permission?).
cp -a $SSL_KEY "/etc/prosody/certs/$DOMAIN.key"
cp -a $SSL_CERT "/etc/prosody/certs/$DOMAIN.crt"

# Create Prosody config.
cat <<CONFIG >/etc/prosody/prosody.cfg.lua
allow_registration = false;
admins = { "$DOMAIN@$DOMAIN" }
use_libevent = true;

modules_enabled = {
    "roster"; -- Allow users to have a roster. Recommended ;)
    "saslauth"; -- Authentication for clients and servers. Recommended if you want to log in.
    "tls"; -- Add support for secure TLS on c2s/s2s connections
    "dialback"; -- s2s dialback support
    "disco"; -- Service discovery
    "private"; -- Private XML storage (for room bookmarks, etc.)
    "vcard"; -- Allow users to set vCards
    "time"; -- Let others know the time here on this server
    "ping"; -- Replies to XMPP pings with pongs
    "pep"; -- Enables users to publish their mood, activity, playing music and more
    "admin_adhoc"; -- Allows administration via an XMPP client that supports ad-hoc commands
    "bosh"; -- Enable BOSH clients, aka "Jabber over HTTP"
    "posix"; -- POSIX functionality, sends server to background, enables syslog, etc.
};


http_ports = { 80 }
http_paths = { bosh = "/http-bind" };
consider_bosh_secure = true;

daemonize = true;
authentication = "internal_plain"
storage = "internal";
data_path = "/data";

c2s_require_encryption = true;
s2s_secure_auth = false
s2s_insecure_domains = { "gmail.com" }
s2s_secure_domains = { "jabber.org" }

log = {
    info = "/var/log/prosody/prosody.log";
    error = "/var/log/prosody/prosody.err";
    {
        levels = { "error" };
        to = "syslog";
    }
}

ssl = {
    key = "/etc/prosody/certs/$DOMAIN.key";
    certificate = "/etc/prosody/certs/$DOMAIN.crt";
}

pidfile = "/var/run/prosody/prosody.pid";

VirtualHost "$DOMAIN"
    enabled = true;

CONFIG

# Clear logs
echo "" > /var/log/prosody/prosody.log
echo "" > /var/log/prosody/prosody.err

# Restart service
service prosody restart

# Add the user account, if necessary.
if [ -z "$(find /data -name accounts -type d)" ] ; then
    prosodyctl register "$DOMAIN" "$DOMAIN" "$PASSWORD"
fi

# The pchat web interface (listens on port 81)
cd /opt/ && wget $DAEMON_URL && tar xvfz $(basename $DAEMON_URL)

# Create the Upstart job.
cat <<UPSTART >/etc/init/pchat.conf
description "pchat"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
script
    cd /opt
    export PORTAL_USERNAME="$USERNAME"
    export PORTAL_PASSWORD="$PASSWORD"
    export PORTAL_DOMAIN="$DOMAIN"
    export PORTAL_PREFIX="$PRIVATE_URI"
    ./pchat
end script
UPSTART

start pchat

# Sync files in memory to disk.
sync

