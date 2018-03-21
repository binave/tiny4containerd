#!/bin/busybox ash

printf "\n\n[`date`]\nRunning init script...\n";

[ -d /root ]    || mkdir -m 0750 /root;
[ -d /sys ]     || mkdir /sys;
[ -d /proc ]    || mkdir /proc;
[ -d /tmp ]     || mkdir -m 1777 /tmp;

# Mount /proc.
/bin/mount -t proc proc /proc;
/bin/mount -t tmpfs -o size=90% tmpfs /mnt;

# Starting udev daemon...
/sbin/udevd --daemon 2>/dev/null;

# Udevadm requesting events from the Kernel...
/sbin/udevadm trigger --action=add >/dev/null 2>&1 &

# Udevadm waiting for the event queue to finish...
/sbin/udevadm settle --timeout=120;
/sbin/udevadm control --reload-rules &

# Remount rootfs rw.
/bin/mount -o remount,rw /;

# Mount system devices from /etc/fstab.
/bin/mount -a;

# set globle file mode mask
umask 022;

# filter environment variable
{
    /bin/sed 's/[\|\;\& ]/\n/g' /proc/cmdline | /bin/grep '^[_A-Z]\+=';
    printf "export PERSISTENT_DATA=$PERSISTENT_DATA\n"
} > /etc/profile.d/boot_envar.sh;

# TODO
# tz

# Configure sysctl, Read sysctl.conf
/sbin/sysctl -p /etc/sysctl.conf;

# mount and monitor hard drive array
/usr/local/sbin/mdisk init;

# Laptop options enabled (AC, Battery and PCMCIA).
/sbin/modprobe ac && /sbin/modprobe battery 2>/dev/null;
/sbin/modprobe yenta_socket >/dev/null 2>&1 || /sbin/modprobe i82365 >/dev/null 2>&1;

# for find/crond/log
/bin/mkdir -p \
    /var/spool/cron/crontabs \
    $PERSISTENT_DATA/tiny/etc/init.d \
    $PERSISTENT_DATA/log/tiny/${Ymd:0:6};

# Starting system log daemon: syslogd...
/sbin/syslogd;
# Starting kernel log daemon: klogd...
/sbin/klogd;

# mdiskd
/usr/local/sbin/mdisk monitor;

# init environment from disk
/usr/local/sbin/envset;

# change password
/usr/local/sbin/pwset;

echo "------ firewall --------------";
# http://wiki.tinycorelinux.net/wiki:firewall tce-load -wi iptables; -> /usr/local/sbin/basic-firewall
/bin/sh /usr/local/etc/init.d/firewall init;

# set static ip or start dhcp
/usr/local/sbin/ifset;
# /bin/hostname -F /etc/hostname;

# mount cgroups hierarchy. https://github.com/tianon/cgroupfs-mount
/bin/sh /usr/local/etc/init.d/cgroupfs mount;

/bin/sleep 2;

# init
/usr/bin/find $PERSISTENT_DATA/tiny/etc/init.d -type f -perm /u+x -name "S*.sh" -exec /bin/sh -c {} \;

# sync the clock
/usr/sbin/ntpd -d -n -p pool.ntp.org >> $PERSISTENT_DATA/log/tiny/${Ymd:0:6}/ntpd_$Ymd.log 2>&1 &

# start cron
/usr/sbin/crond -f -d "${CROND_LOGLEVEL:-8}" >> $PERSISTENT_DATA/log/tiny/${Ymd:0:6}/crond_$Ymd.log 2>&1 &

/bin/chmod 775 /tmp $PERSISTENT_DATA;
# /bin/chown :staff /tmp $PERSISTENT_DATA;
/bin/chgrp staff /tmp $PERSISTENT_DATA;

# hide directory
/bin/chmod 700 $PERSISTENT_DATA/tiny/etc;

#maybe the links will be up by now - trouble is, on some setups, they may never happen, so we can't just wait until they are
/bin/sleep 3;

# set the hostname
echo tc$(/sbin/ifconfig | /bin/grep -A 1 'eth[0-9]' | /bin/grep addr: | /usr/bin/awk '{print $2}' | /usr/bin/awk -F\. '{printf "-"$4}') | \
    /usr/bin/tee $PERSISTENT_DATA/tiny/etc/hostname;
HOSTNAME=`cat $PERSISTENT_DATA/tiny/etc/hostname` && /bin/hostname $HOSTNAME;

# ssh dameon start
/bin/sh /usr/local/etc/init.d/sshd;

# Launch /sbin/acpid (shutdown)
/sbin/acpid;

echo "------ ifconfig --------------";
# show ip info
/sbin/ifconfig | /bin/grep -A 2 '^[a-z]' | /bin/sed 's/Link .*//;s/--//g;s/UP.*//g;s/\s\s/ /g' | /bin/grep -v '^$';

echo "----- containerd -------------";

# Launch Containerd
/usr/local/sbin/containerd start;

# Allow rc.local customisation
/bin/touch $PERSISTENT_DATA/tiny/etc/rc.local;
if [ -x $PERSISTENT_DATA/tiny/etc/rc.local ]; then
    echo "------ rc.local --------------";
    . $PERSISTENT_DATA/tiny/etc/rc.local
fi

printf "Finished init script...\n";

# /usr/bin/clear
