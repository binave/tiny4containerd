#!/bin/bash

_modify_config() {
    [ -s $WORK_DIR/.error ] && return 1;

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

    # reset PS1
    sed -i 's/\\w/\\W/g;s/\/apps/\/opt/' $ROOTFS_DIR/etc/profile $ROOTFS_DIR/etc/skel/.profile;
    _mkcfg +$ROOTFS_DIR/etc/profile"
sudo /usr/local/sbin/wtmp
export TERM=xterm TMOUT=300
readonly TMOUT
";

    # unset CMDLINE
    printf "\nunset CMDLINE\n" | tee -a $ROOTFS_DIR/etc/init.d/tc-functions >> $ROOTFS_DIR/usr/bin/filetool.sh;

    # hide std, fix stderr
    sed -i 's/2>\&1 >\/dev\/null/>\/dev\/null 2>\&1/g;s/chpasswd -m/& 2\>\/dev\/null/g;s/home\*\|noautologin\*\|opt\*\|user\*/# &/' \
        $ROOTFS_DIR/etc/init.d/tc-config;

    # ln: /usr/local/etc/ssl/cacert.pem: File exists
    # ln: /usr/local/etc/ssl/ca-bundle.crt: File exists
    # $ROOTFS_DIR/usr/local/tce.installed/ca-certificates

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

    # drop passwd: /usr/bin/passwd -> /bin/busybox.suid
    rm -f $ROOTFS_DIR/usr/bin/passwd;

    # fix "su -"
    mkdir -p $ROOTFS_DIR/etc/sysconfig;
    echo root > $ROOTFS_DIR/etc/sysconfig/superuser;

    # add some timezone files so we're explicit about being UTC
    echo 'UTC' | tee $ROOTFS_DIR/etc/timezone;
    cp -vL /usr/share/zoneinfo/UTC $ROOTFS_DIR/etc/localtime

}

_apply_rootfs(){
    [ -s $WORK_DIR/.error ] && return 1;

    # Copy our custom rootfs,
    echo "---------- copy custom rootfs --------------------";
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
exec /sbin/init
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
