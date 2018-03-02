#!/bin/bash
# functions

_make_kernel() {
    echo " ------------ untar kernel ------------------------";
    local kernel_path=$TMP/linux-$kernel_version;
    # fix: Directory renamed before its status could be extracted
    _untar $TMP/linux.tar.xz || return $(_err_line $((LINENO / 2)));

    echo " -------- make bzImage modules --------------------";
    # make ARCH=x86_64 menuconfig # ncurses-dev
    cp -v $THIS_DIR/config/kernel.cfg $kernel_path/.config;

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
    # rm -fr $kernel_path # clear
}

_make_busybox() {
    local busybox_path=$TMP/busybox-$busybox_version;
    _wait_file $TMP/busybox.tar.bz2.lock || return $(_err_line $((LINENO / 2)));

    cd $busybox_path;

    patch -Np1 -i $THIS_DIR/patch/busybox-root-path.patch;
    patch -Np1 -i $THIS_DIR/patch/busybox-rpm2cpio.patch;
    patch -Np1 -i $THIS_DIR/patch/busybox-tc-depmod.patch;
    patch -Np1 -i $THIS_DIR/patch/busybox-wget-make-default-timeout-configurable.patch;

    cp -v $THIS_DIR/config/busybox_suid.cfg $busybox_path/.config;
    make && make CONFIG_PREFIX=$ROOTFS install || \
        return $(_err_line $((LINENO / 2)));

    mv $ROOTFS/bin/busybox $ROOTFS/sbin/busybox.suid;

    cp -v $THIS_DIR/config/busybox_nosuid.cfg $busybox_path/.config;
    make && make CONFIG_PREFIX=$ROOTFS install || \
        return $(_err_line $((LINENO / 2)));

    # cp -adv _install/* $ROOTFS;
    # rm -f $ROOTFS/linuxrc;
    # rm -fr $busybox_path # clear
}

_make_glibc() {
    _wait_file $TMP/glibc.tar.xz.lock || return $(_err_line $((LINENO / 2)));
    cd $TMP/glibc-$glibc_version;

    patch -Np1 -i $THIS_DIR/patch/glibc-fhs-1.patch;
    mkdir -p build $ROOTFS/etc;
    cd build;

    echo "CFLAGS += -mtune=generic -Og -pipe" > configparms;
    ../configure \
        --prefix=/usr \
        --libexecdir=/usr/lib/glibc \
        --enable-kernel=4.2.9 \
        --enable-stack-protector=strong \
        libc_cv_slibdir=/lib \
        --enable-obsolete-rpc  \
        --disable-werror;

    find . -name config.make -type f -exec sed -i 's/-O2//g' {} \;
    find . -name config.status -type f -exec sed -i 's/-O2//g' {} \;

    make;
    touch $ROOTFS/etc/ld.so.conf;
    make install install_root=$ROOTFS;

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
    # rm -fr $TMP/libcap-$libcap2_version # clear
}

_make_ssh() {

    # ./configure \
    #     --prefix=$ROOTFS/usr/local \
    #     --localstatedir=/var \
    #     --sysconfdir=/usr/local/etc/ssh \
    #     --libexecdir=/usr/local/lib/openssh \
    #     --with-privsep-path=/var/lib/sshd \
    #     --with-privsep-user=nobody \
    #     --with-xauth=/usr/local/bin/xauth \
    #     --with-md5-passwords || return $(_err_line $((LINENO / 2)));

    # find . -name Makefile -type f -exec sed -i 's/-g -O2//g' {} \;

    # make && make install || return $(_err_line $((LINENO / 2)));

    _wait_file $TMP/zlib.tar.gz.lock || return $(_err_line $((LINENO / 2)));

    cd $TMP/zlib-$zlib_version;
    ./configure && make && make install || return $(_err_line $((LINENO / 2)));

    _wait_file $TMP/dropbear.tar.bz2.lock || return $(_err_line $((LINENO / 2)));

    cd $TMP/dropbear-$dropbear_version;
    mkdir -p $ROOTFS/usr/local;

    ./configure --prefix=$ROOTFS/usr/local && \
        make STATIC=1 PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" && \
        make PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" install;

    # rm -fr $TMP/zlib-$zlib_version $TMP/dropbear-$dropbear_version # clear
}

