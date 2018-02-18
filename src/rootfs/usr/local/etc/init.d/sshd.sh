#!/bin/sh

[ $(id -u) = 0 ] || { echo 'must be root' >&2; exit 1; }

# import settings from env
[ -s /etc/env ] && . /etc/env;

: ${SSHD_PORT:=22};

# Configure sshd and acknowledge for persistence in /opt/tiny of the keys/config
# Move /usr/local/etc/ssh to /opt/tiny/ssh if it doesn't exist
# if it exists, remove the ramdisk's ssh config, so that the hard drive's is properly linked
[ ! -d /opt/tiny/ssh ] && \
    mv /usr/local/etc/ssh /opt/tiny/ || \
        rm -fr /usr/local/etc/ssh;

ln -s /opt/tiny/ssh /usr/local/etc/ssh;

[ -f /usr/local/etc/ssh/ssh_config ] || \
    cp /usr/local/etc/ssh/ssh_config.orig \
        /usr/local/etc/ssh/ssh_config;

[ -f /usr/local/etc/ssh/sshd_config ] || \
    cp /usr/local/etc/ssh/sshd_config.orig \
        /usr/local/etc/ssh/sshd_config;

# speed up login
grep -q "^UseDNS no" /usr/local/etc/ssh/sshd_config || \
    echo "UseDNS no" >> /usr/local/etc/ssh/sshd_config;

# ssh dameon
/usr/local/etc/init.d/openssh start;

# open sshd port
iptables -I INPUT -p tcp --dport $SSHD_PORT -j ACCEPT;
# iptables -I OUTPUT -p tcp --sport $SSHD_PORT -j ACCEPT
