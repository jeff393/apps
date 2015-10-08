#!/bin/bash

#
# Simple bash script for doing common Portal stuff.
#
# TODO: create a bunch of separate functions that do lazy lookups, etc.
#
# 1. Bash settings (errexit, nounset, pipefail).
# 2. Set commonly used variables.
#       $HOSTNAME              | "mail-server"
#       $DOMAIN                | "example.com"
#       $GATEWAY               | "172.17.123.1"
#       $PRIVATE_URI           | "/cloud/a/inst_abc123/"
#       $PRIVATE_URI_NOSLASH   | "/cloud/a/inst_abc123"
#       $PUBLIC_URI            | "/blog/"
#       $PUBLIC_URI_NOSLASH    | "/blog"
#       $PUBLIC_URI_WITHSLASH  | "/blog/"
#
# 2. Enable sticky bit on /data/ and /opt/.
# 3. Enable 2G swap.
# 4. Disable ipv6 (not supported yet).

function portal() {
    # Bash settings
    set -o errexit
    set -o nounset
    set -o pipefail

    export CURL="curl --silent http://169.254.169.254/metadata/v1/"

    # Username
    export USERNAME="$(${CURL}user/username)"

    # Domain
    export DOMAIN="$(${CURL}domains/public/0/name)"

    # Gateway
    export GATEWAY="$(${CURL}interfaces/private/0/ipv4/gateway)"

    # Public Port
    export PUBLIC_PORT="$(${CURL}ports/0/port)"

    # Private URI (port 81 traffic)
    export PRIVATE_URI="$(${CURL}paths/private/0/uri)"

    # Private URI without an ending slash.
    PRIVATE_URI_NOSLASH="$PRIVATE_URI"
    if [ "/" == "${PRIVATE_URI: -1}" ] ; then
        PRIVATE_URI_NOSLASH="${PRIVATE_URI:0:-1}"
    fi
    export PRIVATE_URI_NOSLASH

    # Public URI (port 80 traffic)
    export PUBLIC_URI="$(${CURL}paths/public/0/uri)"

    # Public URI without an ending slash.
    PUBLIC_URI_NOSLASH="$PUBLIC_URI"
    if [ ! -z "$PUBLIC_URI" ] && [ "/" == "${PUBLIC_URI: -1}" ] ; then
        PUBLIC_URI_NOSLASH="${PUBLIC_URI:0:-1}"
    fi
    export PUBLIC_URI_NOSLASH

    # Public URI with an ending slash.
    PUBLIC_URI_WITHSLASH="$PUBLIC_URI"
    if [ ! -z "$PUBLIC_URI" ] && [ "/" != "${PUBLIC_URI: -1}" ] ; then
        PUBLIC_URI_WITHSLASH="$PUBLIC_URI/"
    fi
    export PUBLIC_URI_WITHSLASH

    # Set permissions.
    chmod 1777 /data/ /opt/

    # Enable swap space.
    if [ ! -e /swap ] ; then
        fallocate -l 2G /swap
        chmod 600 /swap
        mkswap /swap
        swapon /swap
        sysctl -w vm.swappiness=10
    fi

    # Disable ipv6.
    sysctl -q -w \
        net.ipv6.conf.lo.disable_ipv6=1 \
        net.ipv6.conf.default.disable_ipv6=1 \
        net.ipv6.conf.all.disable_ipv6=1 >/dev/null

    # Create a fresh apt archive.
    if [ -d /var/lib/apt/lists ] ; then
        rm -rf /var/lib/apt/lists/
        apt-get update
    fi
}

# Run the portal() function.
portal

