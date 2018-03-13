#!/bin/sh

[ $(/usr/bin/id -u) = 0 ] || { echo 'must be root' >&2; exit 1; }

# import settings from env
[ -s /etc/env ] && . /etc/env;

: ${SSHD_PORT:=22};

/usr/sbin/sshd # TODO

# open sshd port
/sbin/iptables -I INPUT -p tcp --dport $SSHD_PORT -j ACCEPT;
# /sbin/iptables -I OUTPUT -p tcp --sport $SSHD_PORT -j ACCEPT
