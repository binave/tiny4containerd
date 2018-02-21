#!/bin/bash
# functions

_make_kernel() {
    echo " ------------ untar kernel ------------------------";
    local kernel_path=$TMP/linux-$kernel_version;
    # fix: Directory renamed before its status could be extracted
    _untar $TMP/linux.tar.xz || return $(_err_line $((LINENO / 2)));

    echo " -------- make bzImage modules --------------------";
    # make ARCH=x86_64 menuconfig # ncurses-dev
    cp -v $THIS_DIR/kernel.cfg $kernel_path/.config;

    # put in queue
    cd $kernel_path;

    make -j $CORES bzImage && make -j $CORES modules || return $(_err_line $((LINENO / 2)))

    echo " ------- install modules firmware -----------------";
    # The post kernel build process
    # Install the kernel modules in $ROOTFS
    make INSTALL_MOD_PATH=$ROOTFS modules_install firmware_install || return $(_err_line $((LINENO / 2)));

    # remove empty link
    rm -fv $ROOTFS/lib/modules/${kernel_version}-tc/build \
        $ROOTFS/lib/modules/${kernel_version}-tc/source;

    echo " --------- bzImage -> vmlinuz64 -------------------";
    _hash $kernel_path/arch/x86/boot/bzImage;

    # $kernel_path/arch/x86_64/boot/bzImage -> ../../x86/boot/bzImage
    mv -v $kernel_path/arch/x86/boot/bzImage $TMP/iso/boot/vmlinuz64;
    rm -fr $TMP/linux* # clear
}

