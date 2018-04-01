#!/bin/busybox ash
_rebuild_fstab(){

    # Exit if script is already running
    [ -e /proc/partitions ] || return;

    if [ -e /var/run/rebuildfstab.pid ]; then
        if [ -e "/proc/$(/bin/cat /var/run/rebuildfstab.pid)" ]; then
            /bin/touch /var/run/rebuildfstab.rescan;
            return
        fi
        /bin/rm -fv /var/run/rebuildfstab.pid
    fi

    echo "$$" | /usr/bin/tee /var/run/rebuildfstab.pid;

    local ADDEDBY CDROMS CDROMSF DEVMAJOR DEVNAME DEVROOT FDISKL FSTYPE MOUNTPOINT OPTIONS TMP i;

    TMP="/tmp/fstab.$$.tmp";
    ADDEDBY="# Added by TC";
    DEVROOT="/dev";

    # Create a list of fdisk -l
    FDISKL=`/sbin/fdisk -l | /usr/bin/awk '$1 ~ /dev/{printf " %s ",$1}'`;

    # Read a list of CDROM/DVD Drives
    CDROMS="";
    CDROMSF=/etc/sysconfig/cdroms;

    [ -s "$CDROMSF" ] && CDROMS=`/bin/cat "$CDROMSF"`;

    /bin/grep -v "$ADDEDBY" /etc/fstab | /usr/bin/tee "$TMP";

    # Loop through block devices
    for i in `/usr/bin/find /sys/block/*/ -name dev`;
    do
        case "$i" in *loop*|*ram*) continue ;; esac

        DEVNAME=`echo "$i" | /usr/bin/tr [!] [/] | /usr/bin/awk 'BEGIN{FS="/"}{print $(NF-1)}'`;
        DEVMAJOR="$(/bin/cat $i | /usr/bin/cut -f1 -d:)";

        FSTYPE="";
        case "$CDROMS" in *"$DEVROOT/$DEVNAME"*) FSTYPE="auto" ;; esac

        # First try blkid approach for FSTYPE for non floppy drives.
        [ "$DEVMAJOR" != 2 -a -z "$FSTYPE" ] && FSTYPE="$(fstype "/dev/$DEVNAME")";
        [ "$FSTYPE" == "linux_raid_member" ] && continue;
        [ "$FSTYPE" == "LVM2_member" ] && continue;

        if [ -z "$FSTYPE" ]; then
            case "$DEVMAJOR" in
                2|98)
                    FSTYPE="auto"
                ;;
                3|8|11|22|33|34)
                    case "$FDISKL" in *"$DEVROOT/$DEVNAME "*) FSTYPE="$(fstype $DEVROOT/$DEVNAME)" ;; esac
                    case "$CDROMS" in *"$DEVROOT/$DEVNAME"*) FSTYPE="auto" ;; esac
                ;;
                179|9|259) # MMC or MD (software raid)
                    FSTYPE="$(fstype $DEVROOT/$DEVNAME)"
                ;;
            esac
        fi

        [ -z "$FSTYPE" ] && continue;
        MOUNTPOINT="/mnt/$DEVNAME";
        OPTIONS="noauto,users,exec";
        case "$FSTYPE" in
            ntfs)
                if [ -f /usr/local/bin/ntfs-3g ]; then
                    FSTYPE="ntfs-3g";
                    OPTIONS="$OPTIONS"
                else
                    FSTYPE="ntfs";
                    OPTIONS="$OPTIONS,ro,umask=000"
                fi
            ;;
            vfat|msdos) OPTIONS="${OPTIONS},umask=000" ;;
            ext2|ext3) OPTIONS="${OPTIONS},relatime" ;;
            swap) OPTIONS="defaults"; MOUNTPOINT="none" ;;
        esac
        [ "$MOUNTPOINT" != "none" ] && /bin/mkdir -pv "/mnt/$DEVNAME";
        /bin/grep -q "^$DEVROOT/$DEVNAME " $TMP || \
            printf "%-15s %-15s %-8s %-20s %-s\n" \
            "$DEVROOT/$DEVNAME" "$MOUNTPOINT" "$FSTYPE" "$OPTIONS" "0 0 $ADDEDBY" | \
            /usr/bin/tee -a "$TMP"
    done

    # Clean up
    /bin/mv -v "$TMP" /etc/fstab;
    /bin/rm -fv /var/run/rebuildfstab.pid;
    sync;

    # If another copy tried to run while we were running, rescan.
    if [ -e /var/run/rebuildfstab.rescan ]; then
        /bin/rm -fv /var/run/rebuildfstab.rescan;
        _rebuild_fstab "$@"
    fi

}

printf "\n\n[`date`]\n\033[1;33mRunning init script...\033[0;39m\n";

# set globle file mode mask
umask 022;

[ -d /root ] || /bin/mkdir -m 0750 /root;
[ -d /tmp  ] || /bin/mkdir -m 1777 /tmp;

