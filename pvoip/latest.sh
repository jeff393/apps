#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

export USER_UID=$(id -u $USERNAME)
export PASSWORD_FILE="/data/pw"
export SUPERUSER_FILE="/data/superuser"
export DAEMON_URL="https://raw.githubusercontent.com/portalplatform/apps/master/pvoip/latest.tar.gz"

# Packages
export DEBIAN_FRONTEND=noninteractive
add-apt-repository -y ppa:mumble/release
apt-get update
apt-get install -y pwgen mumble-server


# Generate password, if necessary.
[ -e $PASSWORD_FILE ] || pwgen 10 1 > $PASSWORD_FILE
export PASSWORD=$(cat $PASSWORD_FILE)

# Generate superuser password, if necessary.
[ -e $SUPERUSER_FILE ] || pwgen 10 1 > $SUPERUSER_FILE
export SUPERUSER=$(cat $SUPERUSER_FILE)

# Create murmurd config.
cat <<CONFIG >/etc/mumble-server.ini
database=/data/mumble-server.sqlite
dbus=system
ice="tcp -h 127.0.0.1 -p 6502"
icesecretwrite=
logfile=/var/log/mumble-server/mumble-server.log
pidfile=/var/run/mumble-server/mumble-server.pid
welcometext="<br>VoIP Server<br>powered by <b>Murmur</b>.<br>Enjoy your stay!<br>"
port=64738
serverpassword=$PASSWORD
bandwidth=144000
users=100
uname=mumble-server
[Ice]
Ice.Warn.UnknownProperties=1
Ice.MessageSizeMax=65536
CONFIG

# Restart service
service mumble-server restart

# Set the superuser password.
murmurd -ini /etc/mumble-server.ini -supw "$SUPERUSER"

# The pvoip web interface (listens on port 81)
cd /opt/ && wget $DAEMON_URL && tar xvfz $(basename $DAEMON_URL)

# Create the Upstart job.
cat <<UPSTART > /etc/init/pvoip.conf
description "pvoip"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
script
    cd /opt
    export PORTAL_USERNAME="$USERNAME"
    export PORTAL_PASSWORD="$PASSWORD"
    export PORTAL_SUPERUSER="$SUPERUSER"
    export PORTAL_DOMAIN="$DOMAIN"
    export PORTAL_PREFIX="$PRIVATE_URI"
    ./pvoip
end script
UPSTART

start pvoip

# Sync files in memory to disk.
sync
