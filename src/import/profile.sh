#!/bin/bash

# Linux allocated devices (4.x+ version), https://www.kernel.org/doc/html/v4.11/admin-guide/devices.html
_create_dev() {
    [ -s $WORK_DIR/.error ] && return 1;
    rm -fr $ROOTFS_DIR/dev;
    cd $ROOTFS_DIR; mkdir -pv dev/{input,net,pts,shm,usb};

    # 1 char: Memory devices
    mknod -m 664 dev/mem    c 1 1; # Physical memory access
    mknod -m 664 dev/kmem   c 1 2; # Kernel virtual memory access
    mknod -m 666 dev/null   c 1 3; # Null device
    mknod -m 664 dev/port   c 1 4; # I/O port access
    mknod -m 664 dev/zero   c 1 5; # Null byte source
    # mknod -m 664 dev/core   c 1 6; # OBSOLETE - replaced by /proc/kcore
    mknod -m 664 dev/full   c 1 7; # Returns ENOSPC on write
    mknod -m 664 dev/random c 1 8; # Nondeterministic random number gen. fix: PRNG is not seeded
    mknod -m 664 dev/urandom    c 1 9; # Faster, less secure random number gen.

    local n;
    for n in `seq 0 7`;
    do
        # 1 block: RAM disk, (ubuntu no)
        mknod -m 664 dev/ram$n          b 1 $n;

        # 3 block: First MFM, RLL and IDE hard disk/CD-ROM interface, (ubuntu no)
        mknod -m 664 dev/hda$(_n0 $n)   b 3 $n;
        mknod -m 664 dev/hdb$(_n0 $n)   b 3 $((n + 64));
        mknod -m 664 dev/hdc$(_n0 $n)   b 3 $((n + 128));
        mknod -m 664 dev/hdd$(_n0 $n)   b 3 $((n + 192));

        # 4 char: TTY devices (0-63)
        mknod -m 666 dev/tty$n          c 4 $n;
        mknod -m 666 dev/ttyS$n         c 4 $((n + 64)); # UART serial port

        # 7 block: Loopback devices
        mknod -m 664 dev/loop$n         b 7 $n;

        # 7 char: Virtual console capture devices (0-63)
        mknod -m 664 dev/vcs$(_n0 $n)   c 7 $n;
        mknod -m 664 dev/vcsa$(_n0 $n)  c 7 $((n + 128));

        # 8 block: SCSI disk devices (0-15) (a-p), (ubuntu no)
        mknod -m 664 dev/sda$(_n0 $n)   b 8 $n;
        mknod -m 664 dev/sdb$(_n0 $n)   b 8 $((n + 16));

        # 11 block: SCSI CD-ROM devices,
        # The prefix /dev/sr (instead of /dev/scd) has been deprecated.
        mknod -m 664 dev/sr$n           b 11 $n;

        # 13 char: Input core
        mknod -m 664 dev/input/event$n  c 13 $((n + 64));

        # 180 char: USB devices (0-15), (ubuntu no)
        mknod -m 664 dev/usb/hiddev$n   c 180 $((n + 96))
    done

    # 5 char: Alternate TTY devices
    mknod -m 666 dev/tty        c 5 0; # Current TTY device
    mknod -m 622 dev/console    c 5 1; # System console
    mknod -m 666 dev/ptmx       c 5 2; # PTY master multiplex

    # 10 char: Non-serial mice, misc features
    mknod -m 664 dev/logibm     c 10 0; # Logitech bus mouse, (ubuntu no)
    mknod -m 664 dev/psaux      c 10 1; # PS/2-style mouse port
    mknod -m 664 dev/inportbm   c 10 2; # Microsoft Inport bus mouse, (ubuntu no)
    mknod -m 664 dev/atibm      c 10 3; # ATI XL bus mouse, (ubuntu no)
    mknod -m 664 dev/beep       c 10 128; # Fancy beep device, (ubuntu no)
    mknod -m 664 dev/nvram      c 10 144; # Non-volatile configuration RAM, (ubuntu no)
    mknod -m 664 dev/agpgart    c 10 175; # AGP Graphics Address Remapping Table, (ubuntu no)
    mknod -m 664 dev/net/tun    c 10 200; # TAP/TUN network device
    mknod -m 666 dev/fuse       c 10 229; # Fuse (virtual filesystem in user-space)

    # 13 char: Input core
    mknod -m 664 dev/input/mouse0   c 13 32; # First mouse
    mknod -m 664 dev/input/mice     c 13 63; # Unified mouse

    # 14 char: Open Sound System (OSS)
    mknod -m 664 dev/audio  c 14 4; # Sun-compatible digital audio, (ubuntu no)

    # 29 char: Universal frame buffer (0-31)
    mknod -m 622 dev/fb0    c 29 0;

    # 108 char: Device independent PPP interface
    mknod -m 664 dev/ppp    c 108 0; # Device independent PPP interface

    # Compulsory links
    ln -sv /proc/self/fd    dev/fd; # File descriptors
    ln -sv /proc/self/fd/0  dev/stdin; # stdin file descriptor
    ln -sv /proc/self/fd/1  dev/stdout; # stdout file descriptor
    ln -sv /proc/self/fd/2  dev/stderr; # stderr file descriptor

    # Recommended links
    ln -sv /proc/kcore      dev/core; # OBSOLETE - replaced by /proc/kcore
    ln -sv sda1             dev/flash; # Flash memory card (rw)
    ln -sv ram1             dev/ram; # RAM disk
    # ln -sv vcs0             dev/vcs; # Current vc text contents
    # ln -sv vcsa0            dev/vcsa; # Current vc text/attribute contents

    # mount -vt devpts    devpts  dev/pts -o gid=5,mode=620;
    # mount -vt proc      proc    proc;
    # mount -vt sysfs     sysfs   sys;
    # mount -v --bind /dev dev;
    # mount -vt tmpfs     tmpfs   run;

    cd $STATE_DIR

}