_make_busybox() {
    _wait_file $TMP/busybox.tar.bz2.lock || return $(_err_line $((LINENO / 2)));

    cp -v $THIS_DIR/busybox.cfg $TMP/busybox-$busybox_version/.config;

    cd $TMP/busybox-$busybox_version;
    make && make install || return $(_err_line $((LINENO / 2)));

    cp -adv _install/* $ROOTFS
}

_make_libcap2() {
    echo " ------------- make libcap2 -----------------------";
    _wait_file $TMP/libcap.tar.xz.lock || return $(_err_line $((LINENO / 2)));

    cd $TMP/libcap-$libcap2_version;
        mkdir -p output;
        sed -i 's/LIBATTR := yes/LIBATTR := no/' Make.Rules;
        make && make prefix=`pwd`/output install || return $(_err_line $((LINENO / 2)));
        mkdir -p $ROOTFS/usr/local/lib;
        cp -av `pwd`/output/lib64/* $ROOTFS/usr/local/lib;
        rm -fr $TMP/libcap* # clear
}

_make_dropbear() {
    _wait_file $TMP/zlib.tar.gz.lock || return $(_err_line $((LINENO / 2)));

    cd $TMP/zlib-$zlib_version;
    ./configure && make && make install || return $(_err_line $((LINENO / 2)));

    _wait_file $TMP/dropbear.tar.bz2.lock || return $(_err_line $((LINENO / 2)));

    cd $TMP/dropbear-$dropbear_version;
    mkdir -p $ROOTFS/usr/local;

    ./configure --prefix=$ROOTFS/usr/local && \
        make STATIC=1 PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" && \
        make PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" install;

    # mkdir $ROOTFS/etc/dropbear;
    # dropbearkey -t rsa -s 1024 -f $ROOTFS/etc/dropbear/dropbear_rsa_host_key;
    # dropbearkey -t dss -f $ROOTFS/etc/dropbear/dropbear_dss_host_key;
}

# TODO _nftables
_make_iptables() {
    _wait_file $TMP/iptables.tar.bz2.lock || return $(_err_line $((LINENO / 2)));

    cd $TMP/iptables-$iptables_version;
    # Error: No suitable 'libmnl' found: --disable-nftables
    ./configure --enable-static --disable-shared --disable-nftables && \
        make -j $CORES LDFLAGS="-all-static" || return $(_err_line $((LINENO / 2)));

    mv -v $TMP/iptables-$iptables_version/iptables/xtables-multi $ROOTFS/usr/local/sbin;

    # Valid subcommands
    local subcommand;
    for subcommand in iptables main4 iptables-save save4 iptables-restore restore4 iptables-xml xml \
                ip6tables main6 ip6tables-save save6 ip6tables-restore restore6;
    do
        ln -fs /usr/local/sbin/xtables-multi    $ROOTFS/usr/local/sbin/$subcommand;
    done
}

_make_mdadm() {
    echo " ------------- make mdadm -----------------------";
    _wait_file $TMP/mdadm.tar.xz.lock || return $(_err_line $((LINENO / 2)));

    cd $TMP/mdadm-$mdadm_version;
    make || return $(_err_line $((LINENO / 2)));
    local md;
    for md in $(make install | awk '{print $6}');
    do
        mkdir -p $ROOTFS${md%/*};
        cp -v $md $ROOTFS$md;
    done
}

_make_lvm2() {
    echo " ------------- lvm2 libcap2 -----------------------";
    _wait_file $TMP/LVM.tgz.lock || return $(_err_line $((LINENO / 2)));

    cd $TMP/LVM$lvm2_version;
    ./configure --prefix=$ROOTFS && make && make install
}

_make_openssl() {
    _wait_file $TMP/openssl.tar.xz.lock || return $(_err_line $((LINENO / 2)));
    cd $TMP/openssl-$openssl_version;
    ./config -fPIC no-shared;
    make
}

_make_curl() {
    _wait_file $TMP/curl.tar.xz.lock || return $(_err_line $((LINENO / 2)));
    cd $TMP/curl-$curl_version;
    ./configure --prefix=$ROOTFS --disable-shared --enable-static && make && make install
    # --without-libidn --without-ssl --without-librtmp --without-gnutls --without-nss --without-libssh2 --without-zlib --without-winidn --disable-rtsp --disable-ldap --disable-ldaps --disable-ipv6
}

# _make_git() {
#     _wait_file $TMP/git.tar.xz.lock || return $(_err_line $((LINENO / 2)));
#     cd $TMP/git-$git_version;
#     ./configure CFLAGS="${CFLAGS} -static" NO_OPENSSL=1 NO_CURL=1;
#     make -j $CORES;
#     make install;
#     make install-doc;
# }

_apply_rootfs() {
    cd $ROOTFS;
    # rm -f linuxrc;

    mkdir -pv dev etc/init.d etc/sysconfig home lib media mnt proc root sys tmp var;

    # find $ROOTFS -type f -exec strip --strip-all {} \;

    # Copy our custom rootfs,
    cp -frv $THIS_DIR/rootfs/* $ROOTFS;

    # trim suffix
    local sf;
    for sf in $(cd $THIS_DIR/rootfs; find . -type f -name "*.sh");
    do
        sf="$ROOTFS/${sf#*/}";
        mv "$sf" "${sf%.*}";
        # chmod
    done

    echo " ----------- ca-certificates ----------------------";
    # Extract ca-certificates, TCL changed something such that these need to be extracted post-install
    chroot $ROOTFS sh -xc ' \
        ldconfig \
        && /usr/local/tce.installed/openssl \
        && /usr/local/tce.installed/ca-certificates \
    ' || return $(_err_line $((LINENO / 2)));

    ln -sT lib $ROOTFS/lib64;
    ln -sT ../usr/local/etc/ssl $ROOTFS/etc/ssl
}

