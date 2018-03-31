#!/bin/busybox ash

# globle env
: ${PERSISTENT_PATH:='/opt'};
export PERSISTENT_PATH Ymd=`/bin/date +%Y%m%d`;

case $1 in
    S)
        [ -f /proc/cmdline ] || /bin/mount /proc;

        # Remount rootfs rw.
        /bin/mount -o remount,rw /;

        # Mount system devices from /etc/fstab.
        /bin/mount -a;

        # This log is started before the persistence partition is mounted
        /bin/sh /etc/init.d/rcS 2>&1 | \
            /usr/bin/tee -a /run/rcS-$$.log;

        /bin/sleep 1.5;

        /bin/mkdir -p $PERSISTENT_PATH/log/tiny/${Ymd:0:6};

        /bin/cat /run/rcS-$$.log >> $PERSISTENT_PATH/log/tiny/${Ymd:0:6}/boot_$Ymd.log && \
            /bin/rm -f /run/rcS-$$.log
    ;;
    K)
        /bin/mkdir -p $PERSISTENT_PATH/log/tiny/${Ymd:0:6};

        /bin/sh /etc/init.d/rcK 2>&1 | \
            /usr/bin/tee -a $PERSISTENT_PATH/log/tiny/${Ymd:0:6}/shut_$Ymd.log;

        # Unload disk
        /usr/local/sbin/mdisk destroy;

        sync; sleep 1; sync; sleep 1;

        /bin/umount -arf 2>/dev/null
    ;;
    *) :;;
esac

unset Ymd
