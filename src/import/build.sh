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
    # The post kernel build process
    # Install the kernel modules in $ROOTFS
    make INSTALL_MOD_PATH=$ROOTFS modules_install firmware_install || return $(_err_line $((LINENO / 2)));

    # remove empty link
    rm -fv $ROOTFS/lib/modules/${kernel_version}-tc/{build,source};

    echo " --------- bzImage -> vmlinuz64 -------------------";
    _hash ./arch/x86/boot/bzImage;

    # ./arch/x86_64/boot/bzImage -> ../../x86/boot/bzImage
    mv -v ./arch/x86/boot/bzImage $TMP/iso/boot/vmlinuz64;
    # rm -fr $TMP/linux-$kernel_version # clear
}

# http://www.linuxfromscratch.org/lfs/view/stable/chapter06/glibc.html
_make_glibc() {
    local args;
    # http://www.linuxfromscratch.org/lfs/view/stable/chapter05/linux-headers.html
    cd $TMP/linux-$kernel_version && {
        echo " ----------- install headers ----------------------";
        make mrproper;
        make INSTALL_HDR_PATH=$TMP/headers headers_install || return $(_err_line $((LINENO / 2)));
        args="--with-headers=$TMP/headers/include"
    };

    _wait_file $TMP/glibc.tar.xz.lock || return $(_err_line $((LINENO / 2)));
    _try_patch glibc-$glibc_version;
    mkdir -p build $ROOTFS/etc;
    touch $ROOTFS/etc/ld.so.conf;
    cd build;

    # fix glibc cannot be compiled without optimization
    printf "CFLAGS += -mtune=generic -Og -pipe\n" > ./configparms;
    ../configure \
        --prefix=/usr \
        --libexecdir=/usr/lib/glibc \
        --enable-kernel=4.2.9 \
        --enable-stack-protector=strong \
        --enable-obsolete-rpc  \
        --disable-werror \
        libc_cv_slibdir=/lib $args || return $(_err_line $((LINENO / 2)));

    sed -i 's/-O2//g' ./config.make ./config.status;

    make && make install_root=$ROOTFS install;
    ln -sT lib $ROOTFS/lib64;

    printf %s '/usr/local/lib
' | tee $ROOTFS/etc/ld.so.conf;

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
    local symbolic target CFLAGS LDFLAGS;
    _wait_file $TMP/busybox.tar.bz2.lock || return $(_err_line $((LINENO / 2)));

    _try_patch busybox-$busybox_version;
    export LDFLAGS="-L $ROOTFS/lib" CFLAGS="-I $ROOTFS/usr/include";

    cp -v $THIS_DIR/config/busybox_suid.cfg ./.config;
    make || return $(_err_line $((LINENO / 2)));

    while read symbolic target
    do
        symbolic=${symbolic//\/\//\/};
        printf "relink: '${symbolic##*/}'.\n";
        rm -f $symbolic && ln -fs $target.suid $symbolic
    done <<< $(make CONFIG_PREFIX=$ROOTFS install | grep '\->' | awk '{print $1" "$3}');

    mv $ROOTFS/bin/busybox $ROOTFS/bin/busybox.suid;

    cp -v $THIS_DIR/config/busybox_nosuid.cfg ./.config;
    make && make CONFIG_PREFIX=$ROOTFS install || \
        return $(_err_line $((LINENO / 2)));

    # rm -fr $TMP/busybox-$busybox_version # clear
}

_make_zlib() {
    _wait_file $TMP/zlib.tar.gz.lock || return $(_err_line $((LINENO / 2)));

    _try_patch zlib-$zlib_version;
    ./configure --prefix=/usr --shared && \
        make && make install || return $(_err_line $((LINENO / 2)));

    cp -adv /usr/lib/libz.so* $ROOTFS/lib;
    ln -sfv ../../lib/$(readlink /usr/lib/libz.so) $ROOTFS/usr/lib/libz.so;
    # rm -fr $TMP/zlib-$zlib_version # clear
}

_make_openssl() {
    _wait_file $TMP/openssl.tar.gz.lock || return $(_err_line $((LINENO / 2)));

    _try_patch openssl-$OPENSSL_VERSION;
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
    _wait_file $TMP/archive.tar.bz2.lock || return $(_err_line $((LINENO / 2)));
    mkdir -p $ROOTFS/tmp $ROOTFS/usr/share/ca-certificates;

    cd $TMP/ca-certificates-*;
    cp $TMP/certdata.txt ./mozilla/;
    make && make DESTDIR=$ROOTFS install || return $(_err_line $((LINENO / 2)));
    touch $ROOTFS/etc/ca-certificates.conf;
    # find $ROOTFS/usr/share/ca-certificates/mozilla -type f | sed 's/.*mozilla/mozilla/g' | \
    #     tee $ROOTFS/etc/ca-certificates.conf;

}

_make_openssh() {
    _wait_file $TMP/openssh.tar.gz.lock || return $(_err_line $((LINENO / 2)));

    _try_patch openssh-$openssh_version;
    ./configure \
        --prefix=/usr \
        --localstatedir=/var \
        --sysconfdir=/etc/ssh \
        --libexecdir=/lib/openssh \
        --with-ssl-dir=$ROOTFS/usr \
        --with-openssl=$ROOTFS/usr \
        --with-privsep-path=/var/lib/sshd \
        --with-privsep-user=nobody \
        --with-xauth=/bin/xauth \
        --with-md5-passwords || return $(_err_line $((LINENO / 2)));

    sed -i 's/-g -O2//g' ./Makefile;

    make && make DESTDIR=$ROOTFS install || return $(_err_line $((LINENO / 2)));

    # _wait_file $TMP/dropbear.tar.bz2.lock || return $(_err_line $((LINENO / 2)));

    # _try_patch dropbear-$dropbear_version;
    # mkdir -p $ROOTFS/usr/local;

    # ./configure --prefix=$ROOTFS/usr/local && \
    #     make STATIC=1 PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" && \
    #     make PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" install;

    # rm -fr $TMP/dropbear-$dropbear_version # clear
}

_make_libcap2() {
    echo " ------------- make libcap2 -----------------------";
    _wait_file $TMP/libcap.tar.xz.lock || return $(_err_line $((LINENO / 2)));

    _try_patch libcap-$libcap2_version;
    mkdir -p output;
    sed -i 's/LIBATTR := yes/LIBATTR := no/' Make.Rules;
    make && make prefix=`pwd`/output install || return $(_err_line $((LINENO / 2)));
    mkdir -p $ROOTFS/usr/local/lib;
    cp -av `pwd`/output/lib64/* $ROOTFS/usr/local/lib;
    # rm -fr $TMP/libcap-$libcap2_version # clear
}

_make_sshfs() {
    _wait_file $TMP/sshfs-fuse.tar.bz2.lock || return $(_err_line $((LINENO / 2)));

    _try_patch sshfs-fuse-$sshfs_fuse_version;
    ./configure \
        --prefix=$ROOTFS/usr/local \
        --localstatedir=/var || return $(_err_line $((LINENO / 2)));

    sed -i 's/-g -O2//g' ./Makefile;

    make && make install || return $(_err_line $((LINENO / 2)));

}

# TODO _nftables
_make_iptables() {
    _wait_file $TMP/iptables.tar.bz2.lock || return $(_err_line $((LINENO / 2)));

    _try_patch iptables-$iptables_version;
    # Error: No suitable 'libmnl' found: --disable-nftables
    ./configure \
        --prefix=/usr/local \
        --disable-static \
        --localstatedir=/var \
        --enable-libipq \
        --disable-nftables;

    sed -i 's/-O2/ /g' ./Makefile;

    make -j $CORES && make install || return $(_err_line $((LINENO / 2)));

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

    _try_patch mdadm-$mdadm_version;
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

    _try_patch LVM$lvm2_version;
    ./configure \
        --prefix=$ROOTFS/usr/local \
        --localstatedir=/var \
        --sysconfdir=/usr/local/etc \
        --with-confdir=/usr/local/etc \
        --enable-applib \
        --enable-cmdlib \
        --enable-pkgconfig \
        --enable-udev_sync || return $(_err_line $((LINENO / 2)));

    sed -i 's/-O2/ /g' ./make.tmpl;

    # Edit make.tmpl
    # DEFAULT_SYS_DIR = /usr/local/etc/lvm

    make && make install || return $(_err_line $((LINENO / 2)));

    # rm -fr $TMP/LVM$lvm2_version # clear
}

_make_curl() {
    _wait_file $TMP/curl.tar.xz.lock || return $(_err_line $((LINENO / 2)));

    _try_patch curl-$curl_version;
    ./configure \
        --prefix=$ROOTFS/usr/local \
        --disable-shared \
        --enable-static \
        --enable-threaded-resolver \
        --with-ca-bundle=/usr/local/etc/ssl/certs/ca-certificates.crt || return $(_err_line $((LINENO / 2)));

    sed -i 's/-O2/ /g' ./Makefile;

    make && make install || return $(_err_line $((LINENO / 2)));

    # rm -fr $TMP/curl-$curl_version # clear
}

_make_git() {
    _wait_file $TMP/git.tar.xz.lock || return $(_err_line $((LINENO / 2)));

    _try_patch git-$git_version;
    ./configure \
        --prefix=$ROOTFS/usr/local \
        --libexecdir=/usr/local/lib \
        --with-gitconfig=$ROOTFS/usr/local/etc/gitconfig || return $(_err_line $((LINENO / 2)));
        # CFLAGS="${CFLAGS} -static"

    sed -i 's/-g -O2/ /g' ./Makefile ./config.mak.autogen;

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

    # remove glibc include
    rm -fr $ROOTFS/usr/include;

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
    rm -fr $ROOTFS/{,share}/{info,man,doc};
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