# http://www.linuxfromscratch.org/blfs/view/7.10-systemd/postlfs/cacerts.html
_make_ca_certificates() {
    _wait_file $TMP/archive.tar.bz2.lock || return $(_err_line $((LINENO / 2)));
    cd  $TMP/ca-certificates-*
    make && make install;
    printf %s 'mozilla/ValiCert_Class_1_VA.crt
mozilla/ValiCert_Class_2_VA.crt
mozilla/Verisign_Class_1_Public_Primary_Certification_Authority.crt
' | tee $ROOTFS/etc/ca-certificates.conf;

}

# https://github.com/wolfSSL/wolfssl/releases
_make_openssl() {
    _wait_file $TMP/openssl.tar.gz.lock || return $(_err_line $((LINENO / 2)));

    cd $TMP/openssl-$OPENSSL_VERSION;

    ./config \
        --install_prefix=$ROOTFS \
        --prefix=$ROOTFS/usr/local \
        --openssldir=$ROOTFS/usr/local/etc/ssl no-shared || return $(_err_line $((LINENO / 2)));

    find . -name Makefile -type f -exec sed -i 's/-O3//g' {} \;

    make && make install || return $(_err_line $((LINENO / 2)));

    # rm -fr $TMP/openssl-$OPENSSL_VERSION # clear
}

_make_sshfs() {
    _wait_file $TMP/sshfs-fuse.tar.bz2.lock || return $(_err_line $((LINENO / 2)));
    cd $TMP/sshfs-fuse-$sshfs_fuse_version;

    ./configure --prefix=$ROOTFS/usr/local --localstatedir=/var || return $(_err_line $((LINENO / 2)));

    find . -name Makefile -type f -exec sed -i 's/-g -O2//g' {} \;

    make && make install || return $(_err_line $((LINENO / 2)));

}

# TODO _nftables
_make_iptables() {
    _wait_file $TMP/iptables.tar.bz2.lock || return $(_err_line $((LINENO / 2)));

    cd $TMP/iptables-$iptables_version;
    # Error: No suitable 'libmnl' found: --disable-nftables
    ./configure --enable-static --disable-shared --disable-nftables;

    find . -name Makefile -type f -exec sed -i 's/-O2/ /g' {} \;

    make -j $CORES LDFLAGS="-all-static" || return $(_err_line $((LINENO / 2)));

    mv -v $TMP/iptables-$iptables_version/iptables/xtables-multi $ROOTFS/usr/local/sbin;

    # Valid subcommands
    local subcommand;
    for subcommand in $($ROOTFS/usr/local/sbin/xtables-multi 2>&1 | grep '\*' | awk '{print $2}');
    do
        ln -fs /usr/local/sbin/xtables-multi    $ROOTFS/usr/local/sbin/$subcommand;
    done

    # rm -fr $TMP/iptables-$iptables_version # clear
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

    # rm -fr $TMP/mdadm-$mdadm_version # clear
}

_make_lvm2() {
    echo " -------------- make lvm2 -----------------------";
    _wait_file $TMP/LVM.tgz.lock || return $(_err_line $((LINENO / 2)));

    cd $TMP/LVM$lvm2_version;

    ./configure \
        --prefix=$ROOTFS/usr/local \
        --localstatedir=/var \
        --sysconfdir=/usr/local/etc \
        --with-confdir=/usr/local/etc \
        --enable-applib \
        --enable-cmdlib \
        --enable-pkgconfig \
        --enable-udev_sync || return $(_err_line $((LINENO / 2)));

    find . -name make.tmpl -type f -exec sed -i 's/-O2/ /g' {} \;

    # Edit make.tmpl
    # DEFAULT_SYS_DIR = /usr/local/etc/lvm

    make && make install || return $(_err_line $((LINENO / 2)));

    # rm -fr $TMP/LVM$lvm2_version # clear
}

_make_curl() {
    _wait_file $TMP/curl.tar.xz.lock || return $(_err_line $((LINENO / 2)));

    cd $TMP/curl-$curl_version;

    ./configure \
        --prefix=$ROOTFS/usr/local \
        --disable-shared \
        --enable-static \
        --enable-threaded-resolver \
        --with-ca-bundle=/usr/local/etc/ssl/certs/ca-certificates.crt || return $(_err_line $((LINENO / 2)));

    find . -name Makefile -type f -exec sed -i 's/-O2/ /g' {} \;

    make && make install || return $(_err_line $((LINENO / 2)));

    # rm -fr $TMP/curl-$curl_version # clear
}

