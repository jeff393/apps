#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

export DAEMON_URL="https://raw.githubusercontent.com/portalplatform/apps/master/pvpn/latest.tar.gz"

# OpenVPN settings
export OPENVPN_DIR="/etc/openvpn"
export OPENVPN_KEYSIZE="2048"
export OPENVPN_DAYS="3650"

# Packages
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y openvpn dnsmasq

# IP masquerading (NAT) using iptables.
/sbin/iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
/sbin/iptables -A FORWARD -s 10.8.0.0/24 -j ACCEPT
/sbin/iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE

# Enable forwarding
sysctl -q -w net.ipv4.ip_forward=1 net.ipv6.conf.all.forwarding=0

cd /data/

if [ ! -f dh2048.pem ]; then
    openssl dhparam -out dh2048.pem $OPENVPN_KEYSIZE
    chmod 600 dh2048.pem
fi

if [ ! -f index.txt ]; then
    touch index.txt
    chmod 600 index.txt
fi

if [ ! -f serial ]; then
    echo 01 > serial
    chmod 600 serial
fi

if [ ! -f ca.key ]; then
    openssl genrsa -out ca.key $OPENVPN_KEYSIZE
    chmod 600 ca.key
fi

if [ ! -f ca.crt ]; then
    openssl req -nodes -batch -new -x509 -key ca.key -out ca.crt -days $OPENVPN_DAYS \
        -subj "/C=NL/ST=NULL/L=NULL/O=NULL/OU=NULL/CN=ca-certificate"
    chmod 600 ca.crt
fi

if [ ! -f server.csr ]; then
    cat <<OPENSSL >openssl.cnf
[ca]
default_ca = CA_default

[CA_default]
dir = /data
certs = \$dir
crl_dir = \$dir
database = \$dir/index.txt
new_certs_dir = \$dir

certificate = ca.crt
serial = \$dir/serial
crl = \$dir/crl.pem
private_key = ca.key
RANDFILE = \$dir/.rand

x509_extensions = server

default_days = 3650
default_crl_days = 30
default_md = sha256
preserve = no

policy = policy_anything

[policy_anything]
countryName = optional
stateOrProvinceName = optional
localityName = optional
organizationName = optional
organizationalUnitName = optional
commonName = supplied
name = optional
emailAddress = optional

[req]
distinguished_name = req_distinguished_name

[req_distinguished_name]
countryName = Country Name (2 letter code)
countryName_default = NL

stateOrProvinceName = State or Province Name (full name)
stateOrProvinceName_default = NULL

localityName = Locality Name (eg, city)
localityName_default = NULL

0.organizationName = Organization Name (eg, company)
0.organizationName_default = NULL

organizationalUnitName = Organizational Unit Name (eg, section)
organizationalUnitName_default = NULL

commonName = Common Name (eg, your name or your server\'s hostname)
commonName_default = $DOMAIN

[server]
basicConstraints=CA:FALSE
nsCertType = server
nsComment = "Server Certificate"
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer:always
extendedKeyUsage=serverAuth
keyUsage = digitalSignature, keyEncipherment
OPENSSL

    openssl genrsa -out server.key $OPENVPN_KEYSIZE
    chmod 600 server.key

    openssl req -batch -extensions server -new -key server.key -out server.csr -config openssl.cnf
    chmod 600 server.csr

    openssl ca -batch -extensions server -in server.csr -out server.crt -config openssl.cnf
    chmod 600 server.crt
fi

if [ ! -f client.key ]; then
    openssl genrsa -out client.key $OPENVPN_KEYSIZE
fi

if [ ! -f client.csr ] ; then
    openssl req \
        -new \
        -key client.key \
        -out client.csr \
        -subj "/C=NL/ST=NULL/L=NULL/O=NULL/OU=NULL/CN=openvpn_clients"
fi

[ -f client.crt ] || openssl x509 -CA ca.crt -CAkey ca.key -CAcreateserial -req -days 3650 -in client.csr -out client.crt

[ -f ta.key ] || openvpn --genkey --secret ta.key


cat <<SERVER >/etc/openvpn/server.conf
server 10.8.0.0 255.255.255.0
port 1194
proto udp
dev tun
ca /data/ca.crt
cert /data/server.crt
key /data/server.key
dh /data/dh2048.pem
duplicate-cn
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1"
push "dhcp-option DNS 10.8.0.1"
client-to-client
keepalive 10 240
cipher AES-256-CBC
auth SHA256
tls-auth /data/ta.key 0
tls-cipher TLS-DHE-RSA-WITH-AES-256-CBC-SHA:TLS-DHE-RSA-WITH-CAMELLIA-256-CBC-SHA:TLS-DHE-RSA-WITH-3DES-EDE-CBC-SHA:TLS-DHE-RSA-WITH-AES-128-CBC-SHA:TLS-DHE-RSA-WITH-SEED-CBC-SHA:TLS-DHE-RSA-WITH-CAMELLIA-128-CBC-SHA:TLS-DHE-RSA-WITH-DES-CBC-SHA
comp-lzo
user nobody
group nogroup
persist-key
persist-tun
persist-local-ip
persist-remote-ip
sndbuf 128000
rcvbuf 128000
txqueuelen 100
status-version 2
status /run/openvpn.status 10
log /dev/null
verb 3
SERVER

cat <<CLIENT >/data/client.conf
client
dev tun
proto udp
remote $DOMAIN $PUBLIC_PORT
keepalive 10 240
resolv-retry infinite
auth SHA256
nobind
persist-key
persist-tun
mute-replay-warnings
ns-cert-type server
comp-lzo
cipher AES-256-CBC
sndbuf 128000
rcvbuf 128000
key-direction 1
verb 3

<ca>
$(cat ca.crt)
</ca>

<cert>
$(cat client.crt)
</cert>

<key>
$(cat client.key)
</key>

<tls-auth>
$(cat ta.key)
</tls-auth>
CLIENT

service openvpn restart

#
# dnsmasq
#

cat <<DNSMASQ >/etc/dnsmasq.conf
# Never forward plain names (without a dot or domain part)
domain-needed
# Never forward addresses in the non-routed address spaces.
bogus-priv
# Only listen on necessary addresses.
listen-address=127.0.0.1,10.8.0.1
DNSMASQ

# NOTE: We need openvpn to have started for 10.8.0.1 to exist.
service dnsmasq restart




#
# The pvpn web interface (listens on port 81)
#
cd /opt/ && wget $DAEMON_URL && tar xvfz $(basename $DAEMON_URL)

# Create the Upstart job.
cat <<UPSTART > /etc/init/pvpn.conf
description "pvpn"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
script
    cd /opt
    export PORTAL_DOMAIN="$DOMAIN"
    export PORTAL_PREFIX="$PRIVATE_URI"
    export PORTAL_PORT="$PUBLIC_PORT"
    ./pvpn
end script
UPSTART

start pvpn

#
# Sync files in memory to disk.
#
sync
