#!/bin/busybox ash

# globle env
export Ymd=`/bin/date +%Y%m%d`;

case $1 in
    S)
        /bin/mkdir -p /run;
        # This log is started before the persistence partition is mounted
        /bin/sh /etc/init.d/rcS 2>&1 | /usr/bin/tee -a /run/rcS.log;
        /bin/sleep 1.5;
        /bin/cat /run/rcS.log >> /var/log/tiny/${Ymd:0:6}/boot_$Ymd.log && \
            /bin/rm -f /run/rcS.log
    ;;
    K)
        /bin/mkdir -p /var/log/tiny/${Ymd:0:6};
        /bin/sh /etc/init.d/rcK 2>&1 | /usr/bin/tee -a /var/log/tiny/${Ymd:0:6}/shut_$Ymd.log;
        # Unload disk
        /usr/local/sbin/mdisk destroy;
        /bin/umount -arf 2>/dev/null
    ;;
    *) :;;
esac

unset Ymd
