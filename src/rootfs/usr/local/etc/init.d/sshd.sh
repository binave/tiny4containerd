#!/bin/sh

[ $(/usr/bin/id -u) = 0 ] || { echo 'must be root' >&2; exit 1; }

# import settings from profile
for i in /etc/profile.d/*.sh; do [ -r $i ] && . $i; done; unset i;

: ${SSHD_PORT:=22};

# TODO
/usr/sbin/sshd &

# open sshd port
/sbin/iptables -I INPUT -p tcp --dport $SSHD_PORT -j ACCEPT;
# /sbin/iptables -I OUTPUT -p tcp --sport $SSHD_PORT -j ACCEPT