_modify_config() {
    echo " ------------ modify config -----------------------";
    mkdir -p $ROOTFS/usr/local/etc/acpi/events/;
    printf %s 'event=button/power*
action=/sbin/poweroff
' | tee $ROOTFS/usr/local/etc/acpi/events/all;

    # sysctl
    printf %s 'net.ipv4.ip_forward=1
# net.ipv6.conf.all.forwarding=1
' | tee $ROOTFS/etc/sysctl.conf;

    # clean motd
    > $ROOTFS/etc/motd;

    # reset PS1
    sed -i 's/\\w/\\W/g;s/\/apps/\/opt/' $ROOTFS/etc/profile $ROOTFS/etc/skel/.profile;
    printf %s "
sudo /usr/local/sbin/wtmp
export TERM=xterm TMOUT=300
readonly TMOUT
" | tee -a $ROOTFS/etc/profile;


    # unset CMDLINE
    printf "\nunset CMDLINE\n" | tee -a $ROOTFS/etc/init.d/tc-functions >> $ROOTFS/usr/bin/filetool.sh;

    # hide std, fix stderr
    sed -i 's/2>\&1 >\/dev\/null/>\/dev\/null 2>\&1/g;s/chpasswd -m/& 2\>\/dev\/null/g;s/home\*\|noautologin\*\|opt\*\|user\*/# &/' \
        $ROOTFS/etc/init.d/tc-config;

    # password
    sed -i "s/^tc.*//;/# Cmnd alias specification/i\
Cmnd_Alias WRITE_CMDS = /usr/bin/tee /etc/sysconfig/backup, /usr/local/sbin/wtmp\n\
\n" $ROOTFS/etc/sudoers;

    # drop passwd: /usr/bin/passwd -> /bin/busybox.suid
    rm -f $ROOTFS/usr/bin/passwd;

    # fix "su -"
    echo root > $ROOTFS/etc/sysconfig/superuser;

    # add some timezone files so we're explicit about being UTC
    echo 'UTC' | tee $ROOTFS/etc/timezone;
    cp -vL /usr/share/zoneinfo/UTC $ROOTFS/etc/localtime;

    # setup acpi config dir
    # tcl6's sshd is compiled without `/usr/local/sbin` in the path, need `ip`, link it elsewhere
    # Make some handy symlinks (so these things are easier to find), visudo, Subversion link, after /opt/bin in $PATH
    ln -svT /usr/local/etc/acpi     $ROOTFS/etc/acpi;
    ln -svT /usr/local/sbin/ip      $ROOTFS/usr/sbin/ip;
    ln -fs /bin/vi              $ROOTFS/usr/bin/;
    ln -fs /opt/bin/svn         $ROOTFS/usr/bin/;
    ln -fs /opt/bin/svnadmin    $ROOTFS/usr/bin/;
    ln -fs /opt/bin/svnlook     $ROOTFS/usr/bin/;

    # crond
    rm -fr $ROOTFS/var/spool/cron/crontabs;
    ln -fs /opt/tiny/etc/crontabs/  $ROOTFS/var/spool/cron/;

    # move dhcp.sh out of init.d as we're triggering it manually so its ready a bit faster
    cp -v $ROOTFS/etc/init.d/dhcp.sh $ROOTFS/usr/local/etc/init.d;
    echo : | tee $ROOTFS/etc/init.d/dhcp.sh;

    # Make sure init scripts are executable
    find $ROOTFS/usr/local/sbin \
        -type f -exec chmod -c +x '{}' +
}

# It builds an image that can be used as an ISO *and* a disk image.
# but read only...
_build_iso() {
    [ -n "$OUTPUT_PATH" ]|| {
        printf "\n[WARN] skip create iso.\n";
        return 0
    };

    cd $ROOTFS || return $((LINENO / 2));

    # create initrd.img
    find | cpio -o -H newc | \
        xz -9 --format=lzma --verbose --verbose --threads=0 --extreme > \
        $TMP/iso/boot/initrd.img || return $((LINENO / 2));

    _hash $TMP/iso/boot/initrd.img;

    # Note: only "-isohybrid-mbr /..." is specific to xorriso.
    xorriso \
        -publisher "Docker Inc." \
        -as mkisofs -l -J -R -V $LABEL \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -b boot/isolinux/isolinux.bin \
        -c boot/isolinux/boot.cat \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -o "$OUTPUT_PATH" \
        $TMP/iso || return $((LINENO / 2));

    _hash "$OUTPUT_PATH";

    return 0
}

_apt_get_install() {
    # clear work path
    rm -fr /var/lib/apt/lists/*;
    {
        curl -L --connect-timeout 1 http://www.google.com >/dev/null 2>&1 && {
            printf %s "$DEBIAN_SOURCE";
            :
        } || printf %s "$DEBIAN_CN_SOURCE"
    } | tee /etc/apt/sources.list;
    apt-get update && apt-get -y install $APT_GET_LIST_MAKE;

    return $?
}
