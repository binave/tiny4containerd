#!/bin/bash
# functions

# [need]: bc
_make_kernel() {
    _install bc || return $(_err_line $((LINENO / 2)));

    echo " ------------ untar kernel ------------------------";
    # fix: Directory renamed before its status could be extracted
    _untar $TMP/linux.tar.xz || return $(_err_line $((LINENO / 2)));
    _try_patch linux-;

    echo " -------- make bzImage modules --------------------";
    # make ARCH=x86_64 menuconfig # ncurses-dev
    cp -v $THIS_DIR/config/kernel.cfg ./.config;

    # put in queue
    make -j $CORES bzImage && make -j $CORES modules || return $(_err_line $((LINENO / 2)))

    echo " ------- install modules firmware -----------------";
    # Install the kernel modules in $ROOTFS
    make INSTALL_MOD_PATH=$ROOTFS modules_install firmware_install || return $(_err_line $((LINENO / 2)));

    # remove empty link
    rm -fv $ROOTFS/lib/modules/${kernel_version}-tc/{build,source};

    echo " ----------- install headers ----------------------";
    # http://www.linuxfromscratch.org/lfs/view/stable/chapter05/linux-headers.html
    make INSTALL_HDR_PATH=$TMP/kernel-header headers_install || return $(_err_line $((LINENO / 2)));

    echo " --------- bzImage -> vmlinuz64 -------------------";
    _hash ./arch/x86/boot/bzImage;

    # ./arch/x86_64/boot/bzImage -> ../../x86/boot/bzImage
    cp -v ./arch/x86/boot/bzImage $TMP/iso/boot/vmlinuz64

}

# http://www.linuxfromscratch.org/lfs/view/stable/chapter06/glibc.html
# [need]: bison, gawk
_make_glibc() {
    _install bison gawk || return $(_err_line $((LINENO / 2)));

    _wait_file $TMP/glibc.tar.xz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch glibc-;

    mkdir -pv _build $ROOTFS/etc;
    touch $ROOTFS/etc/ld.so.conf;
    cd _build;

    # fix glibc cannot be compiled without optimization
    printf "CFLAGS += -mtune=generic -Og -pipe\n" > ./configparms;
    ../configure \
        --prefix=/usr \
        --enable-kernel=4.4.2 \
        --enable-stack-protector=strong \
        --enable-obsolete-rpc  \
        --disable-werror \
        --with-headers=$TMP/kernel-header/include \
        libc_cv_slibdir=/lib || return $(_err_line $((LINENO / 2)));

    sed -i 's/-O2//g' ./config.make ./config.status;
    make && make install_root=$ROOTFS install;

    ln -sT lib $ROOTFS/lib64

}