_make_git() {

    _wait_file $TMP/git.tar.xz.lock || return $(_err_line $((LINENO / 2)));
    cd $TMP/git-$git_version;

    ./configure \
        --prefix=$ROOTFS/usr/local \
        --libexecdir=/usr/local/lib \
        --with-gitconfig=$ROOTFS/usr/local/etc/gitconfig || return $(_err_line $((LINENO / 2)));
        # CFLAGS="${CFLAGS} -static"

    find . -name Makefile -type f -exec sed -i 's/-g -O2/ /g' {} \;
    find . -name config.mak.autogen -type f -exec sed -i 's/-g -O2/ /g' {} \;

    make PERL_PATH="/usr/local/bin/perl" PYTHON_PATH="/usr/local/bin/python" -j $CORES && \
    make PERL_PATH="/usr/local/bin/perl" PYTHON_PATH="/usr/local/bin/python" install;
    make install-doc;

    rm -fr $TMP/git-$git_version # clear
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

_apply_rootfs() {
    cd $ROOTFS;
    mkdir -pv \
        dev \
        etc/init.d \
        etc/ssl/certs \
        etc/skel \
        etc/sysconfig \
        home lib media mnt proc root sys tmp \
        usr/local/etc/acpi/events \
        usr/sbin \
        usr/share;
        # var run

    # Copy our custom rootfs,
    cp -frv $THIS_DIR/rootfs/* $ROOTFS;

    # # ca-certificates
    # cp /etc/ca-certificates.conf            $ROOTFS/etc;
    # cp -adv /etc/ssl/certs                  $ROOTFS/etc/ssl;
    # cp /usr/sbin/update-ca-certificates     $ROOTFS/usr/sbin;
    # cp -frv /usr/share/ca-certificates      $ROOTFS/usr/share;

    # libc
    cp /sbin/ldconfig       $ROOTFS/sbin;

    # timezone
    cp -vL /usr/share/zoneinfo/UTC $ROOTFS/etc/localtime;

    # setup acpi config dir
    # tcl6's sshd is compiled without `/usr/local/sbin` in the path, need `ip`, link it elsewhere
    # Make some handy symlinks (so these things are easier to find), visudo, Subversion link, after /opt/bin in $PATH
    ln -svT /usr/local/etc/acpi     $ROOTFS/etc/acpi;
    ln -svT /usr/local/sbin/ip      $ROOTFS/usr/sbin/ip;
    ln -fs  /bin/vi                 $ROOTFS/usr/bin/;

    # subversion
    ln -fs /var/subversion/bin/svn         $ROOTFS/usr/bin/;
    ln -fs /var/subversion/bin/svnadmin    $ROOTFS/usr/bin/;
    ln -fs /var/subversion/bin/svnlook     $ROOTFS/usr/bin/;

    # trim suffix
    local sf;
    for sf in $(cd $THIS_DIR/rootfs; find . -type f -name "*.sh");
    do
        sf="$ROOTFS/${sf#*/}";
        mv "$sf" "${sf%.*}";
        # chmod
    done

    # Make sure init scripts are executable
    find $ROOTFS/usr/local/sbin \
        -type f -exec chmod -c +x '{}' +

    # drop passwd: /usr/bin/passwd -> /bin/busybox.suid
    rm -f $ROOTFS/usr/bin/passwd;

    # Extract ca-certificates, TCL changed something such that these need to be extracted post-install
    chroot $ROOTFS sh -xc 'ldconfig && openssl' || return $(_err_line $((LINENO / 2)));

    ln -sT lib $ROOTFS/lib64;
    # ln -sT ../usr/local/etc/ssl $ROOTFS/etc/ssl

    # find $ROOTFS -type f -exec strip --strip-all {} \;

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

    cp -rv $THIS_DIR/isolinux $TMP/iso/boot/;
    cp -v \
        /usr/lib/ISOLINUX/isolinux.bin \
        /usr/lib/syslinux/modules/bios/ldlinux.c32 \
        $TMP/iso/boot/isolinux/;

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