_create_etc() {
    [ -s $WORK_DIR/.error ] && return 1;

    echo " ------------- create etc -------------------------";
    # glibc
    _mkcfg $ROOTFS_DIR/etc/nsswitch.conf'
# GNU Name Service Switch config.
#

passwd:     files
group:      files
shadow:     files

hosts:      files dns
networks:   files

protocols:  files
services:   files
ethers:     files
rpc:        files
';

    # protocols, services
    _wait4 iana-etc- || return $(_err $LINENO 4);
    _try_patch iana-etc-;
    make && make DESTDIR=$ROOTFS_DIR install || return $(_err $LINENO 4);

    # hostname
    printf "tiny2containerd\n" > $ROOTFS_DIR/etc/hostname;

    # host.conf
    _mkcfg $ROOTFS_DIR/etc/host.conf'
# The "order" line is only used by old versions of the C library.
order hosts,bind
multi on
';

    # hosts
    _mkcfg $ROOTFS_DIR/etc/hosts'
127.0.0.1	box	localhost localhost.local
';

    # sysctl
    _mkcfg $ROOTFS_DIR/etc/sysctl.conf'
net.ipv4.ip_forward=1
# net.ipv6.conf.all.forwarding=1
';

    # fstab
    _mkcfg $ROOTFS_DIR/etc/fstab'
# /etc/fstab
proc            /proc        proc    defaults          0       0
sysfs           /sys         sysfs   defaults          0       0
devpts          /dev/pts     devpts  defaults          0       0
tmpfs           /dev/shm     tmpfs   defaults          0       0
';

    # group
    _mkcfg $ROOTFS_DIR/etc/group'
root:x:0:
lp:x:7:lp
nogroup:x:65534:
staff:x:50:
';

    # gshadow
    _mkcfg $ROOTFS_DIR/etc/gshadow'
root:*::
nogroup:!::
staff:!::
floppy:!::tcroot:x:0:0:root:/root:/bin/sh
lp:x:7:7:lp:/var/spool/lpd:/bin/sh
nobody:x:65534:65534:nobody:/nonexistent:/bin/false
';

    # passwd
    _mkcfg $ROOTFS_DIR/etc/passwd'
root:x:0:0:root:/root:/bin/sh
lp:x:7:7:lp:/var/spool/lpd:/bin/sh
nobody:x:65534:65534:nobody:/nonexistent:/bin/false
';

    # shadow
    _mkcfg $ROOTFS_DIR/etc/shadow'
root:*:13525:0:99999:7:::
lp:*:13510:0:99999:7:::
nobody:*:13509:0:99999:7:::
';

    # sudoers
    _mkcfg $ROOTFS_DIR/etc/sudoers"
#
# This file MUST be edited with the 'visudo' command as root.
#

# Host alias specification

# Cmnd alias specification
Cmnd_Alias WRITE_LOG_CMDS = /usr/local/sbin/wtmp

# User alias specification

# User privilege specification
ALL     ALL=PASSWD: ALL

root    ALL=(ALL) ALL

ALL     ALL=(ALL) NOPASSWD: WRITE_LOG_CMDS

";

    # profile
    _mkcfg $ROOTFS_DIR/etc/profile"
# /etc/profile: system-wide .profile file for the Bourne shells

umask 022;
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin;

if [ $(id -u) -eq 0 ]; then
    PS1='\u@\h:\W\# '
else
    # Light green and blue colored prompt.
    PS1='\e[1;32m\u@\h\e[0m:\e[1;34m\W\e[0m\$ '
fi

[ -f /etc/sysconfig/language ] && . /etc/sysconfig/language;
[ -f /etc/sysconfig/timezone ] && . /etc/sysconfig/timezone;

sudo /usr/local/sbin/wtmp;

for i in /etc/profile.d/*.sh; do [ -r \$i ] && . \$i; done; unset i;

export LANG LC_ALL PATH PS1 TERM=xterm TMOUT=300 TZ;

readonly TMOUT

";

    # .profile
    _mkcfg $ROOTFS_DIR/etc/skel/.profile"
# ~/.profile: Executed by Bourne-compatible login SHells.

PS1='\u@\h:\W\$ '
PAGER='less -EM'
MANPAGER='less -isR'
EDITOR=vi
FLWM_TITLEBAR_COLOR='58:7D:AA'

export EDITOR FILEMGR FLWM_TITLEBAR_COLOR MANPAGER PAGER PS1

[ -f \$HOME/.ashrc ] && . \$HOME/.ashrc

";

    touch $ROOTFS_DIR/etc/{skel/.ashrc,skel/.ash_history,motd};

    # fix "su -"
    mkdir -pv $ROOTFS_DIR/etc/sysconfig;
    printf %s 'root' > $ROOTFS_DIR/etc/sysconfig/superuser;

    # add some timezone files so we're explicit about being UTC
    printf %s 'UTC' | tee $ROOTFS_DIR/etc/timezone;
    cp -vL /usr/share/zoneinfo/UTC $ROOTFS_DIR/etc/localtime;
    # # time zone database
    # _wait4 tzdata || return $(_err $LINENO 4);
    # _try_patch tzdata;

    _mkcfg $ROOTFS_DIR/etc/acpi/events/all'
event=button/power*
action=/sbin/poweroff
';

    # securetty
    _mkcfg $ROOTFS_DIR/etc/securetty'
# /etc/securetty: List of terminals on which root is allowed to login.
console

# For people with serial port consoles
# ttyS0

# Standard consoles
tty1
tty2
tty3
tty4
tty5
tty6
tty7
';

    # shells
    _mkcfg $ROOTFS_DIR/etc/shells'
# /etc/shells: valid login shells
/bin/sh
/bin/ash
';

    ln -fsv init.d/rcK  $ROOTFS_DIR/etc/rc.shutdown
}

# TODO bionic-base-amd64.tar
_apply_rootfs() {
    [ -s $WORK_DIR/.error ] && return 1;

    # Copy our custom rootfs,
    echo "---------- copy custom rootfs --------------------";
    cd $THIS_DIR/rootfs;
    local sf;
    for sf in $(find . -type f);
    do
        sf="${sf#*/}"; # trim './' head
        mkdir -pv "$ROOTFS_DIR/${sf%/*}";
        if [ "${sf##*.}" == "sh" ]; then
            cp -fv "./$sf" "$ROOTFS_DIR/${sf%.*}"
        else
            cp -fv "./$sf" "$ROOTFS_DIR/${sf%/*}"
        fi
    done

    # for /etc/inittab
    _mkcfg $ROOTFS_DIR/sbin/autologin'
