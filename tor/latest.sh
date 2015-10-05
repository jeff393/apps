#!/bin/bash -x

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

# Tor settings.
export TOR_PORT="9001"
export TOR_NICKNAME=$(hostname)
export TOR_USER="debian-tor"

# Gotty settings
export GOTTY_CMD="arm"
export GOTTY_SESSION="arm"


#
# Packages
#
export DEBIAN_FRONTEND=noninteractive

cat <<TOR_REPO >/etc/apt/sources.list.d/torproject.list
deb http://deb.torproject.org/torproject.org trusty main
deb-src http://deb.torproject.org/torproject.org trusty main
TOR_REPO

gpg --keyserver keys.gnupg.net --recv 886DDD89
gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | sudo apt-key add -

apt-get update
apt-get install -y tor tor-arm deb.torproject.org-keyring

cat <<TOR >/etc/tor/torrc
ORPort $TOR_PORT
ExitPolicy reject *:*

RelayBandwidthRate 128 KB
RelayBandwidthBurst 256 KB

Nickname $TOR_NICKNAME

AccountingStart month 1 00:00
AccountingMax 128 GB

DisableDebuggerAttachment 0
TOR
service tor restart

#
# gotty
#

wget -O /usr/local/bin/gotty https://raw.githubusercontent.com/portalplatform/apps/master/gotty/gotty
chmod 755 /usr/local/bin/gotty
setcap cap_net_bind_service=+ep /usr/local/bin/gotty

cat <<UPSTART >/etc/init/gotty.conf
description "gotty"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
script
    su -s /bin/sh -l $TOR_USER -c "/usr/local/bin/gotty --title-format '{{ .Command }} ({{ .Hostname }})' --root-url $PRIVATE_URI_NOSLASH --port 81 --permit-write byobu-tmux new-session -A -s $GOTTY_SESSION '$GOTTY_CMD'"
end script
UPSTART

start gotty

