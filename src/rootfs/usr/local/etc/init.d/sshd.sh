#!/bin/sh

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin;

[ $(id -u) = 0 ] || { echo 'must be root' >&2; exit 1; }

# import settings from profile
/usr/local/etc/init.d/envset;

for i in /etc/profile.d/*.sh; do [ -r $i ] && . $i; done; unset i;

: ${SSHD_PORT:=22};

# Configure sshd and acknowledge for persistence in /home/etc of the keys/config
# Move /usr/local/etc/ssh to /home/etc/ssh if it doesn't exist
# if it exists, remove the ramdisk's ssh config, so that the hard drive's is properly linked
[ ! -d /home/etc/ssh ] && \
    mv /usr/local/etc/ssh /home/etc/ || \
        rm -fr /usr/local/etc/ssh;

ln -s /home/etc/ssh /usr/local/etc/ssh;

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
