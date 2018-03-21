#!/bin/busybox ash

printf "\n\n[`date`]\nRunning init script...\n";

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
    /var/tiny/etc/init.d \
    /log/tiny/${Ymd:0:6};

# mdiskd
/usr/local/sbin/mdisk monitor;

# create empty config
[ -s /var/tiny/etc/env ] || printf \
    "# set environment variable\n\n" > \
    /var/tiny/etc/env;

# filter env
/usr/bin/awk -F# '{print $1}' /var/tiny/etc/env 2>/dev/null | /bin/sed 's/[\|\;\&]/\n/g;s/export//g;s/^[ ]\+//g' | \
    /bin/grep '^[_A-Z]\+=' >> /etc/env;

echo >> /etc/env;

# init environment
. /etc/env;

# change password
/usr/local/sbin/pw load;

echo "------ firewall --------------";
# http://wiki.tinycorelinux.net/wiki:firewall tce-load -wi iptables; -> /usr/local/sbin/basic-firewall
/bin/sh /usr/local/etc/init.d/firewall init;

# set static ip or start dhcp
/usr/local/sbin/ifinit;

# mount cgroups hierarchy. https://github.com/tianon/cgroupfs-mount
/bin/sh /usr/local/etc/init.d/cgroupfs mount;

/bin/sleep 2;

# init
/usr/bin/find /var/tiny/etc/init.d -type f -perm /u+x -name "S*.sh" -exec /bin/sh -c {} \;

# sync the clock
/usr/sbin/ntpd -d -n -p pool.ntp.org >> /log/tiny/${Ymd:0:6}/ntpd_$Ymd.log 2>&1 &

# start cron
/usr/sbin/crond -f -d "${CROND_LOGLEVEL:-8}" >> /log/tiny/${Ymd:0:6}/crond_$Ymd.log 2>&1 &

/bin/chmod 775 /tmp /var;
# /bin/chown :staff /tmp /var;
/bin/chgrp staff /tmp /var;

# hide directory
/bin/chmod 700 /var/tiny/etc;

#maybe the links will be up by now - trouble is, on some setups, they may never happen, so we can't just wait until they are
/bin/sleep 3;

# set the hostname
echo tiny$(/sbin/ip addr | /bin/grep -A 2 'eth[0-9]*:' | /bin/grep inet | /usr/bin/awk -F'[.]|/' '{print "-"$4}' | /usr/bin/awk '{printf $_}') | \
    /usr/bin/tee /var/tiny/etc/hostname;
HOSTNAME=`cat /var/tiny/etc/hostname` && /usr/bin/sethostname $HOSTNAME;

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
/bin/touch /var/tiny/etc/rc.local;
if [ -x /var/tiny/etc/rc.local ]; then
    echo "------ rc.local --------------";
    . /var/tiny/etc/rc.local
fi

printf "Finished init script...\n";

# /usr/bin/clear
