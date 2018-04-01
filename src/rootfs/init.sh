#!/bin/sh
if mount -t tmpfs -o size=90% tmpfs /mnt; then
    # fix: tar: skipping unsafe symlink to '...' in archive
    export EXTRACT_UNSAFE_SYMLINKS=1;
    if tar -C / --exclude=mnt -cf - . | tar -C /mnt/ -xf -; then
        mkdir /mnt/mnt;
        exec /sbin/switch_root mnt /sbin/init
    fi
fi

# https://git.busybox.net/busybox/tree/examples/inittab
exec /sbin/init; # /etc/initta