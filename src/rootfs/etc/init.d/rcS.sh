#!/bin/sh
# Mount /proc.
[ -f /proc/cmdline ] || /bin/mount /proc;

# Remount rootfs rw.
/bin/mount -o remount,rw /;

# Mount system devices from /etc/fstab.
/bin/mount -a;

# [ -f /proc/cmdline ] || /bin/mount /proc;

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin;

/sbin/udevd --daemon 2>&1 >/dev/null;

/sbin/udevadm trigger --action=add 2>&1 >/dev/null &

rotdash $!;

sleep 5; # WAITUSB

modprobe loop 2>/dev/null;

modprobe -q zram;
modprobe -q zcache;

while [ ! -e /dev/zram0 ]; do usleep 50000; done

grep MemFree /proc/meminfo | awk '{print $2/4 "K"}' > /sys/block/zram0/disksize;

mkswap /dev/zram0 >/dev/null 2>&1;
swapon /dev/zram0;
echo "/dev/zram0  swap         swap    defaults,noauto   0       0" >> /etc/fstab;

{
    umask 022

    # Exit if script is already running
    [ -e /proc/partitions ] || exit
    if [ -e /var/run/rebuildfstab.pid ]; then
        if [ -e "/proc/$(cat /var/run/rebuildfstab.pid)" ]; then
            touch /var/run/rebuildfstab.rescan 2>/dev/null;
            exit
        fi
        rm -fv /var/run/rebuildfstab.pid
    fi
    echo "$$" >/var/run/rebuildfstab.pid;

    TMP="/tmp/fstab.$$.tmp";
    ADDEDBY="# Added by TC";
    DEVROOT="/dev";

    # Create a list of fdisk -l
    FDISKL=`fdisk -l | awk '$1 ~ /dev/{printf " %s ",$1}'`;

    # Read a list of CDROM/DVD Drives
    CDROMS="";
    CDROMSF=/etc/sysconfig/cdroms;
    [ -s "$CDROMSF" ] &&  CDROMS=`cat "$CDROMSF"`;

    grep -v "$ADDEDBY" /etc/fstab > "$TMP";

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

        checkntfs() {
            if [ -f /usr/local/bin/ntfs-3g ]; then
                FSTYPE="ntfs-3g";
                OPTIONS="$OPTIONS"
            else
                FSTYPE="ntfs";
                OPTIONS="$OPTIONS,ro,umask=000"
            fi
        }

        [ -z "$FSTYPE" ] && continue;
        MOUNTPOINT="/mnt/$DEVNAME";
        OPTIONS="noauto,users,exec";
        case "$FSTYPE" in
            ntfs) checkntfs ;;
            vfat|msdos) OPTIONS="${OPTIONS},umask=000" ;;
            ext2|ext3) OPTIONS="${OPTIONS},relatime" ;;
            swap) OPTIONS="defaults"; MOUNTPOINT="none" ;;
        esac
        if [ "$MOUNTPOINT" != "none" ]; then
            mkdir -pv "/mnt/$DEVNAME" 2>/dev/null >/dev/null
        fi
        grep -q "^$DEVROOT/$DEVNAME " $TMP || \
            printf "%-15s %-15s %-8s %-20s %-s\n" "$DEVROOT/$DEVNAME" "$MOUNTPOINT" "$FSTYPE" "$OPTIONS" "0 0 $ADDEDBY" >> "$TMP"
    done

    # Clean up
    mv -v "$TMP" /etc/fstab;
    rm -fv /var/run/rebuildfstab.pid;
    sync;

    # If another copy tried to run while we were running, rescan.
    if [ -e /var/run/rebuildfstab.rescan ]; then
        rm -fv /var/run/rebuildfstab.rescan;
        exec $0 "$@"
    fi

} & fstab_pid=$!

mv -v /tmp/98-tc.rules /etc/udev/rules.d/. 2>/dev/null;

/sbin/udevadm control --reload-rules &

LANGUAGE="C";
echo "LANG=$LANGUAGE" > /etc/sysconfig/language;

export LANG=$LANGUAGE;

export TZ && echo "TZ=$TZ" > /etc/sysconfig/timezone;

while [ ! -e /dev/rtc0 ]; do usleep 50000; done

/sbin/hwclock -u -s &

/bin/hostname -F /etc/hostname;
/sbin/ifconfig lo 127.0.0.1 up;
/sbin/route add 127.0.0.1 lo &

USER="tc";

if ! grep "$USER" /etc/passwd >/dev/null; then
    /usr/sbin/adduser -s /bin/sh -G staff -D "$USER";
    echo "$USER":tcuser | /usr/sbin/chpasswd -m;
    echo -e "$USER\tALL=NOPASSWD: ALL" >> /etc/sudoers
fi

echo "$USER" > /etc/sysconfig/tcuser;

mkdir -pv /home/"$USER";

chmod u+s /bin/busybox.suid /usr/bin/sudo;

modprobe -q squashfs 2>/dev/null;

# touch /var/tmp/k5_skip;

/sbin/ldconfig 2>/dev/null;

unset OPT_SETUP

