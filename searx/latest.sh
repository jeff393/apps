#!/bin/bash -x

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

# Packages
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
    nginx \
    git \
    build-essential \
    python-dev \
    python-virtualenv \
    python-pybabel \
    zlib1g-dev \
    libxml2-dev \
    libyaml-dev \
    libxslt1-dev \
    libffi-dev \
    libssl-dev \
    openssl \


# Nginx
cat <<NGINX >/etc/nginx/sites-available/default
server {
    listen 81;
    access_log /dev/null;
    error_log /dev/null;
    return 302 https://${DOMAIN}${PUBLIC_URI};
}

server {
    listen 80;
    server_name $DOMAIN;
    access_log /dev/null;
    error_log /dev/null;

    location $PUBLIC_URI_NOSLASH {
        proxy_pass http://127.0.0.1:8888;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Scheme \$scheme;
        proxy_set_header X-Script-Name $PUBLIC_URI_NOSLASH;
        proxy_redirect https://127.0.0.1:8888/ https://$DOMAIN/;
    }
}
NGINX
service nginx restart


# Download
cd /opt/
git clone https://github.com/asciimoo/searx


# Build
cd searx/
perl -pi -e "s#ultrasecretkey#$(openssl rand -hex 16)#" searx/settings.yml
perl -pi -e "s#base_url : False#base_url : \"https://${DOMAIN}${PUBLIC_URI_NOSLASH}\"#" searx/settings.yml


# Permissions
chown -R $USERNAME:$USERNAME /data/ /opt/


# Setup
cat <<SETUP >/tmp/setup
#!/bin/bash
cd /opt/searx/
virtualenv searx-ve
. ./searx-ve/bin/activate
pip install -r requirements.txt
python setup.py install
SETUP

chmod 755 /tmp/setup

su -s /bin/bash -l $USERNAME -c /tmp/setup

cat <<RUN >/tmp/run
#!/bin/bash
cd /opt/searx/
virtualenv searx-ve
. ./searx-ve/bin/activate
python searx/webapp.py
RUN
chmod 755 /tmp/run

# Service
cat <<UPSTART >/etc/init/searx.conf
description "searx"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
script
    su -s /bin/bash -l $USERNAME -c /tmp/run
end script
UPSTART

start searx

