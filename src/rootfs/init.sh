#!/bin/sh

[ -d /root ]    || mkdir -m 0750 /root;
[ -d /sys ]     || mkdir /sys;
[ -d /proc ]    || mkdir /proc;
[ -d /tmp ]     || mkdir -m 1777 /tmp;

/bin/mount -t tmpfs -o size=90% tmpfs /mnt;

# Mounting devtmpfs filesystem on: /dev
/bin/mount -t devtmpfs devtmpfs /dev;

exec /sbin/init;