if [ -n "$LAPTOP" ]; then
	modprobe ac && modprobe battery 2>/dev/null;
	modprobe yenta_socket >/dev/null 2>&1 || modprobe i82365 >/dev/null 2>&1;
	/sbin/udevadm trigger 2>/dev/null >/dev/null &
fi

[ -s /etc/sysconfig/icons ] && ICONS=`cat /etc/sysconfig/icons`;

sync;

wait $fstab_pid;

rotdash $!;
rotdash $!;

KEYMAP="us";

# busybox, keyboard
/sbin/loadkmap < /usr/share/kmap/$KEYMAP.kmap;
echo "KEYMAP=$KEYMAP" > /etc/sysconfig/keymap;

# [ -s /etc/sysconfig/desktop ] && DESKTOP=`cat /etc/sysconfig/desktop`;

# [ -s /etc/sysconfig/ntpserver ] && NTPSERVER=`cat /etc/sysconfig/ntpserver`;

# echo "mydata" > /etc/sysconfig/mydata;

# [ -z "$DHCP_RAN" ] && /etc/init.d/dhcp.sh &

Ymd=`date +%Y%m%d`;

# This log is started before the persistence partition is mounted
{

    # Configure sysctl, Read sysctl.conf
    sysctl -p /etc/sysctl.conf;

    [ ! -d /usr/local/etc/acpi/events ] && mkdir -pv /usr/local/etc/acpi/events;
    [ ! -d /usr/local/etc ] && mkdir -pv /usr/local/etc;
    [ ! -f /usr/local/etc/ca-certificates.conf ] && cp -p /usr/local/share/ca-certificates/files/ca-certificates.conf /usr/local/etc;

    update-ca-certificates;
    ln -s /usr/local/etc/ssl/certs/ca-certificates.crt /usr/local/etc/ssl/cacert.pem;
    ln -s /usr/local/etc/ssl/certs/ca-certificates.crt /usr/local/etc/ssl/ca-bundle.crt;

    if [ ! -f /etc/udev/rules.d/99-fuse.rules ]; then
        cp -p /usr/local/share/fuse/files/99-fuse.rules /etc/udev/rules.d;
        udevadm control --reload-rules;
        udevadm trigger
    fi

    [ ! -f /sbin/mount.fuse ] &&                        ln -s /usr/local/sbin/mount.fuse /sbin/mount.fuse;

    [ ! -f /etc/udev/rules.d/10-dm.rules ] &&           cp -p /usr/local/share/lvm2/files/10-dm.rules           /etc/udev/rules.d;
    [ ! -f /etc/udev/rules.d/11-dm-lvm.rules ] &&       cp -p /usr/local/share/lvm2/files/11-dm-lvm.rules       /etc/udev/rules.d;
    [ ! -f /etc/udev/rules.d/13-dm-disk.rules ] &&      cp -p /usr/local/share/lvm2/files/13-dm-disk.rules      /etc/udev/rules.d;
    [ ! -f /etc/udev/rules.d/69-dm-lvm-metad.rules ] && cp -p /usr/local/share/lvm2/files/69-dm-lvm-metad.rules /etc/udev/rules.d;
    [ ! -f /etc/udev/rules.d/95-dm-notify.rules ] &&    cp -p /usr/local/share/lvm2/files/95-dm-notify.rules    /etc/udev/rules.d;

    udevadm control --reload-rules;
    udevadm trigger;

    [ ! -f /etc/udev/rules.d/63-md-raid-arrays.rules ] &&   cp -p /usr/local/share/mdadm/files/63-md-raid-arrays.rules      /etc/udev/rules.d;
    [ ! -f /etc/udev/rules.d/64-md-raid-assembly.rules ] && cp -p /usr/local/share/mdadm/files/64-md-raid-assembly.rules    /etc/udev/rules.d;

    udevadm control --reload-rules;
    udevadm trigger;

    [ ! -d /var/lib/sshd ] && mkdir -pv /var/lib/sshd;

    [ -d /usr/local/etc/ssl/certs ] ||      mkdir -pv   /usr/local/etc/ssl/certs;
    [ -d /usr/local/etc/ssl/private ] ||    mkdir -pv   /usr/local/etc/ssl/private;
    [ -d /usr/local/etc/ssl/crl ] ||        mkdir -pv   /usr/local/etc/ssl/crl;
    [ -d /usr/local/etc/ssl/newcerts ] ||   mkdir -pv   /usr/local/etc/ssl/newcerts;
    [ -f /usr/local/etc/ssl/index.txt ] ||  touch       /usr/local/etc/ssl/index.txt;
    [ -f /usr/local/etc/ssl/serial ] ||    echo "01" >  /usr/local/etc/ssl/serial;
    [ -f /usr/local/etc/ssl/crlnumber ] || echo "01" >  /usr/local/etc/ssl/crlnumber;

    [ -e /etc/hosts.allow ] ||  cp -p /usr/local/etc/hosts.allow /etc/;
    [ -e /etc/hosts.deny ] ||   cp -p /usr/local/etc/hosts.deny  /etc/;

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
} >> /log/tiny/${Ymd:0:6}/boot_$Ymd.log && rm -fv /var/log/boot_*.log;

unset Ymd;

# echo "booting" > /etc/sysconfig/noautologin