#!/bin/busybox ash
if [ -f /etc/sysconfig/autologin ]; then
    exec /sbin/getty 38400 tty1
else
    touch /etc/sysconfig/autologin;
    exec /bin/login -f root
fi
';

    cd $ROOTFS_DIR;
    mkdir -pv \
        etc/{acpi/events,init.d,modprobe.d,skel,ssl/certs,profile.d,sysconfig} \
        home lib mnt proc root run sys tmp var \
        usr/{sbin,share};

    chmod 0750 root;
    chmod 1777 tmp;
    cd $STATE_DIR;

    # executable
    find \
        $ROOTFS_DIR/init \
        $ROOTFS_DIR/usr/local/{,s}bin \
        $ROOTFS_DIR/etc/init.d \
        -type f -exec chmod -c +x '{}' +

}

_add_group() {
    [ -s $WORK_DIR/.error ] && return 1;
    echo "-------------- addgroup --------------------------";
    # for dockerd: root map user
    # set up subuid/subgid so that "--userns-remap=default" works out-of-the-box (see also src/rootfs/etc/sub{uid,gid})
    chroot $ROOTFS_DIR sh -xc '
        addgroup -S dockremap && \
        adduser -S -G dockremap dockremap
    ';
    echo "dockremap:165536:65536" | \
        tee $ROOTFS_DIR/etc/subgid > $ROOTFS_DIR/etc/subuid;

    chroot $ROOTFS_DIR addgroup -S docker
}

