#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

# Packages
apt-get update
apt-get install -y lighttpd libfile-slurp-perl libwww-perl

# lighttpd
curl --silent https://raw.githubusercontent.com/portalplatform/apps/master/tldr/updates >/var/www/updates
echo "$PRIVATE_URI" >/var/www/prefix.config

# Favicon
curl --silent https://raw.githubusercontent.com/portalplatform/apps/master/tldr/latest.png >/var/www/favicon.png

# Bootstrap
curl --silent https://maxcdn.bootstrapcdn.com/bootstrap/3.3.5/css/bootstrap.min.css >/var/www/bootstrap.min.css

# Private port.
perl -pi -e 's/= 80/= 81/' /etc/lighttpd/lighttpd.conf

# CGI
cat <<LIGHTTPD >/etc/lighttpd/conf-enabled/tldr.conf
server.modules += ( "mod_cgi" )
cgi.assign      = ( "/updates" => "/usr/bin/perl" )
alias.url       = ( "$PRIVATE_URI" => "/var/www/" )
url.redirect    = ( "^$PRIVATE_URI$" => "${PRIVATE_URI}updates", )
LIGHTTPD

service lighttpd restart
