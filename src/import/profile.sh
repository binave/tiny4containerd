#!/bin/bash

_create_etc() {
    echo " ------------- create etc -------------------------";

    # glibc default configuration, `ldconfig`
    printf '/usr/lib\n' | tee $ROOTFS/etc/ld.so.conf;

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
' | tee $ROOTFS/etc/nsswitch.conf

    # sysctl
    printf %s 'net.ipv4.ip_forward=1
# net.ipv6.conf.all.forwarding=1
' | tee $ROOTFS/etc/sysctl.conf;

    # fstab
    printf %s '# /etc/fstab
proc            /proc        proc    defaults          0       0
sysfs           /sys         sysfs   defaults          0       0
devpts          /dev/pts     devpts  defaults          0       0
# tmpfs           /dev/shm     tmpfs   defaults          0       0
' | tee $ROOTFS/etc/fstab;

    # group
    printf %s '
root:x:0:
lp:x:7:lp
nogroup:x:65534:
staff:x:50:
' | tee $ROOTFS/etc/group;

    # gshadow
    printf %s '
root:*::
nogroup:!::
staff:!::
floppy:!::tcroot:x:0:0:root:/root:/bin/sh
lp:x:7:7:lp:/var/spool/lpd:/bin/sh
nobody:x:65534:65534:nobody:/nonexistent:/bin/false
' | tee $ROOTFS/etc/gshadow;

    # passwd
    printf %s '
root:x:0:0:root:/root:/bin/sh
lp:x:7:7:lp:/var/spool/lpd:/bin/sh
nobody:x:65534:65534:nobody:/nonexistent:/bin/false
' | tee $ROOTFS/etc/passwd;

    # shadow
    printf %s '
root:*:13525:0:99999:7:::
lp:*:13510:0:99999:7:::
nobody:*:13509:0:99999:7:::
' | tee $ROOTFS/etc/shadow;

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

" | tee $ROOTFS/etc/sudoers;

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
" | tee $ROOTFS/etc/profile;

    # .profile
    printf %s "# ~/.profile: Executed by Bourne-compatible login SHells.
PS1='\u@\h:\W\$ '
PAGER='less -EM'
MANPAGER='less -isR'
EDITOR=vi
FLWM_TITLEBAR_COLOR='58:7D:AA'

export EDITOR FILEMGR FLWM_TITLEBAR_COLOR MANPAGER PAGER PS1

[ -f \$HOME/.ashrc ] && . \$HOME/.ashrc

" | tee $ROOTFS/etc/skel/.profile;

    touch $ROOTFS/etc/{skel/.ashrc,skel/.ash_history,motd};

    # fix "su -"
    echo root > $ROOTFS/etc/sysconfig/superuser;

    # add some timezone files so we're explicit about being UTC
    echo 'UTC' | tee $ROOTFS/etc/timezone;

}

_create_config() {
    echo " ------------ create config -----------------------";
    mkdir $ROOTFS/etc/acpi/events;
    printf %s 'event=button/power*
action=/sbin/poweroff
' | tee $ROOTFS/etc/acpi/events/all;

}
