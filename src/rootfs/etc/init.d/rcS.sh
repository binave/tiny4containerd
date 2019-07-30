#!/bin/sh
_rebuild_fstab(){

    # Exit if script is already running
    [ -e /proc/partitions ] || return;

    if [ -e /run/rebuildfstab.pid ]; then
        if [ -e "/proc/$(cat /run/rebuildfstab.pid)" ]; then
            touch /run/rebuildfstab.rescan;
            return
        fi
        rm -fv /run/rebuildfstab.pid
    fi

    echo "$$" | tee /run/rebuildfstab.pid;

    local ADDEDBY CDROMS CDROMSF DEVMAJOR DEVNAME DEVROOT FDISKL FSTYPE MOUNTPOINT OPTIONS TMP i;

    TMP="/tmp/fstab.$$.tmp";
    ADDEDBY="# Added by TC";
    DEVROOT="/dev";

    # Create a list of fdisk -l
    FDISKL=`fdisk -l | awk '$1 ~ /dev/{printf " %s ",$1}'`;

    # Read a list of CDROM/DVD Drives
    CDROMS="";
    CDROMSF=/etc/sysconfig/cdroms;

    [ -s "$CDROMSF" ] && CDROMS=`cat "$CDROMSF"`;

    grep -v "$ADDEDBY" /etc/fstab | tee "$TMP";

    # Loop through block devices
    for i in `find /sys/block/*/ -name dev`;
    do
        case "$i" in *loop*|*ram*) continue ;; esac

        DEVNAME=`echo "$i" | tr [!] [/] | awk 'BEGIN{FS="/"}{print $(NF-1)}'`;
        DEVMAJOR="$(cat $i | cut -f1 -d:)";

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
        [ "$MOUNTPOINT" != "none" ] && mkdir -pv "/mnt/$DEVNAME";
        grep -q "^$DEVROOT/$DEVNAME " $TMP || \
            printf "%-15s %-12s %-7s %-17s %-7s %-2s %-s\n" \
            "$DEVROOT/$DEVNAME" "$MOUNTPOINT" "$FSTYPE" "$OPTIONS" 0 0 "$ADDEDBY" | \
            tee -a "$TMP"
    done

    # Clean up
    mv -v "$TMP" /etc/fstab;
    rm -fv /run/rebuildfstab.pid;
    sync;

    # If another copy tried to run while we were running, rescan.
    if [ -e /run/rebuildfstab.rescan ]; then
        rm -fv /run/rebuildfstab.rescan;
        _rebuild_fstab "$@"
    fi

}

date;

printf "\n\n[`date`]\n\033[1;33mRunning init script...\033[0;39m\n";

# This log is started before the persistence partition is mounted
umask 022;

udevd --daemon;
udevadm trigger --action=add &

sleep 7; # wait usb

modprobe loop;
modprobe -q zram;
modprobe -q zcache;

while [ ! -e /dev/zram0 ]; do usleep 50000; done

grep MemFree /proc/meminfo | awk '{print $2/4 "K"}' | \
    tee /sys/block/zram0/disksize;

mkswap /dev/zram0;
swapon /dev/zram0;

printf "%-15s %-12s %-7s %-17s %-7s %-s\n"\
    /dev/zram0 swap swap defaults,noauto 0 0 | \
    tee -a /etc/fstab;

_rebuild_fstab & fstab_pid=$!

mv -v /tmp/98-tc.rules /etc/udev/rules.d/.;
udevadm control --reload-rules &

while [ ! -e /dev/rtc0 ]; do usleep 50000; done

modprobe -q squashfs;

# Laptop options enabled (AC, Battery and PCMCIA).
if grep -iq LAPTOP /proc/cmdline; then
    modprobe ac && modprobe battery;
    modprobe yenta_socket || modprobe i82365;
    udevadm trigger &
fi

sync;
wait $fstab_pid;

# Configure sysctl, Read sysctl.conf
sysctl -p /etc/sysctl.conf;

udevadm control --reload-rules;
udevadm trigger;

# filter environment variable
{
    sed 's/[\|\;\& ]/\n/g' /proc/cmdline | grep '^[_A-Z]\+='
} > /etc/profile.d/boot_envar.sh;

# mount and monitor hard drive array
/usr/local/etc/init.d/mdisk init;

# keyboard(busybox), LANG
. /etc/profile.d/boot_envar.sh;
loadkmap < /usr/share/kmap/${KEYMAP:-us}.kmap;
export LANG=${LANG:-C} TZ=${TZ:-CST-8};
echo "LANG=$LANG" | tee /etc/sysconfig/language;
echo "TZ=$TZ"     | tee /etc/sysconfig/timezone;
localedef -i ${LANG%.*} -f UTF-8 ${LANG%.*};

# for crond, find, log
mkdir -pv \
    /var/spool/cron/crontabs \
    /home/etc/init.d \
    /home/log/sys/${Ymd:0:6};

# mdiskd
/usr/local/etc/init.d/mdisk monitor;

hwclock -u -s &

hostname -F /etc/hostname;
ifconfig lo 127.0.0.1 up;
route add 127.0.0.1 lo &

# init environment from disk
/usr/local/etc/init.d/envset;

# change password
/usr/local/etc/init.d/pwset;

echo "------ firewall --------------";
# http://wiki.tinycorelinux.net/wiki:firewall
# tce-load -wi iptables; -> /usr/local/sbin/basic-firewall
sh /usr/local/etc/init.d/firewall init;

# set static ip or start dhcp
/usr/local/etc/init.d/ifset;

# mount cgroups hierarchy. https://github.com/tianon/cgroupfs-mount
sh /usr/local/etc/init.d/cgroupfs mount;

sleep 2;

# init
find /home/etc/init.d -type f -perm /u+x -name "S*.sh" -exec /bin/sh -c {} \;

# sync the clock
ntpd -d -n -p pool.ntp.org >> /home/log/sys/${Ymd:0:6}/ntpd_$Ymd.log 2>&1 &

# start cron
crond -f -d "${CROND_LOGLEVEL:-8}" >> /home/log/sys/${Ymd:0:6}/crond_$Ymd.log 2>&1 &

chmod 1777 /tmp;

# hide directory
chmod 700 /home/etc;

#maybe the links will be up by now - trouble is, on some setups, they may never happen, so we can't just wait until they are
sleep 3;

# set the hostname
echo tc$(ip addr | grep -A 2 'eth[0-9]*:' | grep inet | awk -F'[.]|/' '{print "-"$4}' | awk '{printf $_}') | \
    tee /home/etc/hostname;
HOSTNAME=`cat /home/etc/hostname`;
sethostname $HOSTNAME;

# ssh dameon start
sh /usr/local/etc/init.d/sshd;

# Launch ACPId (shutdown)
/usr/local/etc/init.d/acpid start;

echo "------ ifconfig --------------";
# show ip info
ifconfig | grep -A 2 '^[a-z]' | sed 's/Link .*//;s/--//g;s/UP.*//g;s/\s\s/ /g' | grep -v '^$';

echo "----- containerd -------------";

# Launch Containerd
/usr/local/etc/init.d/containerd start;

# Allow rc.local customisation
touch /home/etc/rc.local;
if [ -x /home/etc/rc.local ]; then
    echo "------ rc.local --------------";
    . /home/etc/rc.local
fi

printf "\033[1;32mFinished init script...\033[0;39m\n";