_add_user() {
    [ -s $WORK_DIR/.error ] && return 1;
    [ "$1" ] || return $(_err $LINENO 3);
    echo "--------------- adduser --------------------------";
    # add user: tc
    chroot $ROOTFS_DIR sh -xc "
        adduser -s /bin/sh -G staff -D $1 && \
        addgroup $1 docker && \
        printf $1:tcuser | /usr/sbin/chpasswd -m
    "
}

_trim_rootfs() {
    [ -s $WORK_DIR/.error ] && return 1;

    echo " --------------- trim file ------------------------";
    # http://www.linuxfromscratch.org/lfs/view/stable/chapter06/revisedchroot.html
    # clear var, drop passwd: /usr/bin/passwd -> /bin/busybox.suid, static library
    rm -frv \
        $ROOTFS_DIR/usr/bin/passwd \
        $ROOTFS_DIR/etc/{ssl/man,*-,sysconfig/autologin} \
        $ROOTFS_DIR/usr/{,local/}include \
        $ROOTFS_DIR/usr/{,local/}share/{info,man,doc} \
        $ROOTFS_DIR/{,usr/}lib/lib*.{,l}a;
        # $ROOTFS_DIR/var/* \

    # '/*' is necessary !
    find $ROOTFS_DIR/usr/share/locale/* \
        $ROOTFS_DIR/usr/share/i18n/locales/* \
        $ROOTFS_DIR/usr/share/i18n/charmaps/* \
        -maxdepth 1 \
        ! -name "en*"   ! -name "eu*"   ! -name "ja*"   ! -name "ko*"   ! -name "uk*"   ! -name "zh_*" \
        ! -name "ANSI_X3.*"     ! -name "BIG5*"     ! -name "GB*"   ! -name "ISO-8859-*" \
        ! -name "JIS_*" ! -name "KOI*"  ! -name "UTF*"  ! -name "*.alias" \
        -exec rm -frv {} +

    # test and move unexecutable script to '$OUT_DIR/uexe'
    for sh in $(grep -lr '\/bin\/bash\|\/bin\/perl' $ROOTFS_DIR/{,usr/}{,s}bin);
    do
        # file $sh | grep -q 'ELF' && continue;
        if file $sh | grep -q 'text executable'; then
            # replace '/bin/bash' to '/bin/sh'
            sed -i 's/\/bin\/bash/\/bin\/sh/g' $sh;
            sh -n $sh || {
                mkdir -pv $OUT_DIR/uexe;
                printf '[unexecutable]: ';
                mv -v $sh $OUT_DIR/uexe
            }
        fi
    done

    # http://www.linuxfromscratch.org/lfs/view/stable/chapter05/stripping.html
    # http://www.linuxfromscratch.org/lfs/view/stable/chapter06/strippingagain.html
    # Take care not to use '--strip-unneeded' on the libraries
    strip --strip-debug $ROOTFS_DIR/lib/*;
    strip --strip-unneeded $ROOTFS_DIR/{,usr/}{,s}bin/* # --strip-all

}
