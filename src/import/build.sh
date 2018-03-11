#!/bin/bash
# functions

_make_kernel() {
    echo " ------------ untar kernel ------------------------";
    # fix: Directory renamed before its status could be extracted
    _untar $TMP/linux.tar.xz || return $(_err_line $((LINENO / 2)));
    _try_patch linux-$kernel_version;

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
_make_glibc() {
    _wait_file $TMP/glibc.tar.xz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch glibc-$glibc_version;

    mkdir -pv build $ROOTFS/etc;
    touch $ROOTFS/etc/ld.so.conf;
    cd build;

    # fix glibc cannot be compiled without optimization
    printf "CFLAGS += -mtune=generic -Og -pipe\n" > ./configparms;
    ../configure \
        --prefix=/usr \
        --libexecdir=/usr/lib/glibc \
        --enable-kernel=4.4.2 \
        --enable-stack-protector=strong \
        --enable-obsolete-rpc  \
        --disable-werror \
        --with-headers=$TMP/kernel-header/include \
        libc_cv_slibdir=/lib || return $(_err_line $((LINENO / 2)));

    sed -i 's/-O2//g' ./config.make ./config.status;
    make && make install_root=$ROOTFS install;

    ln -sT lib $ROOTFS/lib64;
    printf '/usr/local/lib\n' | tee $ROOTFS/etc/ld.so.conf;

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

}

_make_busybox() {
    _wait_file $TMP/busybox.tar.bz2.lock || return $(_err_line $((LINENO / 2)));
    _try_patch busybox-$busybox_version;

    cp -v $THIS_DIR/config/busybox_suid.cfg ./.config;

    # Optional
    local CFLAGS="-I$ROOTFS/usr/include" LDFLAGS="-L$ROOTFS/lib";
    export CFLAGS LDFLAGS;

    make || return $(_err_line $((LINENO / 2)));
    local symbolic target;
    while read symbolic target;
    do
        printf "  $symbolic -> $target.suid\n";
        symbolic=${symbolic//\/\//\/};
        rm -f $symbolic && ln -fs $target.suid $symbolic
    done <<< $(make CONFIG_PREFIX=$ROOTFS install | grep '\->' | awk '{print $1" "$3}');
    mv $ROOTFS/bin/busybox $ROOTFS/bin/busybox.suid;

    make mrproper;
    cp -v $THIS_DIR/config/busybox_nosuid.cfg ./.config;
    make && make CONFIG_PREFIX=$ROOTFS install || \
        return $(_err_line $((LINENO / 2)));

    # rm -fr $TMP/busybox-$busybox_version # clear
}

_make_zlib() {
    _wait_file $TMP/zlib.tar.gz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch zlib-$zlib_version;

    # Optional
    local CFLAGS="-I$ROOTFS/usr/include" LDFLAGS="-L$ROOTFS/lib";
    export CFLAGS LDFLAGS;

    ./configure \
        --prefix=/usr \
        --shared && \
        make && make DESTDIR=$ROOTFS install || return $(_err_line $((LINENO / 2)));

    mv -v $ROOTFS/usr/lib/libz.so.* $ROOTFS/lib;
    ln -sfv ../../lib/$(readlink $ROOTFS/usr/lib/libz.so) $ROOTFS/usr/lib/libz.so
    # rm -fr $TMP/zlib-$zlib_version # clear
}

_make_openssl() {
    _wait_file $TMP/openssl.tar.gz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch openssl-$OPENSSL_VERSION;

    local CFLAGS="-I$ROOTFS/usr/include" LDFLAGS="-L$ROOTFS/lib";
    export CFLAGS LDFLAGS;

    ./config \
        --prefix=/usr \
        --openssldir=/etc/ssl \
        --install_prefix=$ROOTFS \
        shared zlib-dynamic || return $(_err_line $((LINENO / 2)));

    sed -i 's/-O3//g' ./Makefile;
    make && make install || return $(_err_line $((LINENO / 2)));

    # rm -fr $TMP/openssl-$OPENSSL_VERSION # clear
}

# http://www.linuxfromscratch.org/blfs/view/8.1/postlfs/cacerts.html
# http://www.linuxfromscratch.org/blfs/view/stable/postlfs/make-ca.html
_make_ca_certificates() {
    mkdir -pv $ROOTFS/tmp $ROOTFS/usr/share/ca-certificates;
    _wait_file $TMP/archive.tar.bz2.lock || return $(_err_line $((LINENO / 2)));
    cd $TMP/ca-certificates-*;
    cp -v $TMP/certdata.txt ./mozilla/;

    # Optional
    local CFLAGS="-I$ROOTFS/usr/include" LDFLAGS="-L$ROOTFS/lib";
    export CFLAGS LDFLAGS;

    make && make DESTDIR=$ROOTFS install || return $(_err_line $((LINENO / 2)));
    find $ROOTFS/usr/share/ca-certificates/mozilla -type f | sed 's/.*mozilla/mozilla/g' | \
        tee $ROOTFS/etc/ca-certificates.conf;

    # rm -fr

}

_make_openssh() {
    _wait_file $TMP/openssh.tar.gz.lock || return $(_err_line $((LINENO / 2)));
    cd $TMP/openssh-$openssh_version;

    local CFLAGS="-I$ROOTFS/usr/include" LDFLAGS="-L$ROOTFS/lib";
    export CFLAGS LDFLAGS;

    # link 'openssl' lib
    ln -sv $ROOTFS/usr/lib/lib{crypto,ssl}.* /usr/lib;

    ./configure \
        --prefix=/usr \
        --localstatedir=/var \
        --sysconfdir=/etc/ssh \
        --libexecdir=/lib/openssh \
        --with-privsep-path=/var/lib/sshd \
        --with-privsep-user=nobody \
        --with-xauth=/bin/xauth \
        --with-md5-passwords || return $(_err_line $((LINENO / 2)));

    sed -i 's/-g -O2//g' ./Makefile;
    make && make DESTDIR=$ROOTFS install-nokeys || return $(_err_line $((LINENO / 2)));

    # # remove 'openssl' lib
    # rm -f /usr/lib/lib{crypto,ssl}.*;

    echo "PermitRootLogin no" >> $ROOTFS/etc/ssh/sshd_config;

    # mkdir -pv $ROOTFS/dev;
    # mknod -m 666 $ROOTFS/dev/null c 1 3;
    # mknod -m 666 $ROOTFS/dev/zero c 1 5;
    # # fix: PRNG is not seeded
    # mknod -m 666 $ROOTFS/dev/random c 1 8;
    # mknod -m 644 $ROOTFS/dev/urandom c 1 9;
    # ssh-keygen -A;
    # rm -fr $ROOTFS/dev

}

_make_libcap2() {
    echo " ------------- make libcap2 -----------------------";
    _wait_file $TMP/libcap.tar.xz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch libcap-$libcap2_version;

    sed -i '/install.*STALIBNAME/d' Makefile; # Prevent a static library from being installed
    sed -i 's/LIBATTR := yes/LIBATTR := no/' Make.Rules;

    # Optional
    local CFLAGS="-I$ROOTFS/usr/include" LDFLAGS="-L$ROOTFS/lib";
    export CFLAGS LDFLAGS;

    make && make \
        RAISE_SETFCAP=no \
        lib=lib \
        prefix=$ROOTFS/usr \
        install || return $(_err_line $((LINENO / 2)));

    mv -v $ROOTFS/usr/lib/libcap.so.* $ROOTFS/lib;
    ln -sfv ../../lib/$(readlink $ROOTFS/usr/lib/libcap.so) $ROOTFS/usr/lib/libcap.so;

    # rm -fr $TMP/libcap-$libcap2_version # clear
}

# TODO _nftables
_make_iptables() {
    _wait_file $TMP/iptables.tar.bz2.lock || return $(_err_line $((LINENO / 2)));
    _try_patch iptables-$iptables_version;

    # Optional
    local CFLAGS="-I$ROOTFS/usr/include" LDFLAGS="-L$ROOTFS/lib";
    export CFLAGS LDFLAGS;

    # Error: No suitable 'libmnl' found: --disable-nftables
    ./configure \
        --prefix=/usr \
        --sbindir=/sbin \
        --enable-libipq \
        --localstatedir=/var \
        --with-xtlibdir=/lib/xtables \
        --with-kernel=$TMP/linux-$kernel_version \
        --disable-nftables;

    # link 'glibc' lib
    ln -sv $ROOTFS/lib/{libc,ld-linux-x86-64}.so.* /lib;
    ln -sv $ROOTFS/usr/lib/libc_nonshared.a /usr/lib;

    sed -i 's/-O2/ /g' ./Makefile;
    make -j $CORES && make DESTDIR=$ROOTFS install || return $(_err_line $((LINENO / 2)));

    # # remove 'glibc' lib
    # rm -fv /lib/{libc,ld-linux-x86-64}.so.* /usr/lib/libc_nonshared.a;

    local file;
    for file in ip4tc ip6tc ipq iptc xtables;
    do
        mv -v $ROOTFS/usr/lib/lib${file}.so.* $ROOTFS/lib && \
        ln -sfv ../../lib/$(readlink $ROOTFS/usr/lib/lib${file}.so) $ROOTFS/usr/lib/lib${file}.so
    done
    # rm -fr $TMP/iptables-$iptables_version $TMP/linux-$kernel_version # clear
}

# kernel version 4.4.2 or above.
_make_mdadm() {
    echo " ------------- make mdadm -----------------------";
    _wait_file $TMP/mdadm.tar.xz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch mdadm-$mdadm_version;

    # Optional
    local CFLAGS="-I$ROOTFS/usr/include" LDFLAGS="-L$ROOTFS/lib";
    export CFLAGS LDFLAGS;

    make && make DESTDIR=$ROOTFS install || return $(_err_line $((LINENO / 2)));
    # rm -fr $TMP/mdadm-$mdadm_version # clear
}

# for _make_eudev
_make_util_linux() {
    _wait_file $TMP/util.tar.xz.lock || return $(_err_line $((LINENO / 2)));
    cd $TMP/util-linux-$util_linux_version;

    # # link 'glibc' lib
    # ln -sv $ROOTFS/lib/{libc,ld-linux-x86-64}.so.* /lib;
    # ln -sv $ROOTFS/usr/lib/libc_nonshared.a /usr/lib;

    # Optional
    local CFLAGS="-I$ROOTFS/usr/include" LDFLAGS="-L$ROOTFS/lib";
    export CFLAGS LDFLAGS;

    ./configure \
        --prefix=/usr \
        --disable-all-programs \
        --disable-makeinstall-chown \
        --enable-libuuid \
        --enable-libblkid \
        --without-python && \
        make && make DESTDIR=$ROOTFS install || return $(_err_line $((LINENO / 2)));

    # # remove 'glibc' lib
    # rm -fv /lib/{libc,ld-linux-x86-64}.so.* /usr/lib/libc_nonshared.a;

}

# for _make_lvm2
_make_readline() {
    _wait_file $TMP/readline.tar.gz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch readline-$readline_version;

    sed -i '/MV.*old/d' Makefile.in;
    sed -i '/{OLDSUFF}/c:' support/shlib-install;

    # Optional
    local CFLAGS="-I$ROOTFS/usr/include" LDFLAGS="-L$ROOTFS/lib";
    export CFLAGS LDFLAGS;

    ./configure \
        --prefix=/usr \
        --enable-shared && \
        make && make DESTDIR=$ROOTFS install || return $(_err_line $((LINENO / 2)));

    mv -v $ROOTFS/usr/lib/lib{readline,history}.so.* $ROOTFS/lib;
    ln -sfv ../../lib/$(readlink $ROOTFS/usr/lib/libreadline.so) $ROOTFS/usr/lib/libreadline.so;
    ln -sfv ../../lib/$(readlink $ROOTFS/usr/lib/libhistory.so) $ROOTFS/usr/lib/libhistory.so;

}

# for _make_lvm2
_make_eudev() {
    _wait_file $TMP/eudev.tar.gz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch eudev-$eudev_version;

    sed -r -i 's|/usr(/bin/test)|\1|' test/udev-test.pl; # fix a test script
    printf %s "HAVE_BLKID=1
BLKID_LIBS=\"-lblkid\"
BLKID_CFLAGS=\"-I$ROOTFS/usr/include\"
" | tee -a config.cache;

    # Optional
    local CFLAGS="-I$ROOTFS/usr/include" LDFLAGS="-L$ROOTFS/lib";
    export CFLAGS LDFLAGS;

    ./configure \
        --prefix=/usr \
        --bindir=/sbin \
        --sbindir=/sbin \
        --libdir=/usr/lib \
        --sysconfdir=/etc \
        --libexecdir=/lib \
        --with-rootprefix= \
        --with-rootlibdir=/lib \
        --enable-manpages \
        --disable-static \
        --config-cache || return $(_err_line $((LINENO / 2)));

    # link 'util-linux' local
    ln -sv $ROOTFS/lib/lib{blkid,uuid}.so* /lib;
    ln -sv $ROOTFS/usr/lib/lib{blkid,uuid}.so* /usr/lib;

    LIBRARY_PATH=$ROOTFS/lib make && \
        make DESTDIR=$ROOTFS install || \
        return $(_err_line $((LINENO / 2)));

    # rm -fv /lib/lib{blkid,uuid}.so* /usr/lib/lib{blkid,uuid}.so*

}

# for _make_lvm2, need: gettext
_make_xfsprogs() {
    _wait_file $TMP/xfsprogs.tar.xz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch xfsprogs-$xfsprogs_version;

    # Optional
    local CFLAGS="-I$ROOTFS/usr/include" LDFLAGS="-L$ROOTFS/lib";
    export CFLAGS LDFLAGS;

    sed -i 's/-g -O2//g' ./configure;

    # link 'readline' lib
    ln -sv $ROOTFS/lib/lib{readline,history}.so* /lib;
    ln -sv $ROOTFS/usr/lib/lib{readline,history}.so* /usr/lib

    # # link 'eudev' lib
    # ln -sv $ROOTFS/lib/libudev.so* /lib;
    # ln -sv $ROOTFS/usr/lib/libudev.so* /usr/lib;

    # # link 'glibc' lib
    # ln -sv $ROOTFS/lib/lib{m,mvec,pthread}.so.* /lib;
    # ln -sv $ROOTFS/usr/lib/lib{mvec,pthread}_nonshared.a /usr/lib

    # # link 'util-linux' local
    # ln -sv $ROOTFS/lib/lib{blkid,uuid}.so* /lib;
    # ln -sv $ROOTFS/usr/lib/lib{blkid,uuid}.so* /usr/lib;

    make \
        CFLAGS="-I$ROOTFS/usr/include" \
        LDFLAGS="-L$ROOTFS/lib -lncurses" \
        DEBUG=-DNDEBUG \
        INSTALL_USER=root \
        INSTALL_GROUP=root \
        LOCAL_CONFIGURE_OPTIONS="--prefix=/usr \
            --disable-static \
            --localstatedir=/var \
            --enable-readline \
            --enable-lib64=no";

    make DESTDIR=$ROOTFS install;
    make DESTDIR=$ROOTFS install-dev;

}

# kernel version 4.4.2 or above.
_make_lvm2() {
    echo " -------------- make lvm2 -----------------------";
    _wait_file $TMP/LVM.tgz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch LVM$lvm2_version;

    local CFLAGS="-I$ROOTFS/usr/include" LDFLAGS="-L$ROOTFS/lib" \
        UDEV_CFLAGS="-I$ROOTFS/usr/include" UDEV_LIBS="-L$ROOTFS/usr/lib";
    export CFLAGS LDFLAGS UDEV_CFLAGS UDEV_LIBS;

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

_make_sshfs() {
    _wait_file $TMP/sshfs-fuse.tar.bz2.lock || return $(_err_line $((LINENO / 2)));
    _try_patch sshfs-fuse-$sshfs_fuse_version;

    local CFLAGS="-I$ROOTFS/usr/include" LDFLAGS="-L$ROOTFS/lib";
    export CFLAGS LDFLAGS;

    ./configure \
        --prefix=$ROOTFS/usr/local \
        --localstatedir=/var || return $(_err_line $((LINENO / 2)));

    sed -i 's/-g -O2//g' ./Makefile;
    make && make DESTDIR=$ROOTFS install || return $(_err_line $((LINENO / 2)));

}

_make_curl() {
    _wait_file $TMP/curl.tar.xz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch curl-$curl_version;

    local CFLAGS="-I$ROOTFS/usr/include" LDFLAGS="-L$ROOTFS/lib";
    export CFLAGS LDFLAGS;

    ./configure \
        --prefix=/usr \
        --enable-threaded-resolver \
        --with-ca-bundle=/usr/local/etc/ssl/certs/ca-certificates.crt || return $(_err_line $((LINENO / 2)));

    sed -i 's/-O2/ /g' ./Makefile;
    make && make DESTDIR=$ROOTFS install || return $(_err_line $((LINENO / 2)));

    # rm -fr $TMP/curl-$curl_version # clear
}

_make_git() {
    _wait_file $TMP/git.tar.xz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch git-$git_version;

    local CFLAGS="-I$ROOTFS/usr/include" LDFLAGS="-L$ROOTFS/lib";
    export CFLAGS LDFLAGS;

    ./configure \
        --prefix=/usr \
        --libexecdir=/usr/local/lib \
        --with-gitconfig=$ROOTFS/usr/local/etc/gitconfig || return $(_err_line $((LINENO / 2)));

    sed -i 's/-g -O2/ /g' ./Makefile ./config.mak.autogen;
    make PERL_PATH="/usr/local/bin/perl" PYTHON_PATH="/usr/local/bin/python" -j $CORES && \
    make PERL_PATH="/usr/local/bin/perl" PYTHON_PATH="/usr/local/bin/python" make DESTDIR=$ROOTFS install;
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
        etc/{init.d,ssl/certs,skel,sysconfig} \
        home lib media mnt proc root sys tmp \
        usr/{local/etc/acpi/events,sbin,share};
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

    # Make sure init scripts are executable
    find $ROOTFS/usr/local/sbin \
        -type f -exec chmod -c +x '{}' +

    # # ca-certificates
    # cp /etc/ca-certificates.conf            $ROOTFS/etc;
    # cp -adv /etc/ssl/certs                  $ROOTFS/etc/ssl;
    # cp /usr/sbin/update-ca-certificates     $ROOTFS/usr/sbin;
    # cp -frv /usr/share/ca-certificates      $ROOTFS/usr/share;
    # # libc
    # cp /sbin/ldconfig       $ROOTFS/sbin;

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

    # drop passwd: /usr/bin/passwd -> /bin/busybox.suid
    rm -f $ROOTFS/usr/bin/passwd;

    # Extract ca-certificates, TCL changed something such that these need to be extracted post-install
    chroot $ROOTFS sh -xc 'ldconfig && openssl' || return $(_err_line $((LINENO / 2)));

    # ln -sT ../usr/local/etc/ssl $ROOTFS/etc/ssl

    # http://www.linuxfromscratch.org/lfs/view/stable/chapter05/stripping.html
    # http://www.linuxfromscratch.org/lfs/view/stable/chapter06/strippingagain.html
    # Take care not to use '--strip-unneeded' on the libraries
    strip --strip-debug $ROOTFS/lib/*;
    strip --strip-unneeded $ROOTFS/{,usr/}{,s}bin/*; # --strip-all

    rm -fr $ROOTFS/usr/include $ROOTFS/{,share}/{info,man,doc};
    find $ROOTFS/{,usr/}lib -name \*.la -delete

    # http://www.linuxfromscratch.org/lfs/view/stable/chapter06/revisedchroot.html
    rm -f /usr/lib/lib{bz2,com_err,e2p,ext2fs,ss,ltdl,fl,fl_pic,z,bfd,opcodes}.a;

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