_make_busybox() {
    _wait_file $TMP/busybox.tar.bz2.lock || return $(_err_line $((LINENO / 2)));
    _try_patch busybox-;

    cp -v $THIS_DIR/config/busybox_suid.cfg ./.config;

    make || return $(_err_line $((LINENO / 2)));
    local symbolic target;
    while read symbolic target;
    do
        printf "  $symbolic -> $target.suid\n";
        symbolic=${symbolic//\/\//\/};
        rm -f $symbolic && ln -fs $target.suid $symbolic
    done <<< $(make CONFIG_PREFIX=$ROOTFS install | grep '\->' | awk '{print $1" "$3}');
    mv -v $ROOTFS/bin/busybox $ROOTFS/bin/busybox.suid;

    make mrproper;
    cp -v $THIS_DIR/config/busybox_nosuid.cfg ./.config;
    make && make CONFIG_PREFIX=$ROOTFS install || \
        return $(_err_line $((LINENO / 2)));

    # rm -fr $TMP/busybox-$busybox_version # clear
}

# for openssl build, openssh runtime
__make_zlib() {
    _wait_file $TMP/zlib.tar.gz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch zlib-;

    ./configure \
        --prefix=/usr \
        --shared && \
        make && make install || return $(_err_line $((LINENO / 2)));

    cp -adv /usr/lib/libz.so* $ROOTFS/usr/lib;
    mv -v $ROOTFS/usr/lib/libz.so.* $ROOTFS/lib;
    ln -sfv ../../lib/$(readlink $ROOTFS/usr/lib/libz.so) $ROOTFS/usr/lib/libz.so
    # rm -fr $TMP/zlib-$zlib_version # clear
}

# [need]: zlib
_make_openssl() {
    _wait_file $TMP/openssl.tar.gz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch openssl-;

    ./config \
        --prefix=/usr \
        --openssldir=/etc/ssl \
        --install_prefix=$ROOTFS \
        shared zlib-dynamic || return $(_err_line $((LINENO / 2)));

    sed -i 's/-O3//g' ./Makefile;
    make && make install || return $(_err_line $((LINENO / 2)));

    # for openssh build
    cp -adv $ROOTFS/usr/include/openssl /usr/include;

    # rm -fr $TMP/openssl-$OPENSSL_VERSION # clear
}

# http://www.linuxfromscratch.org/blfs/view/8.1/postlfs/cacerts.html
# http://www.linuxfromscratch.org/blfs/view/stable/postlfs/make-ca.html
# [need]: python build
_make_ca_certificates() {
    _install python || return $(_err_line $((LINENO / 2)));

    mkdir -pv $ROOTFS/tmp $ROOTFS/usr/share/ca-certificates;
    _wait_file $TMP/archive.tar.bz2.lock || return $(_err_line $((LINENO / 2)));
    _try_patch ca-certificates-;
    cp -v $TMP/certdata.txt ./mozilla/;

    make && make DESTDIR=$ROOTFS install || return $(_err_line $((LINENO / 2)));
    find $ROOTFS/usr/share/ca-certificates/mozilla -type f | sed 's/.*mozilla/mozilla/g' | \
        tee $ROOTFS/etc/ca-certificates.conf;

    # rm -fr

}

# [need]: zlib
_make_openssh() {
    _wait_file $TMP/openssh.tar.gz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch openssh- openssl-$OPENSSL_VERSION; # e.g. openssh-7.6p1-openssl-1.1.0-1.patch

    # link 'openssl' lib
    ln -sv $ROOTFS/usr/lib/lib{crypto,ssl}.* /usr/lib;

    ./configure \
        --prefix=/usr \
        --localstatedir=/var \
        --sysconfdir=/etc/ssh \
        --with-privsep-path=/var/lib/sshd \
        --with-privsep-user=nobody \
        --with-xauth=/bin/xauth \
        --with-md5-passwords || return $(_err_line $((LINENO / 2)));

    sed -i 's/-g -O2//g' ./Makefile;
    make && make DESTDIR=$ROOTFS install-nokeys || return $(_err_line $((LINENO / 2)));

    # unlink 'openssl' lib
    rm -fv /usr/lib/lib{crypto,ssl}.*;

    echo "PermitRootLogin no" >> $ROOTFS/etc/ssh/sshd_config

}

# TODO _nftables
_make_iptables() {
    _wait_file $TMP/iptables.tar.bz2.lock || return $(_err_line $((LINENO / 2)));
    _try_patch iptables-;

    # Error: No suitable 'libmnl' found: --disable-nftables
    ./configure \
        --prefix=/usr \
        --sbindir=/sbin \
        --enable-libipq \
        --enable-shared \
        --localstatedir=/var \
        --with-xtlibdir=/lib/xtables \
        --with-kernel=$TMP/linux-$kernel_version \
        --disable-nftables;
    sed -i 's/-O2/ /g' ./Makefile;

    # link 'glibc' lib
    ln -sv $ROOTFS/lib/{libc,ld-linux-x86-64}.so.* /lib;
    ln -sv $ROOTFS/usr/lib/libc_nonshared.a /usr/lib;

    make -j $CORES && make DESTDIR=$ROOTFS install || return $(_err_line $((LINENO / 2)));

    local file;
    for file in ip4tc ip6tc ipq iptc xtables;
    do
        mv -v $ROOTFS/usr/lib/lib${file}.so.* $ROOTFS/lib && \
        ln -sfv ../../lib/$(readlink $ROOTFS/usr/lib/lib${file}.so) $ROOTFS/usr/lib/lib${file}.so
    done

    # unlink 'glibc' lib
    rm -fv /lib/{libc,ld-linux-x86-64}.so.* /usr/lib/libc_nonshared.a;

    # rm -fr $TMP/iptables-$iptables_version $TMP/linux-$kernel_version # clear
}

# kernel version 4.4.2 or above.
_make_mdadm() {
    echo " ------------- make mdadm -----------------------";
    _wait_file $TMP/mdadm.tar.xz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch mdadm-;

    make && make DESTDIR=$ROOTFS install || return $(_err_line $((LINENO / 2)));
    # rm -fr $TMP/mdadm-$mdadm_version # clear
}

# for _make_eudev
__make_util_linux() {
    _wait_file $TMP/util.tar.xz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch util-linux-;

    ./configure \
        --prefix=/usr \
        --disable-all-programs \
        --disable-makeinstall-chown \
        --enable-libuuid \
        --enable-libblkid \
        --without-python && \
        make && make install || return $(_err_line $((LINENO / 2)));

    # for lvm2 runtime
    cp -adv /usr/lib/lib{blkid,uuid}.so* $ROOTFS/usr/lib;
    cp -adv /lib/lib{blkid,uuid}.so* $ROOTFS/lib

}

# http://linuxfromscratch.org/lfs/view/stable/chapter06/eudev.html
# for _make_lvm2, [need]: gperf, util-linux
_make_eudev() {
    _install gperf || return $(_err_line $((LINENO / 2)));

    _wait_file $TMP/eudev.tar.gz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch eudev-;

    sed -r -i 's|/usr(/bin/test)|\1|' test/udev-test.pl; # fix a test script
    printf %s "HAVE_BLKID=1
BLKID_LIBS=\"-lblkid\"
BLKID_CFLAGS=\"-I/usr/include\"
" | tee -a config.cache;

    ./configure \
        --prefix=/usr \
        --bindir=/sbin \
        --sbindir=/sbin \
        --libdir=/usr/lib \
        --sysconfdir=/etc \
        --with-rootprefix= \
        --with-rootlibdir=/lib \
        --enable-manpages \
        --disable-static \
        --config-cache || return $(_err_line $((LINENO / 2)));

    make && make DESTDIR=$ROOTFS install && make install || return $(_err_line $((LINENO / 2)))

}

# http://linuxfromscratch.org/blfs/view/stable/postlfs/lvm2.html
# kernel version 4.4.2 or above. [need]: pkg-config, udev
_make_lvm2() {
    _install pkg-config || return $(_err_line $((LINENO / 2)));

    echo " -------------- make lvm2 -----------------------";
    _wait_file $TMP/LVM.tgz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch LVM2;

    ./configure \
        --prefix=/usr \
        --localstatedir=/var \
        --sysconfdir=/etc \
        --with-confdir=/etc \
        --enable-applib \
        --enable-cmdlib \
        --enable-pkgconfig \
        --enable-udev_sync || return $(_err_line $((LINENO / 2)));

    sed -i 's/-O2/ /g' ./make.tmpl;
    make && make DESTDIR=$ROOTFS install || return $(_err_line $((LINENO / 2)))

    # rm -fr $TMP/LVM$lvm2_version # clear
}

# for _make_fuse _make_sshfs
_build_meson() {
    _install re2c || return $(_err_line $((LINENO / 2)));

    cd $TMP/ninja-release && ./configure.py --bootstrap || return $(_err_line $((LINENO / 2)));
    cp -v ./ninja /usr/bin;

    _install python3 || return $(_err_line $((LINENO / 2)));

    cd $TMP/meson-master && python3 ./setup.py install || return $(_err_line $((LINENO / 2)))

}

# for _make_sshfs build, [need]: ninja, meson, udev
_make_fuse() {
    local DESTDIR;
    _wait_file $TMP/fuse.tar.gz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch libfuse-;

    mkdir -pv _build;
    cd _build;
    meson --prefix=/usr .. || return $(_err_line $((LINENO / 2)));

    ninja install && DESTDIR=$ROOTFS ninja install || return $(_err_line $((LINENO / 2)))

    # uninstall 'util-linux' 'eudev'
    cd $TMP/util-linux-* && make uninstall;
    cd $TMP/eudev-* && make uninstall

}

# for __make_glib, [need]: libbz2-dev libreadline-dev
__make_pcre() {
    _install libbz2-dev libreadline-dev || return $(_err_line $((LINENO / 2)));

    _wait_file $TMP/pcre.tar.bz2.lock || return $(_err_line $((LINENO / 2)));
    _try_patch pcre-;
    ./configure \
        --prefix=/usr \
        --docdir=/usr/share/doc/pcre-8.41 \
        --enable-unicode-properties \
        --enable-pcre16 \
        --enable-pcre32 \
        --enable-pcregrep-libz \
        --enable-pcregrep-libbz2 \
        --enable-pcretest-libreadline \
        --enable-shared || return $(_err_line $((LINENO / 2)));

    make && make install || return $(_err_line $((LINENO / 2)));

    cp -adv /usr/lib/libpcre.so* $ROOTFS/usr/lib;
    mv -v $ROOTFS/usr/lib/libpcre.so.* $ROOTFS/lib;
    ln -sfv ../../lib/$(readlink $ROOTFS/usr/lib/libpcre.so) $ROOTFS/usr/lib/libpcre.so

}

# for _make_sshfs runtime, [need]: zlib, libffi-dev, gettext
__make_glib() {
    _install libffi-dev gettext || return $(_err_line $((LINENO / 2)));

    _wait_file $TMP/glib.tar.xz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch glib-;
    ./configure \
        --prefix=/usr \
        --localstatedir=/var \
        --enable-shared \
        --with-pcre=system \
        --disable-libmount || return $(_err_line $((LINENO / 2)));

    sed -i 's/-g -O2//g' ./Makefile;

    # link 'glibc' lib
    ln -sv $ROOTFS/lib/l{d-linux-x86-64,ibpthread,ibc}.so* /lib;
    ln -sv $ROOTFS/usr/lib/lib{c,pthread}_nonshared.a /usr/lib;

    make && make install || return $(_err_line $((LINENO / 2)));

    cp -adv /usr/lib/libglib-* $ROOTFS/usr/lib;

    # unlink 'glibc' lib
    rm -fv /lib/l{d-linux-x86-64,ibpthread,ibc}.so* /usr/lib/lib{c,pthread}_nonshared.a;

    # uninstall 'zlib'
    cd $TMP/zlib-* && make uninstall

}

# http://linuxfromscratch.org/blfs/view/stable/postlfs/sshfs.html
# [need]: fuse, python-docutils
_make_sshfs() {
    _install python-docutils || return $(_err_line $((LINENO / 2)));

    local DESTDIR;
    _wait_file $TMP/sshfs.tar.gz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch sshfs-;

    mkdir -pv _build;
    cd _build;
    meson --prefix=/usr .. || return $(_err_line $((LINENO / 2)));

    DESTDIR=$ROOTFS ninja install || return $(_err_line $((LINENO / 2)));

    mv -v $ROOTFS/usr/lib/x86_64-linux-gnu/* $ROOTFS/lib;
    rm -frv $ROOTFS/usr/lib/x86_64-linux-gnu;

    # uninstall 'pcre', 'glib'
    cd $TMP/pcre-* && make uninstall;
    cd $TMP/glib-* && make uninstall;

}

_make_curl() {
    _wait_file $TMP/curl.tar.xz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch curl-;

    ./configure \
        --prefix=/usr \
        --enable-shared \
        --enable-threaded-resolver \
        --with-ca-path=/etc/ssl/certs || return $(_err_line $((LINENO / 2)));
        # --with-ca-bundle=/usr/local/etc/ssl/certs/ca-certificates.crt || return $(_err_line $((LINENO / 2)));

    sed -i 's/-O2/ /g' ./Makefile;
    make && make DESTDIR=$ROOTFS install || return $(_err_line $((LINENO / 2)));

    mv -v $ROOTFS/usr/local/lib/libcurl* $ROOTFS/usr/lib;

    # relink
    mv -v $ROOTFS/usr/lib/libcurl.so.* $ROOTFS/lib;
    ln -sfv ../../lib/$(readlink $ROOTFS/usr/lib/libcurl.so) $ROOTFS/usr/lib/libcurl.so

    # rm -fr $TMP/curl-$curl_version # clear
}

__make_libcap2() {
    echo " ------------- make libcap2 -----------------------";
    _wait_file $TMP/libcap.tar.xz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch libcap-;

    sed -i '/install.*STALIBNAME/d' Makefile; # Prevent a static library from being installed
    sed -i 's/LIBATTR := yes/LIBATTR := no/' Make.Rules;

    make && make \
        RAISE_SETFCAP=no \
        lib=lib \
        prefix=/usr \
        install || return $(_err_line $((LINENO / 2)));

    cp -adv /usr/lib/libcap.so* $ROOTFS/usr/lib;
    mv -v $ROOTFS/usr/lib/libcap.so.* $ROOTFS/lib;
    ln -sfv ../../lib/$(readlink $ROOTFS/usr/lib/libcap.so) $ROOTFS/usr/lib/libcap.so;

    # rm -fr $TMP/libcap-$libcap2_version # clear
}

_apply_rootfs() {
    cd $ROOTFS;
    mkdir -pv \
        dev \
        etc/{acpi/events,init.d,ssl/certs,skel,sysconfig} \
        home lib media mnt proc root sys tmp \
        usr/{sbin,share};
        # var run

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

    # add executable
    find $ROOTFS/usr/local/{,s}bin -type f -exec chmod -c +x '{}' +

    # copy timezone
    cp -vL /usr/share/zoneinfo/UTC $ROOTFS/etc/localtime;

    # subversion
    ln -fsv /var/subversion/bin/svn         $ROOTFS/usr/bin/;
    ln -fsv /var/subversion/bin/svnadmin    $ROOTFS/usr/bin/;
    ln -fsv /var/subversion/bin/svnlook     $ROOTFS/usr/bin/;

    # http://www.linuxfromscratch.org/lfs/view/stable/chapter06/revisedchroot.html
    # drop passwd: /usr/bin/passwd -> /bin/busybox.suid
    rm -frv \
        $ROOTFS/usr/bin/passwd \
        $ROOTFS/etc/ssl/man \
        $ROOTFS/usr/{,local/}include \
        $ROOTFS/usr/{,local/}share/{info,man,doc} \
        $ROOTFS/{,usr/}lib/lib{bz2,com_err,e2p,ext2fs,ss,ltdl,fl,fl_pic,z,bfd,opcodes}.a

    find $ROOTFS/{,usr/}lib -name \*.la -delete;

    # http://www.linuxfromscratch.org/lfs/view/stable/chapter05/stripping.html
    # http://www.linuxfromscratch.org/lfs/view/stable/chapter06/strippingagain.html
    # Take care not to use '--strip-unneeded' on the libraries
    strip --strip-debug $ROOTFS/lib/*;
    strip --strip-unneeded $ROOTFS/{,usr/}{,s}bin/*; # --strip-all

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
