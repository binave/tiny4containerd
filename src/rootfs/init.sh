#!/bin/sh

[ -d /root ]    || mkdir -m 0750 /root;
[ -d /sys ]     || mkdir /sys;
[ -d /proc ]    || mkdir /proc;
[ -d /tmp ]     || mkdir -m 1777 /tmp;

/bin/mount -t tmpfs -o size=90% tmpfs /mnt;

# https://git.busybox.net/busybox/tree/examples/inittab
exec /sbin/init; # /etc/initta