/bin/mkdir -pv /sys /proc;

# Starting udev daemon...
/sbin/udevd --daemon 2>/dev/null;

# Udevadm requesting events from the Kernel...
/sbin/udevadm trigger --action=add >/dev/null 2>&1 &

/sbin/modprobe loop 2>/dev/null;

# start swap
/sbin/modprobe -q zram;
/sbin/modprobe -q zcache;

while [ ! -e /dev/zram0 ]; do /bin/usleep 50000; done

/bin/grep MemFree /proc/meminfo | /usr/bin/awk '{print $2/4 "K"}' | \
    /usr/bin/tee /sys/block/zram0/disksize;

/sbin/mkswap /dev/zram0 >/dev/null 2>&1;
/sbin/swapon /dev/zram0;

printf "%-15s %-12s %-7s %-17s %-7s %-s\n"\
    /dev/zram0 swap swap defaults,noauto 0 0 | \
    /usr/bin/tee -a /etc/fstab;

_rebuild_fstab & fstab_pid=$!

/bin/mv -v /tmp/98-tc.rules /etc/udev/rules.d/.;

# Udevadm waiting for the event queue to finish...
/sbin/udevadm control --reload-rules &

export LANG=C TZ=CST-8;
echo "LANG=$LANG" | /usr/bin/tee /etc/sysconfig/language;
echo "TZ=$TZ"     | /usr/bin/tee /etc/sysconfig/timezone;

while [ ! -e /dev/rtc0 ]; do /bin/usleep 50000; done

/sbin/hwclock -u -s &

/bin/hostname -F /etc/hostname;
# init ip
/sbin/ifconfig lo 127.0.0.1 up;
/sbin/route add 127.0.0.1 lo &

/sbin/modprobe -q squashfs 2>/dev/null;

# Laptop options enabled (AC, Battery and PCMCIA).
/sbin/modprobe ac && /sbin/modprobe battery 2>/dev/null;
/sbin/modprobe yenta_socket >/dev/null 2>&1 || /sbin/modprobe i82365 >/dev/null 2>&1;

wait $fstab_pid;

# busybox, keyboard
/sbin/loadkmap < /usr/share/kmap/${KEYMAP:=us}.kmap;

# filter environment variable
{
    /bin/sed 's/[\|\;\& ]/\n/g' /proc/cmdline | /bin/grep '^[_A-Z]\+=';
    printf "export PERSISTENT_PATH=$PERSISTENT_PATH\n"
} > /etc/profile.d/boot_envar.sh;

# Configure sysctl, Read sysctl.conf
/sbin/sysctl -p /etc/sysctl.conf;

/sbin/udevadm control --reload-rules;
/sbin/udevadm trigger;

# mount and monitor hard drive array
/usr/local/sbin/mdisk init;

# Starting system log daemon: syslogd...
/sbin/syslogd;
# Starting kernel log daemon: klogd...
/sbin/klogd;

# for find/crond/log
/bin/mkdir -p \
    /var/spool/cron/crontabs \
    $PERSISTENT_PATH/tiny/etc/init.d \
    $PERSISTENT_PATH/log/tiny/${Ymd:0:6};

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
/usr/bin/find $PERSISTENT_PATH/tiny/etc/init.d -type f -perm /u+x -name "S*.sh" -exec /bin/sh -c {} \;

# sync the clock
/usr/sbin/ntpd -d -n -p pool.ntp.org >> $PERSISTENT_PATH/log/tiny/${Ymd:0:6}/ntpd_$Ymd.log 2>&1 &

# start cron
/usr/sbin/crond -f -d "${CROND_LOGLEVEL:-8}" >> $PERSISTENT_PATH/log/tiny/${Ymd:0:6}/crond_$Ymd.log 2>&1 &

# hide directory
/bin/chmod 700 $PERSISTENT_PATH/tiny/etc;

#maybe the links will be up by now - trouble is, on some setups, they may never happen, so we can't just wait until they are
/bin/sleep 3;

# set the hostname
echo tc$(/sbin/ifconfig | /bin/grep -A 1 'eth[0-9]' | /bin/grep addr: | /usr/bin/awk '{print $2}' | /usr/bin/awk -F\. '{printf "-"$4}') | \
    /usr/bin/tee $PERSISTENT_PATH/tiny/etc/hostname;
HOSTNAME=`/bin/cat $PERSISTENT_PATH/tiny/etc/hostname` && /bin/hostname $HOSTNAME;

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
/bin/touch $PERSISTENT_PATH/tiny/etc/rc.local;
if [ -x $PERSISTENT_PATH/tiny/etc/rc.local ]; then
    echo "------ rc.local --------------";
    . $PERSISTENT_PATH/tiny/etc/rc.local
fi

printf "\033[1;32mFinished init script...\033[0;39m\n";

# /usr/bin/clear
