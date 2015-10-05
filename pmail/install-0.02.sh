#!/bin/bash

# Bash settings
set -e
set -u

# Sticky bit so Maildirs can be created, etc.
chmod 1777 /data/

export USERNAME=$(curl --silent http://169.254.169.254/metadata/v1/user/username)
export DOMAIN=$(curl --silent http://169.254.169.254/metadata/v1/domains/public/0/name)
export URI=$(curl --silent http://169.254.169.254/metadata/v1/paths/private/0/uri)

export DAEMON_URL="https://raw.githubusercontent.com/portalplatform/apps/master/pmail/latest.tar.gz"

export USER_UID=$(id -u $USERNAME)
export HOSTNAME=$(hostname)
export PASSWORD_FILE="/data/pw"

export SSL_CERT="/data/ssl.crt"
export SSL_KEY="/data/ssl.key"

#
# Packages
#
export DEBIAN_FRONTEND=noninteractive
apt-get update
# apt-get upgrade -y
apt-get install -y postfix dovecot-imapd pwgen


#
# Generate password, if necessary.
#
[ -e $PASSWORD_FILE ] || pwgen 10 1 > $PASSWORD_FILE
export PASSWORD=$(cat $PASSWORD_FILE)


#
# Generate self-signed cert, if necessary.
#
[ -e $SSL_CERT ] || openssl req \
    -new \
    -newkey rsa:2048 \
    -days 1000 \
    -nodes \
    -x509 \
    -subj "/C=US/ST=Personal/L=Cloud/O=IT/CN=$DOMAIN" \
    -keyout $SSL_KEY \
    -out $SSL_CERT

#
# Dovecot
#

# LEGACYFIX
[ -d /data/$USERNAME ] && mv /data/$USERNAME /data/$DOMAIN

echo -n "" > /etc/dovecot/users
echo "$DOMAIN:$(doveadm pw -p $PASSWORD):$USER_UID:$USER_UID" >> /etc/dovecot/users

cat <<AUTH >/etc/dovecot/conf.d/10-auth.conf
ssl = required
auth_mechanisms = plain
disable_plaintext_auth = yes
!include auth-passwdfile.conf.ext
AUTH

cat <<MAILDIR >/etc/dovecot/conf.d/10-mail.conf
mail_location = maildir:/data/%u/
namespace inbox {
    inbox = yes
}
MAILDIR

cat <<LOCAL >/etc/dovecot/local.conf
service auth {
    unix_listener /var/spool/postfix/private/auth {
        mode = 0660
        user = postfix
        group = postfix
    }
}
LOCAL

cat <<SSLCONF >/etc/dovecot/conf.d/10-ssl.conf
ssl_cert = <$SSL_CERT
ssl_key = <$SSL_KEY
SSLCONF

service dovecot restart


#
# Postfix
#

cat <<VIRTUAL >/etc/postfix/virtual
VIRTUAL
postmap /etc/postfix/virtual

cat <<VMAILBOX >/etc/postfix/vmailbox
@$DOMAIN $DOMAIN/
VMAILBOX
postmap /etc/postfix/vmailbox


cat <<MAINCF >/etc/postfix/main.cf
smtpd_banner = \$myhostname ESMTP \$mail_name
biff = no
append_dot_mydomain = no
readme_directory = no
smtpd_tls_cert_file=/data/ssl.crt
smtpd_tls_key_file=/data/ssl.key
smtpd_use_tls=yes
smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache
smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
myhostname = $HOSTNAME
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
mydestination = $HOSTNAME, localhost.localdomain, localhost
relayhost = 
mynetworks = 127.0.0.0/8 172.16.0.0/12
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all
inet_protocols = all

#home_mailbox = Maildir/
virtual_mailbox_domains = $DOMAIN
virtual_mailbox_base = /data
virtual_mailbox_maps = hash:/etc/postfix/vmailbox
virtual_minimum_uid = 100
virtual_uid_maps = static:$USER_UID
virtual_gid_maps = static:$USER_UID
virtual_alias_maps = hash:/etc/postfix/virtual

# SASL
smtpd_sasl_auth_enable = yes
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_authenticated_header = yes
smtpd_sasl_security_options = noanonymous
smtpd_sasl_local_domain = \$myhostname
broken_sasl_auth_clients = yes
smtpd_recipient_restrictions =
	reject_unknown_sender_domain,
	reject_unknown_recipient_domain,
	reject_unauth_pipelining,
	permit_mynetworks,
	permit_sasl_authenticated,
	reject_unauth_destination
smtpd_sender_restrictions = reject_unknown_sender_domain

MAINCF


cat <<MASTER >>/etc/postfix/master.cf
submission inet n - n - - smtpd
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=private/auth
  -o smtpd_sasl_security_options=noanonymous
  -o smtpd_sasl_local_domain=\$myhostname
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_recipient_restrictions=reject_non_fqdn_recipient,reject_unknown_recipient_domain,permit_sasl_authenticated,reject

MASTER

service postfix restart



#
# The pmail web interface (listens on port 81)
#

cd /opt/ && wget $DAEMON_URL && tar xvfz $(basename $DAEMON_URL)

# Create the Upstart job.
cat <<UPSTART > /etc/init/pmail.conf
description "pmail"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
script
    cd /opt
    export MAILSERVER_USERNAME="$USERNAME"
    export MAILSERVER_PASSWORD="$PASSWORD"
    export MAILSERVER_DOMAIN="$DOMAIN"
    export MAILSERVER_PREFIX="$URI"
    ./pmail
end script
UPSTART

start pmail


#
# Sync files in memory to disk.
#
sync
