#!/bin/bash

_modify_config() {
    [ -s $WORK_DIR/.error ] && return 1;

    _mkcfg -$ROOTFS_DIR/etc/fstab'
# /etc/fstab
proc            /proc        proc    defaults          0       0
sysfs           /sys         sysfs   defaults          0       0
devpts          /dev/pts     devpts  defaults          0       0
tmpfs           /dev/shm     tmpfs   defaults          0       0
';

    # acpi http://wiki.tinycorelinux.net/wiki:using_acpid_to_control_your_pc_buttons
    _mkcfg $ROOTFS_DIR/usr/local/etc/acpi/events/all'
event=button/power*
action=/sbin/poweroff
';

    # sysctl
    _mkcfg -$ROOTFS_DIR/etc/sysctl.conf'
net.ipv4.ip_forward=1
# net.ipv6.conf.all.forwarding=1
';

    # clean motd
    > $ROOTFS_DIR/etc/motd;

    # unset CMDLINE
    printf "\nunset CMDLINE\n" | tee -a $ROOTFS_DIR/etc/init.d/tc-functions >> $ROOTFS_DIR/usr/bin/filetool.sh;

    _mkcfg -$ROOTFS_DIR/etc/sudoers"
#
# This file MUST be edited with the 'visudo' command as root.
#

# Host alias specification

# Cmnd alias specification
Cmnd_Alias WRITE_LOG_CMDS = /usr/bin/tee /etc/sysconfig/backup, /usr/local/sbin/wtmp

# User alias specification

# User privilege specification
ALL     ALL=PASSWD: ALL
root    ALL=(ALL) ALL

ALL     ALL=(ALL) NOPASSWD: WRITE_LOG_CMDS

";

    # profile
    _mkcfg -$ROOTFS_DIR/etc/profile"
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
    _mkcfg -$ROOTFS_DIR/etc/skel/.profile"
# ~/.profile: Executed by Bourne-compatible login SHells.

PS1='\u@\h:\W\$ '
PAGER='less -EM'
MANPAGER='less -isR'
EDITOR=vi
FLWM_TITLEBAR_COLOR='58:7D:AA'

export EDITOR FILEMGR FLWM_TITLEBAR_COLOR MANPAGER PAGER PS1

[ -f \$HOME/.ashrc ] && . \$HOME/.ashrc

";

    # drop passwd: /usr/bin/passwd -> /bin/busybox.suid
    rm -fv $ROOTFS_DIR/usr/bin/passwd;

    # fix "su -"
    mkdir -pv $ROOTFS_DIR/etc/sysconfig;
    echo root | tee $ROOTFS_DIR/etc/sysconfig/superuser;

    # add some timezone files so we're explicit about being UTC
    echo 'UTC' | tee $ROOTFS_DIR/etc/timezone;
    cp -Lv /usr/share/zoneinfo/UTC $ROOTFS_DIR/etc/localtime

}

_apply_rootfs(){
    [ -s $WORK_DIR/.error ] && return 1;

    # Copy our custom rootfs,
    echo " ---------- copy custom rootfs --------------------";
    cd $THIS_DIR/rootfs;
    local sf;
    for sf in $(find . -type f);
    do
        sf="${sf#*/}"; # trim './' head
        mkdir -pv "$ROOTFS_DIR/${sf%/*}";
        if [ "${sf##*.}" == "sh" -a "${sf##*/}" != "bootsync.sh" ]; then
            cp -fv "./$sf" "$ROOTFS_DIR/${sf%.*}"
        else
            cp -fv "./$sf" "$ROOTFS_DIR/${sf%/*}"
        fi
    done
    cd $STATE_DIR;


    _mkcfg -$ROOTFS_DIR/init'
#!/bin/sh
if mount -t tmpfs -o size=90% tmpfs /mnt; then
    if tar -C / --exclude=mnt -cf - . | tar -C /mnt/ -xf -; then
        mkdir /mnt/mnt;
        exec /sbin/switch_root mnt /sbin/init
    fi
fi

# https://git.busybox.net/busybox/tree/examples/inittab
exec /sbin/init; # /etc/initta

';

    # Make sure init scripts are executable
    find \
        $ROOTFS_DIR/init\
        $ROOTFS_DIR/usr/local/{,s}bin \
        $ROOTFS_DIR/etc/init.d \
        -type f -exec chmod -c +x '{}' +

}

_add_group() {
    [ -s $WORK_DIR/.error ] && return 1;
    echo " -------------- addgroup --------------------------";
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
