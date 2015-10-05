#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

export DAEMON_URL="https://raw.githubusercontent.com/portalplatform/apps/master/pmail/latest.tar.gz"
export USER_UID=$(id -u $USERNAME)
export HOSTNAME=$(hostname)
export PASSWORD_FILE="/data/pw"
export SSL_CERT="/data/ssl.crt"
export SSL_KEY="/data/ssl.key"

# Packages
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
    dovecot-imapd \
    dovecot-sieve \
    dovecot-antispam \
    postfix \
    postfix-pcre \
    dspam \
    pwgen


# Generate password, if necessary.
[ -e $PASSWORD_FILE ] || pwgen 10 1 > $PASSWORD_FILE
export PASSWORD=$(cat $PASSWORD_FILE)

# Generate self-signed cert, if necessary.
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
auth_mechanisms = plain login
disable_plaintext_auth = yes
!include auth-passwdfile.conf.ext
AUTH

cat <<'MAILDIR' >/etc/dovecot/conf.d/10-mail.conf
mail_location = maildir:/data/%u/
namespace inbox {
    inbox = yes

    mailbox Drafts {
        auto = subscribe
        special_use = \Drafts
    }

    mailbox Sent {
        auto = subscribe
        special_use = \Sent
    }

    mailbox Junk {
        auto = subscribe
        special_use = \Junk
    }

    mailbox Trash {
        auto = subscribe
        special_use = \Trash
    }

    mailbox Archive {
        auto = subscribe
        special_use = \Archive
    }
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
smtpd_banner = $DOMAIN ESMTP \$mail_name
biff = no
readme_directory = no
message_size_limit = 100000000
append_dot_mydomain = no

smtpd_use_tls = yes
smtpd_tls_cert_file = /data/ssl.crt
smtpd_tls_key_file = /data/ssl.key
smtpd_tls_auth_only = yes
smtpd_tls_received_header = yes
smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache

smtp_tls_security_level = may
smtp_tls_loglevel = 2
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache

myhostname = $DOMAIN
myorigin = $DOMAIN
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
mydestination = localhost.localdomain, localhost
relayhost = 
mynetworks = 127.0.0.0/8 172.16.0.0/12
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all
inet_protocols = all

smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination

virtual_mailbox_limit = 0
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
	permit_mynetworks,
	permit_sasl_authenticated,
	reject_unknown_sender_domain,
	reject_unknown_recipient_domain,
	reject_unauth_pipelining,
	reject_unauth_destination
smtpd_sender_restrictions = reject_unknown_sender_domain

# Remove client IP and mailer headers.
smtp_header_checks = pcre:/etc/postfix/smtp_header_checks.pcre

MAINCF
cat <<'SMTP_HEADER_CHECKS' >/etc/postfix/smtp_header_checks.pcre
/^\s*(Received: from)[^\n]*(.*)/ REPLACE $1 [127.0.0.1] (localhost [127.0.0.1])$2
/^\s*User-Agent/        IGNORE
/^\s*X-Enigmail/        IGNORE
/^\s*X-Mailer/          IGNORE
/^\s*X-Originating-IP/  IGNORE
SMTP_HEADER_CHECKS


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


# The pmail web interface (listens on port 81)
cd /opt/ && wget $DAEMON_URL && tar xvfz $(basename $DAEMON_URL)

# Create the pmail service.
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
    export MAILSERVER_PREFIX="$PRIVATE_URI"
    ./pmail
end script
UPSTART

start pmail


# Sync files in memory to disk.
sync
