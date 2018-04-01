#!/bin/busybox ash

# globle env
: ${PERSISTENT_PATH:='/var'};
export PERSISTENT_PATH Ymd=`/bin/date +%Y%m%d` \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin;

case $1 in
    S)
        [ -f /proc/cmdline ] || mount /proc;

        # Remount rootfs rw.
        mount -o remount,rw /;

        # Mount system devices from /etc/fstab.
        mount -a;

        mkdir -p /run;

        # This log is started before the persistence partition is mounted
        sh /etc/init.d/rcS 2>&1 | tee -a /run/rcS-$$.log;

        sleep 1.5;

        mkdir -p $PERSISTENT_PATH/log/tiny/${Ymd:0:6};

        cat /run/rcS-$$.log >> $PERSISTENT_PATH/log/tiny/${Ymd:0:6}/boot_$Ymd.log && \
            rm -f /run/rcS-$$.log
    ;;
    K)
        mkdir -p $PERSISTENT_PATH/log/tiny/${Ymd:0:6};

        sh /etc/init.d/rcK 2>&1 | \
            tee -a $PERSISTENT_PATH/log/tiny/${Ymd:0:6}/shut_$Ymd.log;

        # Unload disk
        mdisk destroy;

        sync; sleep 1; sync; sleep 1;

        umount -arf 2>/dev/null
    ;;
    *) :;;
esac

unset Ymd
