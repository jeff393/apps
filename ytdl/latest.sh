#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

# Packages
apt-get update
apt-get install -y lighttpd libfile-slurp-perl


# youtube-dl
curl --silent http://youtube-dl.org/latest/youtube-dl >/usr/local/bin/youtube-dl
chmod 755 /usr/local/bin/youtube-dl

# lighttpd
curl --silent https://raw.githubusercontent.com/portalplatform/apps/master/ytdl/magic >/var/www/magic
perl -pi -e 's/= 80/= 81/' /etc/lighttpd/lighttpd.conf
cat <<LIGHTTPD >/etc/lighttpd/conf-enabled/ytdl.conf
server.modules += ( "mod_cgi" )
cgi.assign      = ( "/magic" => "/usr/bin/perl" )
alias.url       = ( "$PRIVATE_URI" => "/var/www/" )
url.redirect    = ( "^$PRIVATE_URI$" => "${PRIVATE_URI}magic", )
LIGHTTPD

service lighttpd restart
