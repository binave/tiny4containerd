#!/bin/sh

[ $(/usr/bin/id -u) = 0 ] || { echo 'must be root' >&2; exit 1; }

# import settings from env
[ -s /etc/env ] && . /etc/env;

: ${SSHD_PORT:=22};
DSS_KEY=/var/tiny/ssh/dropbear_dss_host_key;
RSA_KEY=/var/tiny/ssh/dropbear_rsa_host_key;

[ -f "$RSA_KEY" ] || /usr/local/bin/dropbearkey -t rsa -s 1024 -f $RSA_KEY;
[ -f "$DSS_KEY" ] || /usr/local/bin/dropbearkey -t dss -f $DSS_KEY;

/usr/local/sbin/dropbear -p $SSHD_PORT -d $DSS_KEY -r $RSA_KEY &

# open sshd port
/usr/local/sbin/iptables -I INPUT -p tcp --dport $SSHD_PORT -j ACCEPT;
# /usr/local/sbin/iptables -I OUTPUT -p tcp --sport $SSHD_PORT -j ACCEPT
