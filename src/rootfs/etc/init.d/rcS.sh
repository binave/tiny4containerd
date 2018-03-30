#!/bin/sh
# Mount /proc.
[ -f /proc/cmdline ] || /bin/mount /proc;

# Remount rootfs rw.
/bin/mount -o remount,rw /;

# Mount system devices from /etc/fstab.
/bin/mount -a;

_rebuild_fstab(){

    # Exit if script is already running
    [ -e /proc/partitions ] || return;

    if [ -e /var/run/rebuildfstab.pid ]; then
        if [ -e "/proc/$(cat /var/run/rebuildfstab.pid)" ]; then
            touch /var/run/rebuildfstab.rescan;
            return
        fi
        rm -fv /var/run/rebuildfstab.pid
    fi

    echo "$$" | tee /var/run/rebuildfstab.pid;

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
            printf "%-15s %-15s %-8s %-20s %-s\n" \
            "$DEVROOT/$DEVNAME" "$MOUNTPOINT" "$FSTYPE" "$OPTIONS" "0 0 $ADDEDBY" | \
            tee -a "$TMP"
    done

    # Clean up
    mv -v "$TMP" /etc/fstab;
    rm -fv /var/run/rebuildfstab.pid;
    sync;

    # If another copy tried to run while we were running, rescan.
    if [ -e /var/run/rebuildfstab.rescan ]; then
        rm -fv /var/run/rebuildfstab.rescan;
        _rebuild_fstab "$@"
    fi

}

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin;
Ymd=`date +%Y%m%d`;

