#!/bin/busybox ash

_init() {
	# Starting udev daemon...
	/sbin/udevd --daemon 2>/dev/null;

	# Udevadm requesting events from the Kernel...
	/sbin/udevadm trigger;

	# Udevadm waiting for the event queue to finish...
	/sbin/udevadm settle --timeout=120;

    # set globle file mode mask
    umask 022;

    # # Starting system log daemon: syslogd...
    # syslogd -s $TODO;
    # # Starting kernel log daemon: klogd...
    # klogd;

    # Mount /proc.
    [ -f /proc/cmdline ] || /bin/mount /proc;

    # Remount rootfs rw.
    /bin/mount -o remount,rw /;

    # Mount system devices from /etc/fstab.
    /bin/mount -a;

    # filter environment
    /bin/sed 's/[\|\;\& ]/\n/g' /proc/cmdline | /bin/grep '^[_A-Z]\+=' > /etc/env;

    # TODO
    # tz

    # This log is started before the persistence partition is mounted
    /bin/sh /etc/init.d/rcS 2>&1 | /usr/bin/tee -a /var/log/rcS.log;

    /bin/sleep 1.5;

    /bin/cat /var/log/rcS.log >> /log/tiny/${Ymd:0:6}/boot_$Ymd.log && \
        /bin/rm -f /var/log/rcS.log
}

_destroy() {
    /bin/mkdir -p /log/tiny/${Ymd:0:6};

    /bin/sh /etc/init.d/rcK 2>&1 | /usr/bin/tee -a /log/tiny/${Ymd:0:6}/shut_$Ymd.log;

    # Unload disk
    /usr/local/sbin/mdisk destroy;

    /bin/umount -arf 2>/dev/null

}

# globle env
export Ymd=`/bin/date +%Y%m%d`;

case $1 in
    S) _init;;
    K) _destroy;;
    *) :;;
esac

unset Ymd

