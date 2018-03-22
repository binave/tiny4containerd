#!/bin/bash

_modify_config() {
    # acpi http://wiki.tinycorelinux.net/wiki:using_acpid_to_control_your_pc_buttons
    mkdir -p $ROOTFS_DIR/usr/local/etc/acpi/events/;
    printf %s 'event=button/power*
action=/sbin/poweroff
' | tee $ROOTFS_DIR/usr/local/etc/acpi/events/all;

    # sysctl
    printf %s 'net.ipv4.ip_forward=1
# net.ipv6.conf.all.forwarding=1
' | tee $ROOTFS_DIR/etc/sysctl.conf;

    # clean motd
    > $ROOTFS_DIR/etc/motd;

    # reset PS1
    sed -i 's/\\w/\\W/g;s/\/apps/\/opt/' $ROOTFS_DIR/etc/profile $ROOTFS_DIR/etc/skel/.profile;
    printf %s "
sudo /usr/local/sbin/wtmp
export TERM=xterm TMOUT=300
readonly TMOUT
" | tee -a $ROOTFS_DIR/etc/profile;

    # insert shutdown command
    sed -i ':a;N;$!ba;s/# Sync.*-9 $K5_SKIP/STAMP=`date +%Y%m%d`\
LOG_DIR=\/log\/tiny\/${STAMP:0:6}\
mkdir -p $LOG_DIR\
\n{\n\
    printf "\\n\\n[`date`]\\n"\n\
    # stop container daemon\
    \/usr\/local\/sbin\/containerd stop\n\
    # shutdown script\
    find \/opt\/tiny\/etc\/init.d -type f -perm \/u+x -name "K*.sh" -exec \/bin\/sh -c {} \\\;\n\
    \/usr\/local\/sbin\/wtmp\n\
    # PID USER COMMAND\
    ps -ef | grep "crond\\|monitor\\|ntpd\\|sshd\\|udevd" | awk "{print \\"kill \\"\\$1}" | sh 2>\/dev\/null\
\n} 2>\&1 \| tee -a $LOG_DIR\/shut_$STAMP.log\n\
unset LOG_DIR STAMP\n\
# Sync all filesystems.\
sync; sleep 1; sync; sleep 1\n\
# Unload disk\
\/usr\/local\/sbin\/mdisk destroy\
/;s/apps/opt/g' $ROOTFS_DIR/etc/init.d/rc.shutdown;

    # unset CMDLINE
    printf "\nunset CMDLINE\n" | tee -a $ROOTFS_DIR/etc/init.d/tc-functions >> $ROOTFS_DIR/usr/bin/filetool.sh;

    # hide std, fix stderr
    sed -i 's/2>\&1 >\/dev\/null/>\/dev\/null 2>\&1/g;s/chpasswd -m/& 2\>\/dev\/null/g;s/home\*\|noautologin\*\|opt\*\|user\*/# &/' \
        $ROOTFS_DIR/etc/init.d/tc-config;

    # ln: /usr/local/etc/ssl/cacert.pem: File exists
    # ln: /usr/local/etc/ssl/ca-bundle.crt: File exists
    # $ROOTFS_DIR/usr/local/tce.installed/ca-certificates

    # password
    sed -i "s/^tc.*//;/# Cmnd alias specification/i\
Cmnd_Alias WRITE_CMDS = /usr/bin/tee /etc/sysconfig/backup, /usr/local/sbin/wtmp\n\
\n" $ROOTFS_DIR/etc/sudoers;

    # drop passwd: /usr/bin/passwd -> /bin/busybox.suid
    rm -f $ROOTFS_DIR/usr/bin/passwd;

    # fix "su -"
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
