#!/bin/bash

_modify_config() {
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

    _mkcfg -$ROOTFS_DIR/init'
#!/bin/sh
exec /sbin/init
';
    chmod +x $ROOTFS_DIR/init;

    # drop passwd: /usr/bin/passwd -> /bin/busybox.suid
    rm -f $ROOTFS_DIR/usr/bin/passwd;

    # fix "su -"
    mkdir -p $ROOTFS_DIR/etc/sysconfig;
    echo root > $ROOTFS_DIR/etc/sysconfig/superuser;

    # add some timezone files so we're explicit about being UTC
    echo 'UTC' | tee $ROOTFS_DIR/etc/timezone;
    cp -vL /usr/share/zoneinfo/UTC $ROOTFS_DIR/etc/localtime;

    # setup acpi config dir
    # tcl6's sshd is compiled without `/usr/local/sbin` in the path, need `ip`, link it elsewhere
    # Make some handy symlinks (so these things are easier to find), visudo, Subversion link, after /opt/bin in $PATH
    ln -svT /usr/local/etc/acpi     $ROOTFS_DIR/etc/acpi;
    ln -svT /usr/local/sbin/ip      $ROOTFS_DIR/usr/sbin/ip;
    ln -fs /bin/vi              $ROOTFS_DIR/usr/bin/;
    ln -fs /opt/bin/svn         $ROOTFS_DIR/usr/bin/;
    ln -fs /opt/bin/svnadmin    $ROOTFS_DIR/usr/bin/;
    ln -fs /opt/bin/svnlook     $ROOTFS_DIR/usr/bin/;

    # crond
    rm -fr $ROOTFS_DIR/var/spool/cron/crontabs;
    ln -fs /opt/tiny/etc/crontabs/  $ROOTFS_DIR/var/spool/cron/;

    # move dhcp.sh out of init.d as we're triggering it manually so its ready a bit faster
    cp -v $ROOTFS_DIR/etc/init.d/dhcp.sh $ROOTFS_DIR/usr/local/etc/init.d;
    echo : | tee $ROOTFS_DIR/etc/init.d/dhcp.sh;

    # Make sure init scripts are executable
    find $ROOTFS_DIR/usr/local/{,s}bin $ROOTFS_DIR/etc/init.d -type f -exec chmod -c +x '{}' +

}
