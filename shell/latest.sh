#!/bin/bash -x

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

# Settings
export GOTTY_CMD="bash"
export GOTTY_SESSION="shell"

#
# Gotty
#
wget -O /usr/local/bin/gotty https://raw.githubusercontent.com/portalplatform/apps/master/gotty/gotty
chmod 755 /usr/local/bin/gotty
setcap cap_net_bind_service=+ep /usr/local/bin/gotty


#
# Bash
#
cat <<BASH_UPSTART >/etc/init/bash.conf
description "bash"
start on runlevel [2345]
stop on runlevel [!2345]
expect daemon
respawn
script
    su -l $USERNAME -c "byobu-tmux new-session -d -s $GOTTY_SESSION '$GOTTY_CMD'"
end script
BASH_UPSTART

start bash

#
# Gotty
#
wget -O /usr/local/bin/gotty https://raw.githubusercontent.com/portalplatform/apps/master/gotty/gotty
chmod 755 /usr/local/bin/gotty
setcap cap_net_bind_service=+ep /usr/local/bin/gotty

cat <<GOTTY_UPSTART >/etc/init/gotty.conf
description "gotty"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
script
    su -l $USERNAME -c "/usr/local/bin/gotty --title-format 'Shell - ({{ .Hostname }})' --root-url $PRIVATE_URI_NOSLASH --port 81 --permit-write byobu-tmux new-session -A -s $GOTTY_SESSION '$GOTTY_CMD'"
end script
GOTTY_UPSTART

start gotty

sleep 2
