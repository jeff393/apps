#!/bin/bash -x

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

# Settings
export GOTTY_CMD="weechat --dir /data/"
export GOTTY_SESSION="weechat"

# Packages
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y weechat

# Gotty
wget -O /usr/local/bin/gotty https://raw.githubusercontent.com/portalplatform/apps/master/gotty/gotty
chmod 755 /usr/local/bin/gotty
setcap cap_net_bind_service=+ep /usr/local/bin/gotty

cat <<UPSTART >/etc/init/weechat.conf
description "weechat"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
script
    su -l $USERNAME -c "/usr/local/bin/gotty --title-format 'WeeChat - ({{ .Hostname }})' --root-url $PRIVATE_URI_NOSLASH --port 81 --permit-write tmux new-session -A -s $GOTTY_SESSION '$GOTTY_CMD'"
end script
UPSTART

start weechat

sleep 2
