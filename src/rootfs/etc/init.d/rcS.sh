#!/bin/busybox ash

# /etc/init.d/rcS - u/bin/sed by /etc/inittab to start the system.

printf "\n\n[`date`]\nRunning init script...\n";

# Configure sysctl, Read sysctl.conf
/sbin/sysctl -p /etc/sysctl.conf;

# mount and monitor hard drive array
/usr/local/sbin/mdisk init;

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

# if we have the tc user, let's add it do the docker group
/bin/grep -q '^tc:' /etc/passwd && /usr/sbin/addgroup tc docker;

/bin/chmod 775 /tmp /volume1;
/bin/chown :staff /tmp /volume1;

# hide directory
/bin/chmod 700 /var/tiny/etc;

#maybe the links will be up by now - trouble is, on some setups, they may never happen, so we can't just wait until they are
/bin/sleep 3;

# set the hostname
echo tiny$(/sbin/ip addr | /bin/grep -A 2 'eth[0-9]*:' | /bin/grep inet | /usr/bin/awk -F'[.]|/' '{print "-"$4}' | /usr/bin/awk '{printf $_}') | \
    /usr/bin/tee /var/tiny/etc/hostname;
HOSTNAME=`cat /var/tiny/etc/hostname`;
/usr/bin/sethostname $HOSTNAME;

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

/usr/bin/clear
