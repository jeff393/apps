#!/bin/bash -x

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

# Settings
export GOTTY_TITLE="Crawl"
export GOTTY_SESSION="crawl"
export GOTTY_CMD="/usr/games/crawl -dir /data"

# Repos
echo 'deb https://crawl.develz.org/debian crawl 0.16' >/etc/apt/sources.list.d/crawl.list
curl --silent https://crawl.develz.org/debian/pubkey | apt-key add -

# Packages
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y crawl

# Gotty
wget -O /usr/local/bin/gotty https://raw.githubusercontent.com/portalplatform/apps/master/gotty/gotty
chmod 755 /usr/local/bin/gotty
setcap cap_net_bind_service=+ep /usr/local/bin/gotty

cat <<UPSTART >/etc/init/crawl.conf
description "crawl"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
script
    su -l $USERNAME -c "/usr/local/bin/gotty --title-format '$GOTTY_TITLE - ({{ .Hostname }})' --root-url $PRIVATE_URI_NOSLASH --port 81 --permit-write tmux new-session -A -s $GOTTY_SESSION '$GOTTY_CMD'"
end script
UPSTART

start crawl

sleep 2
