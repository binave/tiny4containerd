#!/bin/sh

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin;

[ $(id -u) = 0 ] || { echo 'must be root' >&2; exit 1; }

# import settings from profile
envset; for i in /etc/profile.d/*.sh; do [ -r $i ] && . $i; done; unset i;

: ${SSHD_PORT:=22};

# TODO
sshd &

# open sshd port
iptables -I INPUT -p tcp --dport $SSHD_PORT -j ACCEPT;
# iptables -I OUTPUT -p tcp --sport $SSHD_PORT -j ACCEPT
