#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

export TRANSMISSION_DIR="/data/.transmission-daemon"
export TRANSMISSION_USER="debian-transmission"

# Set transmission directory (where config and torrent files are stored).
cat <<DEFAULT >/etc/default/transmission-daemon
ENABLE_DAEMON=1
CONFIG_DIR="$TRANSMISSION_DIR"
OPTIONS="--config-dir \$CONFIG_DIR"
DEFAULT

# Packages
export DEBIAN_FRONTEND="noninteractive"
apt-get update
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    transmission-daemon \
    pwgen \
    nginx \
    nginx-extras

stop transmission-daemon

cat <<CONFIG >$TRANSMISSION_DIR/settings.json
{
    "alt-speed-down": 50,
    "alt-speed-enabled": false,
    "alt-speed-time-begin": 540,
    "alt-speed-time-day": 127,
    "alt-speed-time-enabled": false,
    "alt-speed-time-end": 1020,
    "alt-speed-up": 50,
    "bind-address-ipv4": "0.0.0.0",
    "bind-address-ipv6": "::",
    "blocklist-enabled": false,
    "blocklist-url": "http://www.example.com/blocklist",
    "cache-size-mb": 4,
    "dht-enabled": true,
    "download-dir": "/data",
    "download-limit": 100,
    "download-limit-enabled": 0,
    "download-queue-enabled": true,
    "download-queue-size": 5,
    "encryption": 1,
    "idle-seeding-limit": 30,
    "idle-seeding-limit-enabled": false,
    "incomplete-dir": "/data",
    "incomplete-dir-enabled": false,
    "lpd-enabled": false,
    "max-peers-global": 200,
    "message-level": 2,
    "peer-congestion-algorithm": "",
    "peer-id-ttl-hours": 6,
    "peer-limit-global": 200,
    "peer-limit-per-torrent": 50,
    "peer-port": 51413,
    "peer-port-random-high": 65535,
    "peer-port-random-low": 49152,
    "peer-port-random-on-start": false,
    "peer-socket-tos": "default",
    "pex-enabled": true,
    "port-forwarding-enabled": false,
    "preallocation": 1,
    "prefetch-enabled": 1,
    "queue-stalled-enabled": true,
    "queue-stalled-minutes": 30,
    "ratio-limit": 2,
    "ratio-limit-enabled": false,
    "rename-partial-files": true,
    "rpc-enabled": true,
    "rpc-bind-address": "127.0.0.1",
    "rpc-url": "$PRIVATE_URI_NOSLASH/transmission/",
    "rpc-port": 9091,
    "rpc-authentication-required": false,
    "rpc-username": "transmission",
    "rpc-password": "transmission",
    "rpc-whitelist": "127.0.0.1",
    "rpc-whitelist-enabled": true,
    "scrape-paused-torrents-enabled": true,
    "script-torrent-done-enabled": false,
    "script-torrent-done-filename": "",
    "seed-queue-enabled": false,
    "seed-queue-size": 10,
    "speed-limit-down": 100,
    "speed-limit-down-enabled": false,
    "speed-limit-up": 100,
    "speed-limit-up-enabled": false,
    "start-added-torrents": true,
    "trash-original-torrent-files": false,
    "umask": 18,
    "upload-limit": 100,
    "upload-limit-enabled": 0,
    "upload-slots-per-torrent": 14,
    "utp-enabled": true
}
CONFIG


start transmission-daemon

# Nginx
cat <<HEADER >/data/.header.html
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
    <meta http-equiv="content-type" content="text/html; charset=utf-8"/>
    <style type="text/css">
        body, html {
            margin: 0;
            background: #fff;
            font-family: sans-serif;
            padding-bottom: 200px;
        }
        tr.e {
            background: #f4f4f4;
        }
        th, td {
            padding: 0.25em 0.5em;
        }
        th {
            text-align: left;
            font-weight: bold;
            background: #eee;
            border-bottom: 1px solid #aaa;
        }
        #list {
            border: 1px solid #aaa;
            width: 100%;
        }
        a {
            color: #a33;
        }
        a:hover {
            color: #e33;
        }
        h1 {
            display: none;
        }
        button {
            margin: 10px 2px;
            width: 200px;
            font-size: 16px;
        }
    </style>
    <title>Transmission</title>
</head>
<body>

    <iframe src="$PRIVATE_URI_NOSLASH/transmission/web/" frameBorder="0" width="100%" height="500"></iframe>
    <a href="./"><button>Refresh Directory</button></a>
    <h1>
HEADER

cat <<NGINX >/etc/nginx/sites-enabled/default
server {
    listen 81;
    server_name $DOMAIN;

    allow $GATEWAY;
    deny all;

    location $PRIVATE_URI_NOSLASH {
        alias /data;
        fancyindex on;
        fancyindex_exact_size off;
        fancyindex_localtime on;
        fancyindex_header "$PRIVATE_URI_NOSLASH/.header.html";
        fancyindex_ignore "lost\+found";
    }

    location $PRIVATE_URI_NOSLASH/transmission {
        proxy_set_header Host            "localhost";
        proxy_set_header X-Real-IP       \$remote_addr;
        proxy_set_header X-Forwarded-for \$remote_addr;
        proxy_pass http://127.0.0.1:9091;
    }
}

NGINX

service nginx restart



