#!/bin/bash

_create_etc() {
    [ -s $WORK_DIR/.error ] && return 1;

    echo " ------------- create etc -------------------------";

    # glibc
    printf %s '# GNU Name Service Switch config.
# Begin /etc/nsswitch.conf

passwd: files
group: files
shadow: files

hosts: files dns
networks: files

protocols: files
services: files
ethers: files
rpc: files

# End /etc/nsswitch.conf
' | tee $ROOTFS_DIR/etc/nsswitch.conf

    # hostname
    printf %s 'tiny2containerd
' | tee $ROOTFS_DIR/etc/hostname;

    # host.conf
    printf %s '# The "order" line is only used by old versions of the C library.
order hosts,bind
multi on
' | tee $ROOTFS_DIR/etc/host.conf;

    # hosts
    printf %s '127.0.0.1	box	localhost localhost.local
' | tee $ROOTFS_DIR/etc/hosts;

    # sysctl
    printf %s 'net.ipv4.ip_forward=1
# net.ipv6.conf.all.forwarding=1
' | tee $ROOTFS_DIR/etc/sysctl.conf;

    # fstab
    printf %s '# /etc/fstab
proc            /proc        proc    defaults          0       0
sysfs           /sys         sysfs   defaults          0       0
devpts          /dev/pts     devpts  defaults          0       0
tmpfs           /dev/shm     tmpfs   defaults          0       0
' | tee $ROOTFS_DIR/etc/fstab;

    # group
    [ -f $ROOTFS_DIR/etc/group ] && printf "[WARN] skip '/etc/group'\n" || printf %s '
root:x:0:
lp:x:7:lp
nogroup:x:65534:
staff:x:50:
' | tee $ROOTFS_DIR/etc/group;

    # gshadow
    [ -f $ROOTFS_DIR/etc/gshadow ] && printf "[WARN] skip '/etc/gshadow'\n" || printf %s '
root:*::
nogroup:!::
staff:!::
floppy:!::tcroot:x:0:0:root:/root:/bin/sh
lp:x:7:7:lp:/var/spool/lpd:/bin/sh
nobody:x:65534:65534:nobody:/nonexistent:/bin/false
' | tee $ROOTFS_DIR/etc/gshadow;

    # passwd
    [ -f $ROOTFS_DIR/etc/passwd ] && printf "[WARN] skip '/etc/passwd'\n" || printf %s '
root:x:0:0:root:/root:/bin/sh
lp:x:7:7:lp:/var/spool/lpd:/bin/sh
nobody:x:65534:65534:nobody:/nonexistent:/bin/false
' | tee $ROOTFS_DIR/etc/passwd;

    # shadow
    [ -f $ROOTFS_DIR/etc/shadow ] && printf "[WARN] skip '/etc/shadow'\n" || printf %s '
root:*:13525:0:99999:7:::
lp:*:13510:0:99999:7:::
nobody:*:13509:0:99999:7:::
' | tee $ROOTFS_DIR/etc/shadow;

    # sudoers
    printf %s "#
# This file MUST be edited with the 'visudo' command as root.
#
# See the man page for details on how to write a sudoers file.
#

# Host alias specification

# User alias specification
Cmnd_Alias WRITE_CMDS = /usr/bin/tee /etc/sysconfig/backup, /usr/local/bin/wtmp

# Cmnd alias specification

# User privilege specification
root    ALL=(ALL) ALL

" # | tee $ROOTFS_DIR/etc/sudoers;

    # profile
    printf %s "# /etc/profile: system-wide .profile file for the Bourne shells

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

sudo /usr/local/bin/wtmp;

for i in /etc/profile.d/*.sh; do [ -r \$i ] && . \$i; done; unset i;

export LANG LC_ALL PATH PS1 TERM=xterm TMOUT=300 TZ;

readonly TMOUT

" | tee $ROOTFS_DIR/etc/profile;

    mkdir -pv $ROOTFS_DIR/etc/{skel,sysconfig};

    # .profile
    printf %s "# ~/.profile: Executed by Bourne-compatible login SHells.

PS1='\u@\h:\W\$ '
PAGER='less -EM'
MANPAGER='less -isR'
EDITOR=vi
FLWM_TITLEBAR_COLOR='58:7D:AA'

export EDITOR FILEMGR FLWM_TITLEBAR_COLOR MANPAGER PAGER PS1

[ -f \$HOME/.ashrc ] && . \$HOME/.ashrc

" | tee $ROOTFS_DIR/etc/skel/.profile;

    touch $ROOTFS_DIR/etc/{skel/.ashrc,skel/.ash_history,motd};

    # fix "su -"
    echo root > $ROOTFS_DIR/etc/sysconfig/superuser;

    # add some timezone files so we're explicit about being UTC
    echo 'UTC' | tee $ROOTFS_DIR/etc/timezone;

    mkdir -pv $ROOTFS_DIR/etc/acpi/events;
    printf %s 'event=button/power*
action=/sbin/poweroff
' | tee $ROOTFS_DIR/etc/acpi/events/all;

    # securetty
    echo '# /etc/securetty: List of terminals on which root is allowed to login.
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
' | tee $ROOTFS_DIR/etc/securetty;

    # shells
    echo '# /etc/shells: valid login shells
/bin/sh
/bin/ash
' | tee $ROOTFS_DIR/etc/shells;

}

# Linux allocated devices (4.x+ version), https://www.kernel.org/doc/html/v4.11/admin-guide/devices.html
_create_dev() {
    [ -s $WORK_DIR/.error ] && return 1;
    rm -fr $ROOTFS_DIR/dev;
    cd $ROOTFS_DIR; mkdir -pv dev/{input,net,pts,shm,usb};

    # 1 char: Memory devices
    mknod -m 640 dev/mem    c 1 1; # Physical memory access
    mknod -m 640 dev/kmem   c 1 2; # Kernel virtual memory access
    mknod -m 666 dev/null   c 1 3; # Null device
    mknod -m 640 dev/port   c 1 4; # I/O port access
    mknod -m 666 dev/zero   c 1 5; # Null byte source
    # mknod -m 666 dev/core   c 1 6; # OBSOLETE - replaced by /proc/kcore
    mknod -m 666 dev/full   c 1 7; # Returns ENOSPC on write
    mknod -m 444 dev/random c 1 8; # Nondeterministic random number gen. fix: PRNG is not seeded
    mknod -m 444 dev/urandom    c 1 9; # Faster, less secure random number gen.

    local n;
    for n in `seq 0 7`;
    do
        # 1 block: RAM disk
        mknod -m 660 dev/ram$n          b 1 $n;

        # 3 block: First MFM, RLL and IDE hard disk/CD-ROM interface
        mknod -m 660 dev/hda$(_n0 $n)   b 3 $n;
        mknod -m 660 dev/hdb$(_n0 $n)   b 3 $((n + 64));
        mknod -m 660 dev/hdc$(_n0 $n)   b 3 $((n + 128));
        mknod -m 660 dev/hdd$(_n0 $n)   b 3 $((n + 192));

        # 4 char: TTY devices (0-63)
        mknod -m 622 dev/tty$n          c 4 $n;
        mknod -m 660 dev/ttyS$n         c 4 $((n + 64)); # UART serial port

        # 7 block: Loopback devices
        mknod -m 660 dev/loop$n         b 7 $n;

        # 7 char: Virtual console capture devices (0-63)
        mknod -m 600 dev/vcs$(_n0 $n)   c 7 $n;
        mknod -m 600 dev/vcsa$(_n0 $n)  c 7 $((n + 128));

        # 8 block: SCSI disk devices (0-15) (a-p)
        mknod -m 660 dev/sda$(_n0 $n)   b 8 $n;
        mknod -m 660 dev/sdb$(_n0 $n)   b 8 $((n + 16));

        # 13 char: Input core
        mknod -m 640 dev/input/event$n  c 13 $((n + 64));

        # 180 char: USB devices (0-15)
        mknod -m 660 dev/usb/hiddev$n   c 180 $((n + 96))

    done

    # 5 char: Alternate TTY devices
    mknod -m 666 dev/tty        c 5 0; # Current TTY device
    mknod -m 622 dev/console    c 5 1; # System console
    mknod -m 666 dev/ptmx       c 5 2; # PTY master multiplex

    # 10 char: Non-serial mice, misc features
    mknod -m 660 dev/logibm     c 10 0; # Logitech bus mouse
    mknod -m 660 dev/psaux      c 10 1; # PS/2-style mouse port
    mknod -m 660 dev/inportbm   c 10 2; # Microsoft Inport bus mouse
    mknod -m 660 dev/atibm      c 10 3; # ATI XL bus mouse
    mknod -m 660 dev/beep       c 10 128; # Fancy beep device
    mknod -m 660 dev/nvram      c 10 144; # Non-volatile configuration RAM
    mknod -m 660 dev/agpgart    c 10 175; # AGP Graphics Address Remapping Table
    mknod -m 666 dev/net/tun    c 10 200; # TAP/TUN network device
    mknod -m 600 dev/fuse       c 10 229; # Fuse (virtual filesystem in user-space)

    # 13 char: Input core
    mknod -m 660 dev/input/mouse0   c 13 32; # First mouse
    mknod -m 660 dev/input/mice     c 13 63; # Unified mouse

    # 14 char: Open Sound System (OSS)
    mknod -m 660 dev/audio  c 14 4; # Sun-compatible digital audio

    # 29 char: Universal frame buffer (0-31)
    mknod -m 622 dev/fb0    c 29 0;

    # 108 char: Device independent PPP interface
    mknod -m 660 dev/ppp    c 108 0; # Device independent PPP interface

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

    cd -

}

_n0() { [ $1 == 0 ] || printf %s $1; }

# TODO bionic-base-amd64.tar
_apply_rootfs() {
    [ -s $WORK_DIR/.error ] && return $(_err $LINENO 3);
    _create_dev;

    cd $ROOTFS_DIR;
    mkdir -pv \
        etc/{acpi/events,init.d,modprobe.d,skel,ssl/certs,profile.d,sysconfig} \
        home lib mnt proc root run sys tmp \
        usr/{sbin,share};
        # var run

    # replace '/bin/bash' to '/bin/sh', move perl script to '/opt'
    for sh in $(grep -lr '\/bin\/bash\|\/bin\/perl' $ROOTFS_DIR/{,usr/}{,s}bin);
    do
        sed -i 's/\/bin\/bash/\/bin\/sh/g' $sh;
        sh -n $sh || mv -v $sh /opt
    done

    # Copy our custom rootfs,
    cp -frv $THIS_DIR/rootfs/* $ROOTFS_DIR;

    # for /etc/inittab
    printf %s '#!/bin/busybox ash
if [ -f /etc/sysconfig/autologin ]; then
    exec /sbin/getty 38400 tty1
else
    touch /etc/sysconfig/autologin;
    exec /bin/login -f root
fi
' | tee $ROOTFS_DIR/sbin/autologin;

    # trim suffix
    local sf sh;
    for sf in $(cd $THIS_DIR/rootfs; find . -type f -name "*.sh");
    do
        sf="$ROOTFS_DIR/${sf#*/}";
        mv -f "$sf" "${sf%.*}";
        # chmod
    done

    # executable
    chmod +x $ROOTFS_DIR/init;
    find $ROOTFS_DIR/usr/local/{,s}bin $ROOTFS_DIR/etc/init.d -type f -exec chmod -c +x '{}' +

    chmod 0750 $ROOTFS_DIR/root;
    chmod 1777 $ROOTFS_DIR/tmp;

    # copy timezone
    cp -vL /usr/share/zoneinfo/UTC $ROOTFS_DIR/etc/localtime;

    # initrd.img
    ln -fsv bin/busybox                     $ROOTFS_DIR/linuxrc;

    # git-core
    ln -fsv /var/git-core/bin/git           $ROOTFS_DIR/usr/bin/;

    # subversion
    ln -fsv /var/subversion/bin/svn         $ROOTFS_DIR/usr/bin/;
    ln -fsv /var/subversion/bin/svnadmin    $ROOTFS_DIR/usr/bin/;
    ln -fsv /var/subversion/bin/svnlook     $ROOTFS_DIR/usr/bin/;

    # visudo
    ln -fsv $(readlink $ROOTFS_DIR/usr/bin/readlink)    $ROOTFS_DIR/usr/bin/vi;

    # http://www.linuxfromscratch.org/lfs/view/stable/chapter05/stripping.html
    # http://www.linuxfromscratch.org/lfs/view/stable/chapter06/strippingagain.html
    # Take care not to use '--strip-unneeded' on the libraries
    strip --strip-debug $ROOTFS_DIR/lib/*;
    strip --strip-unneeded $ROOTFS_DIR/{,usr/}{,s}bin/*; # --strip-all

}