# This log is started before the persistence partition is mounted
{
    umask 022;

    /sbin/udevd --daemon;
    /sbin/udevadm trigger --action=add &

    sleep 5; # wait usb

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
    /sbin/udevadm control --reload-rules &

    export LANG=C TZ=CST-8;
    echo "LANG=$LANG" | tee /etc/sysconfig/language;
    echo "TZ=$TZ"     | tee /etc/sysconfig/timezone;

    while [ ! -e /dev/rtc0 ]; do usleep 50000; done

    /sbin/hwclock -u -s &

    /bin/hostname -F /etc/hostname;
    /sbin/ifconfig lo 127.0.0.1 up;
    /sbin/route add 127.0.0.1 lo &

    USER="tc";
    if ! grep "$USER" /etc/passwd >/dev/null; then
        /usr/sbin/adduser -s /bin/sh -G staff -D "$USER";
        echo "$USER":tcuser | /usr/sbin/chpasswd -m
    fi

    mkdir -pv /home/"$USER";

    chmod u+s /bin/busybox.suid /usr/bin/sudo;

    modprobe -q squashfs;
    /sbin/ldconfig;

    if [ -n "$LAPTOP" ]; then
        modprobe ac && modprobe battery;
        modprobe yenta_socket || modprobe i82365;
        /sbin/udevadm trigger &
    fi

    sync;
    wait $fstab_pid;

    # busybox, keyboard
    KEYMAP="us";
    /sbin/loadkmap < /usr/share/kmap/$KEYMAP.kmap;
    echo "KEYMAP=$KEYMAP" | tee /etc/sysconfig/keymap;

    # Configure sysctl, Read sysctl.conf
    sysctl -p /etc/sysctl.conf;

    [ ! -f /usr/local/etc/ca-certificates.conf ] && \
        cp -pv /usr/local/share/ca-certificates/files/ca-certificates.conf \
        /usr/local/etc;

    update-ca-certificates;
    # ln -sv /usr/local/etc/ssl/certs/ca-certificates.crt /usr/local/etc/ssl/cacert.pem;
    # ln -sv /usr/local/etc/ssl/certs/ca-certificates.crt /usr/local/etc/ssl/ca-bundle.crt;

    # fuse
    [ ! -f /sbin/mount.fuse ] && \
        ln -sv  /usr/local/sbin/mount.fuse /sbin/mount.fuse;

    # rules, not found: /etc/udev/rules.d/69-dm-lvm-metad.rules
    cp -pv \
        /usr/local/share/fuse/files/*.rules \
        /usr/local/share/lvm2/files/*.rules \
        /usr/local/share/mdadm/files*.rules \
        /etc/udev/rules.d;

    udevadm control --reload-rules;
    udevadm trigger;

    mkdir -pv /var/lib/sshd \
        /usr/local/etc/ssl/certs \
        /usr/local/etc/ssl/crl \
        /usr/local/etc/ssl/newcerts \
        /usr/local/etc/ssl/private;

    touch /usr/local/etc/ssl/index.txt;
    echo "01" | tee /usr/local/etc/ssl/crlnumber > /usr/local/etc/ssl/serial;

    cp -pv /usr/local/etc/hosts.* /etc/;

    # filter env
    sed 's/[\|\;\& ]/\n/g' /proc/cmdline | grep '^[_A-Z]\+=' > /etc/env;

    # mount and monitor hard drive array
    /usr/local/sbin/mdisk init;

    # for find/crond/log
    mkdir -pv \
        /opt/tiny/etc/crontabs \
        /opt/tiny/etc/init.d \
        /log/tiny/${Ymd:0:6};

    # mdiskd
    /usr/local/sbin/mdisk monitor;

    # create empty config
    [ -s /opt/tiny/etc/env ] || printf \
        "# set environment variable\n\n" > \
        /opt/tiny/etc/env;

    # filter env
    {
        awk -F# '{print $1}' /opt/tiny/etc/env 2>/dev/null | \
            sed 's/[\|\;\&]/\n/g;s/export//g;s/^[ ]\+//g' | grep '^[_A-Z]\+='
        printf "PERSISTENT_DATA=/opt\n\n"
    } >> /etc/env;

    # init env
    . /etc/env;

    # change password
    /usr/local/sbin/pwset;

    echo "------ firewall --------------";
    # http://wiki.tinycorelinux.net/wiki:firewall
    # tce-load -wi iptables; -> /usr/local/sbin/basic-firewall
    sh /usr/local/etc/init.d/firewall init;

    # set static ip or start dhcp
    /usr/local/sbin/ifset;

    # mount cgroups hierarchy. https://github.com/tianon/cgroupfs-mount
    sh /usr/local/etc/init.d/cgroupfs mount;

    sleep 2;

    # init
    find /opt/tiny/etc/init.d -type f -perm /u+x -name "S*.sh" -exec /bin/sh -c {} \;

    # sync the clock
    ntpd -d -n -p pool.ntp.org >> /log/tiny/${Ymd:0:6}/ntpd_$Ymd.log 2>&1 &

    # start cron
    crond -f -d "${CROND_LOGLEVEL:-8}" >> /log/tiny/${Ymd:0:6}/crond_$Ymd.log 2>&1 &

    # if we have the tc user, let's add it do the docker group
    grep -q '^tc:' /etc/passwd && addgroup tc docker;

    chmod 1777 /tmp /volume1;

    # hide directory
    chmod 700 /opt/tiny/etc;

    # mkdir /tmp/tce
    # tce-setup
    # printf "http://repo.tinycorelinux.net/\n" | tee /opt/tcemirror

    #maybe the links will be up by now - trouble is, on some setups, they may never happen, so we can't just wait until they are
    sleep 3;

    # set the hostname
    echo tiny$(ip addr | grep -A 2 'eth[0-9]*:' | grep inet | awk -F'[.]|/' '{print "-"$4}' | awk '{printf $_}') | \
        tee /opt/tiny/etc/hostname;
    HOSTNAME=`cat /opt/tiny/etc/hostname`;
    /usr/bin/sethostname $HOSTNAME;

    # ssh dameon start
    sh /usr/local/etc/init.d/sshd;

    # Launch ACPId (shutdown)
    /usr/local/etc/init.d/acpid start;

    echo "------ ifconfig --------------";
    # show ip info
    ifconfig | grep -A 2 '^[a-z]' | sed 's/Link .*//;s/--//g;s/UP.*//g;s/\s\s/ /g' | grep -v '^$';

    echo "----- containerd -------------";

    # Launch Containerd
    /usr/local/sbin/containerd start;

    # Allow rc.local customisation
    touch /opt/tiny/etc/rc.local;
    if [ -x /opt/tiny/etc/rc.local ]; then
        echo "------ rc.local --------------";
        . /opt/tiny/etc/rc.local
    fi

} 2>&1 | tee -a /var/log/boot_$Ymd.log;

# move log
{
    printf "\n\n[`date`]\n";
    cat /var/log/boot_*.log
} >> /log/tiny/${Ymd:0:6}/boot_$Ymd.log && rm -f /var/log/boot_*.log;

unset Ymd;

# echo "booting" > /etc/sysconfig/noautologin

