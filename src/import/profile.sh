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
    printf %s '
root:x:0:
lp:x:7:lp
nogroup:x:65534:
staff:x:50:
' | tee $ROOTFS_DIR/etc/group;

    # gshadow
    printf %s '
root:*::
nogroup:!::
staff:!::
floppy:!::tcroot:x:0:0:root:/root:/bin/sh
lp:x:7:7:lp:/var/spool/lpd:/bin/sh
nobody:x:65534:65534:nobody:/nonexistent:/bin/false
' | tee $ROOTFS_DIR/etc/gshadow;

    # passwd
    printf %s '
root:x:0:0:root:/root:/bin/sh
lp:x:7:7:lp:/var/spool/lpd:/bin/sh
nobody:x:65534:65534:nobody:/nonexistent:/bin/false
' | tee $ROOTFS_DIR/etc/passwd;

    # shadow
    printf %s '
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
Cmnd_Alias WRITE_CMDS = /usr/bin/tee /etc/sysconfig/backup, /usr/local/sbin/wtmp

# Cmnd alias specification

# User privilege specification
root    ALL=(ALL) ALL

" | tee $ROOTFS_DIR/etc/sudoers;

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

export LANG LC_ALL PATH PS1 TERM=xterm TMOUT=300 TZ;

sudo /usr/local/sbin/wtmp;

readonly TMOUT;

for i in /etc/profile.d/*.sh; do [ -r \$i ] && . \$i; done
unset i
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

}

# Linux allocated devices (4.x+ version), https://www.kernel.org/doc/html/v4.11/admin-guide/devices.html
_create_dev() {
    [ -s $WORK_DIR/.error ] && return 1;

    mkdir -pv $ROOTFS_DIR/dev/{pts,shm};

    # Memory devices
    mknod -m 666 $ROOTFS_DIR/dev/null c 1 3;
    mknod -m 666 $ROOTFS_DIR/dev/port c 1 4
    mknod -m 666 $ROOTFS_DIR/dev/zero c 1 5;
    mknod -m 666 $ROOTFS_DIR/dev/full c 1 7;
    mknod -m 666 $ROOTFS_DIR/dev/random c 1 8; # fix: PRNG is not seeded
    mknod -m 644 $ROOTFS_DIR/dev/urandom c 1 9;

    # TTY devices
    mknod -m 660 $ROOTFS_DIR/dev/tty0 c 4 0
    mknod -m 620 $ROOTFS_DIR/dev/tty1 c 4 1
    mknod -m 600 $ROOTFS_DIR/dev/tty2 c 4 2
    mknod -m 600 $ROOTFS_DIR/dev/tty3 c 4 3
    mknod -m 600 $ROOTFS_DIR/dev/tty4 c 4 4
    mknod -m 600 $ROOTFS_DIR/dev/tty5 c 4 5
    mknod -m 600 $ROOTFS_DIR/dev/tty6 c 4 6
    mknod -m 600 $ROOTFS_DIR/dev/ttyS0 c 4 64

    # Alternate TTY devices
    mknod -m 666 $ROOTFS_DIR/dev/tty c 5 0;
    mknod -m 600 $ROOTFS_DIR/dev/console c 5 1; # ?
    mknod -m 666 $ROOTFS_DIR/dev/ptmx c 5 2;

    # Compulsory links
    ln -sv /proc/self/fd    $ROOTFS_DIR/dev/fd;
    ln -sv /proc/self/fd/0  $ROOTFS_DIR/dev/stdin;
    ln -sv /proc/self/fd/1  $ROOTFS_DIR/dev/stdout;
    ln -sv /proc/self/fd/2  $ROOTFS_DIR/dev/stderr;

    # Recommended links
    ln -sv /proc/kcore  $ROOTFS_DIR/dev/core;

    # mount -vt devpts devpts $ROOTFS_DIR/dev/pts -o gid=5,mode=620;
    # mount -vt proc proc $ROOTFS_DIR/proc;
    # mount -vt sysfs sysfs $ROOTFS_DIR/sys;
    # mount -v --bind /dev $ROOTFS_DIR/dev;
    # mount -vt tmpfs tmpfs $ROOTFS_DIR/run;

}

_apply_rootfs() {

    # TODO bionic-base-amd64.tar

    [ -s $WORK_DIR/.error ] && return $(_err $LINENO 3);

    _create_dev;

    cd $ROOTFS_DIR;
    mkdir -pv \
        etc/{acpi/events,init.d,ssl/certs,skel,sysconfig} \
        home lib media mnt proc sys \
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

    # trim suffix
    local sf sh;
    for sf in $(cd $THIS_DIR/rootfs; find . -type f -name "*.sh");
    do
        sf="$ROOTFS_DIR/${sf#*/}";
        mv "$sf" "${sf%.*}";
        # chmod
    done

    # executable
    chmod +x $ROOTFS_DIR/init;
    find $ROOTFS_DIR/usr/local/{,s}bin $ROOTFS_DIR/etc/init.d -type f -exec chmod -c +x '{}' +

    # copy timezone
    cp -vL /usr/share/zoneinfo/UTC $ROOTFS_DIR/etc/localtime;

    # initrd.img
    ln -fsv bin/busybox $ROOTFS_DIR/linuxrc;

    # subversion
    ln -fsv /var/subversion/bin/svn         $ROOTFS_DIR/usr/bin/;
    ln -fsv /var/subversion/bin/svnadmin    $ROOTFS_DIR/usr/bin/;
    ln -fsv /var/subversion/bin/svnlook     $ROOTFS_DIR/usr/bin/;

    # http://www.linuxfromscratch.org/lfs/view/stable/chapter06/revisedchroot.html
    # drop passwd: /usr/bin/passwd -> /bin/busybox.suid
    rm -frv \
        $ROOTFS_DIR/usr/bin/passwd \
        $ROOTFS_DIR/etc/ssl/man \
        $ROOTFS_DIR/usr/{,local/}include \
        $ROOTFS_DIR/usr/{,local/}share/{info,man,doc} \
        $ROOTFS_DIR/{,usr/}lib/lib{bz2,com_err,e2p,ext2fs,ss,ltdl,fl,fl_pic,z,bfd,opcodes}.a

    find $ROOTFS_DIR/{,usr/}lib -name \*.la -delete;

    # http://www.linuxfromscratch.org/lfs/view/stable/chapter05/stripping.html
    # http://www.linuxfromscratch.org/lfs/view/stable/chapter06/strippingagain.html
    # Take care not to use '--strip-unneeded' on the libraries
    strip --strip-debug $ROOTFS_DIR/lib/*;
    strip --strip-unneeded $ROOTFS_DIR/{,usr/}{,s}bin/*; # --strip-all

}
