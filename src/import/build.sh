#!/bin/bash
# functions

# [need]: 'bc'
_make_kernel() {
    [ -s $ISO_DIR/boot/vmlinuz64 -a \
        -d $ROOTFS_DIR/lib/modules/$kernel_version$CONFIG_LOCALVERSION/kernel ] && \
        { printf "[WARN] skip make 'kernel'\n"; return 0; };

    # fix: Directory renamed before its status could be extracted
    _untar $CELLAR_DIR/linux- || return $(_err $LINENO 3);
    _try_patch linux-;

    # make ARCH=x86_64 menuconfig # ncurses-dev
    cp -v $THIS_DIR/config/kernel.cfg ./.config;

    # put in queue
    _ make -j $CORES_COUNT bzImage && _ make -j $CORES_COUNT modules || return $(_err $LINENO 3)

    # Install the kernel modules in $ROOTFS_DIR
    _ make INSTALL_MOD_PATH=$ROOTFS_DIR modules_install firmware_install || return $(_err $LINENO 3);

    # remove empty link
    rm -fv $ROOTFS_DIR/lib/modules/[0-9]*/{build,source};

    # http://www.linuxfromscratch.org/lfs/view/stable/chapter05/linux-headers.html
    _ make INSTALL_HDR_PATH=$WORK_DIR/kernel-header headers_install || return $(_err $LINENO 3);

    _hash ./arch/x86/boot/bzImage;

    # ./arch/x86_64/boot/bzImage -> ../../x86/boot/bzImage
    cp -v ./arch/x86/boot/bzImage $ISO_DIR/boot/vmlinuz64

}

# http://www.linuxfromscratch.org/lfs/view/stable/chapter06/glibc.html
# [need]: 'bison', 'gawk'
_make_glibc() {
    [ -s $ROOTFS_DIR/etc/ld.so.conf ] && { printf "[WARN] skip make 'glibc'\n"; return 0; };

    _wait4 glibc- || return $(_err $LINENO 3);
    _try_patch glibc-;

    mkdir -pv _install $ROOTFS_DIR/etc;
    touch $ROOTFS_DIR/etc/ld.so.conf;
    cd _install;

    # fix 'glibc' cannot be compiled without optimization
    printf "CFLAGS += -mtune=generic -Og -pipe\n" > ./configparms;
    ../configure \
        --prefix=/usr \
        --enable-kernel=4.4.2 \
        --enable-stack-protector=strong \
        --enable-obsolete-rpc  \
        --disable-werror \
        --with-headers=$WORK_DIR/kernel-header/include \
        libc_cv_slibdir=/lib || return $(_err $LINENO 3);

    sed -i 's/-O2//g' ./config.make ./config.status;
    _ make && _ make install_root=$ROOTFS_DIR install;

    mkdir -pv $ROOTFS_DIR/lib64;
    ln -sv ../lib/$(readlink $ROOTFS_DIR/lib/ld-linux-x86-64.so.*) $ROOTFS_DIR/lib64/$(cd $ROOTFS_DIR/lib; ls ld-linux-x86-64.so.*);

    # glibc default configuration, `ldconfig`
    printf '/usr/lib\n' | tee $ROOTFS_DIR/etc/ld.so.conf

}

_make_busybox() {
    [ -s $ROOTFS_DIR/bin/busybox ] && { printf "[WARN] skip make 'busybox'\n"; return 0; };

    _wait4 busybox- || return $(_err $LINENO 3);
    _try_patch busybox-;

    cp -v $THIS_DIR/config/busybox_suid.cfg ./.config;

    _ make || return $(_err $LINENO 3);
    local symbolic target;
    while read symbolic target;
    do
        printf "  $symbolic -> $target.suid\n";
        symbolic=${symbolic//\/\//\/};
        rm -f $symbolic && ln -fs $target.suid $symbolic
    done <<< $(make CONFIG_PREFIX=$ROOTFS_DIR install | grep '\->' | awk '{print $1" "$3}');
    mv -v $ROOTFS_DIR/bin/busybox $ROOTFS_DIR/bin/busybox.suid;

    _ make mrproper;
    cp -v $THIS_DIR/config/busybox_nosuid.cfg ./.config;
    _ make && _ make CONFIG_PREFIX=$ROOTFS_DIR install || \
        return $(_err $LINENO 3);

    # initrd.img
    ln -fsv bin/busybox     $ROOTFS_DIR/linuxrc

}

# for 'openssl' build, 'openssh' runtime
__make_zlib() {
    [ -s $ROOTFS_DIR/usr/lib/libz.so ] && { printf "[WARN] skip make 'zlib'\n"; return 0; };

    _wait4 zlib- || return $(_err $LINENO 3);
    _try_patch zlib-;

    ./configure \
        --prefix=/usr \
        --shared && \
        _ make && _ make install || return $(_err $LINENO 3);

    cp -adv /usr/lib/libz.so* $ROOTFS_DIR/usr/lib;
    mv -v $ROOTFS_DIR/usr/lib/libz.so.* $ROOTFS_DIR/lib;
    ln -sfv ../../lib/$(readlink $ROOTFS_DIR/usr/lib/libz.so) $ROOTFS_DIR/usr/lib/libz.so
}

# [need]: 'zlib', https://wiki.openssl.org/index.php/Compilation_and_Installation
_make_openssl() {
    [ -s $ROOTFS_DIR/usr/bin/openssl ] && { printf "[WARN] skip make 'openssl'\n"; return 0; };

    _wait4 openssl- || return $(_err $LINENO 3);
    _try_patch openssl-;

    ./config \
        --prefix=/usr \
        --openssldir=/etc/ssl \
        shared zlib-dynamic || return $(_err $LINENO 3);

    sed -i 's/-O3//g' ./Makefile;
    _ make && _ make DESTDIR=$ROOTFS_DIR install || return $(_err $LINENO 3);

    # for 'openssh' build
    cp -adv $ROOTFS_DIR/usr/include/openssl /usr/include;
}

# http://www.linuxfromscratch.org/blfs/view/8.1/postlfs/cacerts.html
# http://www.linuxfromscratch.org/blfs/view/stable/postlfs/make-ca.html
# [need]: 'python' build
_make_ca() {
    [ -s $ROOTFS_DIR/etc/ca-certificates.conf ] && { printf "[WARN] skip make 'ca'\n"; return 0; };

    [ -s $WORK_DIR/.error ] && return $(_err $LINENO 3);

    _wait4 ca-certificates-master || return $(_err $LINENO 3);
    cd $CELLAR_DIR/ca-certificates-master;

    mkdir -pv $ROOTFS_DIR/tmp $ROOTFS_DIR/usr/share/ca-certificates;
    cp -v $CELLAR_DIR/certdata.txt ./mozilla/;

    _ make && _ make DESTDIR=$ROOTFS_DIR install || return $(_err $LINENO 3);
    find $ROOTFS_DIR/usr/share/ca-certificates/mozilla -type f | sed 's/.*mozilla/mozilla/g' | \
        tee $ROOTFS_DIR/etc/ca-certificates.conf;

}

# [need]: 'zlib'
_make_openssh() {
    [ -s $ROOTFS_DIR/usr/sbin/sshd ] && { printf "[WARN] skip make 'openssh'\n"; return 0; };

    _wait4 openssh- || return $(_err $LINENO 3);
    _try_patch openssh- openssl-$OPENSSL_VERSION; # e.g. openssh-7.6p1-openssl-1.1.0-1.patch

    # link 'openssl' lib
    ln -sv $ROOTFS_DIR/usr/lib/lib{crypto,ssl}.* /usr/lib;

    ./configure \
        --prefix=/usr \
        --localstatedir=/var \
        --sysconfdir=/etc/ssh \
        --with-privsep-path=/var/lib/sshd \
        --with-privsep-user=nobody \
        --with-xauth=/bin/xauth \
        --with-md5-passwords || return $(_err $LINENO 3);

    sed -i 's/-g -O2//g' ./Makefile;
    _ make && _ make DESTDIR=$ROOTFS_DIR install-nokeys || return $(_err $LINENO 3);

    # unlink 'openssl' lib
    rm -fv /usr/lib/lib{crypto,ssl}.*;

    echo "PermitRootLogin no" >> $ROOTFS_DIR/etc/ssh/sshd_config

}

# TODO _nftables
_make_iptables() {
    [ -s $ROOTFS_DIR/sbin/xtables-multi ] && { printf "[WARN] skip make 'iptables'\n"; return 0; };

    _wait4 iptables- || return $(_err $LINENO 3);
    _try_patch iptables-;

    # Error: No suitable 'libmnl' found: --disable-nftables
    ./configure \
        --prefix=/usr \
        --sbindir=/sbin \
        --enable-libipq \
        --enable-shared \
        --localstatedir=/var \
        --with-xtlibdir=/lib/xtables \
        --with-kernel=$WORK_DIR/linux-[0-9]* \
        --disable-nftables;
    sed -i 's/-O2/ /g' ./Makefile;

    # link 'glibc' lib
    ln -sv $ROOTFS_DIR/lib/{libc,ld-linux-x86-64}.so.* /lib;
    ln -sv $ROOTFS_DIR/usr/lib/libc_nonshared.a /usr/lib;

    _ make -j $CORES_COUNT && _ make DESTDIR=$ROOTFS_DIR install || return $(_err $LINENO 3);

    local file;
    for file in ip4tc ip6tc ipq iptc xtables;
    do
        mv -v $ROOTFS_DIR/usr/lib/lib${file}.so.* $ROOTFS_DIR/lib && \
        ln -sfv ../../lib/$(readlink $ROOTFS_DIR/usr/lib/lib${file}.so) $ROOTFS_DIR/usr/lib/lib${file}.so
    done

    # unlink 'glibc' lib
    rm -fv /lib/{libc,ld-linux-x86-64}.so.* /usr/lib/libc_nonshared.a
}

# kernel version 4.4.2 or above.
_make_mdadm() {
    [ -s $ROOTFS_DIR/sbin/mdadm ] && { printf "[WARN] skip make 'mdadm'\n"; return 0; };

    _wait4 mdadm- || return $(_err $LINENO 3);
    _try_patch mdadm-;

    _ make && _ make DESTDIR=$ROOTFS_DIR install || return $(_err $LINENO 3)
}

# for '_make_eudev'
__make_util_linux() {
    [ -s $ROOTFS_DIR/usr/lib/libuuid.so ] && { printf "[WARN] skip make 'util-linux'\n"; return 0; };

    _wait4 util-linux- || return $(_err $LINENO 3);
    _try_patch util-linux-;

    # --libdir
    ./configure \
        --prefix=/usr \
        --disable-all-programs \
        --disable-makeinstall-chown \
        --enable-kill \
        --enable-libuuid \
        --enable-libblkid \
        --without-python && \
        _ make && _ make install || return $(_err $LINENO 3);

    # for 'lvm2' runtime
    cp -adv /usr/lib/lib{blk,uu}id.so* $ROOTFS_DIR/usr/lib;
    cp -adv /lib/lib{blk,uu}id.so* $ROOTFS_DIR/lib

}

# http://linuxfromscratch.org/lfs/view/stable/chapter06/eudev.html
# for '_make_lvm2', [need]: 'gperf', 'util-linux'
_make_eudev() {
    [ -s $ROOTFS_DIR/sbin/udevd ] && { printf "[WARN] skip make 'eudev'\n"; return 0; };

    _wait4 eudev- || return $(_err $LINENO 3);
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
        --config-cache || return $(_err $LINENO 3);

    _ make && _ make DESTDIR=$ROOTFS_DIR install && _ make install || return $(_err $LINENO 3)

}

# http://linuxfromscratch.org/blfs/view/stable/postlfs/lvm2.html
# kernel version 4.4.2 or above. [need]: 'pkg-config', 'udev'
_make_lvm2() {
    [ -s $ROOTFS_DIR/usr/sbin/lvm ] && { printf "[WARN] skip make 'lvm2'\n"; return 0; };

    _wait4 LVM2 || return $(_err $LINENO 3);
    _try_patch LVM2;

    ./configure \
        --prefix=/usr \
        --localstatedir=/var \
        --sysconfdir=/etc \
        --with-confdir=/etc \
        --enable-applib \
        --enable-cmdlib \
        --enable-pkgconfig \
        --enable-udev_sync || return $(_err $LINENO 3);

    sed -i 's/-O2/ /g' ./make.tmpl;
    _ make && _ make DESTDIR=$ROOTFS_DIR install || return $(_err $LINENO 3)
}

# for '_make_fuse' '_make_sshfs'
_build_meson() {
    [ -s $ROOTFS_DIR/usr/bin/fusermount3 -a -s $ROOTFS_DIR/usr/bin/sshfs ] && \
        { printf "[WARN] skip make 'meson'\n"; return 0; };

    _wait4 ninja-release || return $(_err $LINENO 3);

    cd $CELLAR_DIR/ninja-release && ./configure.py --bootstrap || \
        return $(_err $LINENO 3);
    cp -v ./ninja /usr/bin;

    _wait4 meson-master || return $(_err $LINENO 3);

    cd $CELLAR_DIR/meson-master && _ python3 ./setup.py install || \
        return $(_err $LINENO 3)
}

# for '_make_sshfs' build, [need]: 'ninja', 'meson', 'udev'
_make_fuse() {
    [ -s $ROOTFS_DIR/usr/bin/fusermount3 ] && { printf "[WARN] skip make 'fuse'\n"; return 0; };

    _wait4 fuse- || return $(_err $LINENO 3);
    _try_patch libfuse-;

    mkdir -pv _install; cd _install;
    _ meson --prefix=/usr .. || return $(_err $LINENO 3);

    local DESTDIR;
    _ ninja install && DESTDIR=$ROOTFS_DIR _ ninja install || return $(_err $LINENO 3)

    # uninstall 'util-linux' 'eudev'
    cd $WORK_DIR/util-linux-* && _ make uninstall;
    cd $WORK_DIR/eudev-* && _ make uninstall

}

# for '__make_glib', [need]: 'libbz2-dev' 'libreadline-dev'
__make_pcre() {
    [ -s $ROOTFS_DIR/usr/lib/libpcre.so ] && { printf "[WARN] skip make 'pcre'\n"; return 0; };

    _wait4 pcre- || return $(_err $LINENO 3);
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
        --enable-shared || return $(_err $LINENO 3);

    _ make && _ make install || return $(_err $LINENO 3);

    cp -adv /usr/lib/libpcre.so* $ROOTFS_DIR/usr/lib;
    mv -v $ROOTFS_DIR/usr/lib/libpcre.so.* $ROOTFS_DIR/lib;
    ln -sfv ../../lib/$(readlink $ROOTFS_DIR/usr/lib/libpcre.so) $ROOTFS_DIR/usr/lib/libpcre.so

}

# for '_make_sshfs' runtime, [need]: 'zlib', 'libffi-dev', 'gettext'
__make_glib() {
    [ -s $ROOTFS_DIR/usr/lib/libglib-2.0.so ] && { printf "[WARN] skip make 'glib'\n"; return 0; };

    _wait4 glib- || return $(_err $LINENO 3);
    _try_patch glib-;
    ./configure \
        --prefix=/usr \
        --localstatedir=/var \
        --enable-shared \
        --with-pcre=system \
        --disable-libmount || return $(_err $LINENO 3);

    sed -i 's/-g -O2//g' ./Makefile;

    # link 'glibc' lib
    ln -sv $ROOTFS_DIR/lib/l{d-linux-x86-64,ibpthread,ibc}.so* /lib;
    ln -sv $ROOTFS_DIR/usr/lib/lib{c,pthread}_nonshared.a /usr/lib;

    _ make && _ make install || return $(_err $LINENO 3);

    cp -adv /usr/lib/libglib-* $ROOTFS_DIR/usr/lib;

    # unlink 'glibc' lib
    rm -fv /lib/l{d-linux-x86-64,ibpthread,ibc}.so* /usr/lib/lib{c,pthread}_nonshared.a;

    # uninstall 'zlib'
    cd $WORK_DIR/zlib-* && _ make uninstall

}

# http://linuxfromscratch.org/blfs/view/stable/postlfs/sshfs.html
# [need]: 'fuse', 'python-docutils'
_make_sshfs() {
    [ -s $ROOTFS_DIR/usr/bin/sshfs ] && { printf "[WARN] skip make 'sshfs'\n"; return 0; };

    _wait4 sshfs- || return $(_err $LINENO 3);
    _try_patch sshfs-;

    mkdir -pv _install; cd _install;
    _ meson --prefix=/usr .. || return $(_err $LINENO 3);

    local DESTDIR;
    DESTDIR=$ROOTFS_DIR _ ninja install || return $(_err $LINENO 3);

    mv -v $ROOTFS_DIR/usr/lib/x86_64-linux-gnu/* $ROOTFS_DIR/lib;
    rm -frv $ROOTFS_DIR/usr/lib/x86_64-linux-gnu;

    # uninstall 'pcre', 'glib'
    cd $WORK_DIR/pcre-* && _ make uninstall;
    cd $WORK_DIR/glib-* && _ make uninstall

}

# for docker, [need]: ncurses-dev
_make_procps() {
    [ -s $ROOTFS_DIR/bin/./ps ] && { printf "Skip 'procps'\n"; return 0; };

    _wait4 procps-ng- || return $(_err $LINENO 3);
    _try_patch procps-ng-;

    ./configure \
        --prefix=/usr \
        --exec-prefix= \
        --libdir=/usr/lib \
        --enable-shared \
        --disable-kill && _ make || return $(_err $LINENO 3);

    sed -i -r 's|(pmap_initname)\\\$|\1|' testsuite/pmap.test/pmap.exp;
    sed -i '/set tty/d' testsuite/pkill.test/pkill.exp;
    rm testsuite/pgrep.test/pgrep.exp;

    _ make DESTDIR=$ROOTFS_DIR install || return $(_err $LINENO 3);

    mv -v $ROOTFS_DIR/usr/lib/libprocps.so.* $ROOTFS_DIR/lib;
    ln -sfv ../../lib/$(readlink $ROOTFS_DIR/usr/lib/libprocps.so) $ROOTFS_DIR/usr/lib/libprocps.so

}

# for docker
_make_xz() {
    [ -s $ROOTFS_DIR/bin/xz ] && { printf "Skip 'xz'\n"; return 0; };

    _wait4 xz- || return $(_err $LINENO 3);
    _try_patch xz-;

    ./configure \
        --prefix=/usr \
        --disable-static || return $(_err $LINENO 3);

    _ make && _ make DESTDIR=$ROOTFS_DIR install || return $(_err $LINENO 3);

    mv -v $ROOTFS_DIR/usr/bin/{lzma,unlzma,lzcat,xz,unxz,xzcat} $ROOTFS_DIR/bin;
    mv -v $ROOTFS_DIR/usr/lib/liblzma.so.* $ROOTFS_DIR/lib;
    ln -svf ../../lib/$(readlink $ROOTFS_DIR/usr/lib/liblzma.so) $ROOTFS_DIR/usr/lib/liblzma.so
}

# for docker, http://linuxfromscratch.org/blfs/view/stable/general/git.html
_make_git() {
    [ -s $ROOTFS_DIR/usr/bin/git ] && { printf "[WARN] skip make 'git'\n"; return 0; };

    _wait4 git- || return $(_err $LINENO 3);
    _try_patch git-;

    ./configure \
        --prefix=/usr \
        --with-gitconfig=/etc/gitconfig || return $(_err $LINENO 3);

    sed -i 's/-g -O2/ /g' ./Makefile ./config.mak.autogen;

    _ make && _ make DESTDIR=$ROOTFS_DIR install;

    # # need: asciidoc (man)
    # _ make DESTDIR=$ROOTFS_DIR install-man

}

_make_sudo() {
    [ -s $ROOTFS_DIR/usr/bin/sudo ] && { printf "[WARN] skip make 'sudo'\n"; return 0; };

    _wait4 sudo- || return $(_err $LINENO 3);
    _try_patch sudo-;

    ./configure \
        --prefix=/usr \
        --libexecdir=/usr/lib \
        --with-secure-path \
        --with-all-insults \
        --with-env-editor \
        --with-passprompt="[sudo] password for %p: " || return $(_err $LINENO 3);

    _ make && _ make DESTDIR=$ROOTFS_DIR install || return $(_err $LINENO 3);

    # after build busybox
    ln -fsv $(readlink $ROOTFS_DIR/usr/bin/readlink)    $ROOTFS_DIR/usr/bin/vi

}

_make_e2fsprogs() {
    [ -s $ROOTFS_DIR/sbin/resize2fs ] && { printf "[WARN] skip make 'e2fsprogs'\n"; return 0; };

    _wait4 e2fsprogs- || return $(_err $LINENO 3);
    _try_patch e2fsprogs-;

    mkdir -pv _install; cd _install;

    ../configure \
        --prefix=/usr \
        --bindir=/bin \
        --with-root-prefix="" \
        --enable-elf-shlibs \
        --disable-uuidd && \
        _ make && _ make DESTDIR=$ROOTFS_DIR install || \
        return $(_err $LINENO 3);

}

_make_curl() {
    [ -s $ROOTFS_DIR/usr/bin/curl ] && { printf "[WARN] skip make 'curl'\n"; return 0; };

    _wait4 curl- || return $(_err $LINENO 3);
    _try_patch curl-;

    ./configure \
        --prefix=/usr \
        --enable-shared \
        --enable-threaded-resolver \
        --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt || return $(_err $LINENO 3);

    sed -i 's/-O2/ /g' ./Makefile;
    _ make && _ make DESTDIR=$ROOTFS_DIR install || return $(_err $LINENO 3);

    mv -v $ROOTFS_DIR/usr/local/lib/libcurl* $ROOTFS_DIR/usr/lib;

    # relink
    mv -v $ROOTFS_DIR/usr/lib/libcurl.so.* $ROOTFS_DIR/lib;
    ln -sfv ../../lib/$(readlink $ROOTFS_DIR/usr/lib/libcurl.so) $ROOTFS_DIR/usr/lib/libcurl.so
}

# [need]: expat2-dev
_make_subversion() {
    _wait4 apr-[0-9] || return $(_err $LINENO 3);
    _try_patch apr-[0-9];
    sed -i 's/\$RM "\$cfgfile"/# &/' ./configure
    ./configure \
        --prefix=/usr || return $(_err $LINENO 3);
    _ make && _ make DESTDIR=$OUT_DIR/extapp install;

    # tce-load -wi expat2-dev
    _wait4 apr-util- || return $(_err $LINENO 3);
    _try_patch apr-util-;
    ./configure \
        --prefix=/usr \
        --with-apr=$OUT_DIR/extapp/usr || return $(_err $LINENO 3);
    _ make && _ make DESTDIR=$OUT_DIR/extapp install;

    _wait4 subversion- || return $(_err $LINENO 3);
    _try_patch subversion-;
    unzip $CELLAR_DIR/subversion-*;
    mv -fv sqlite-amalgamation-* sqlite-amalgamation;
    ./configure \
        --prefix=/usr \
        --with-apr=$OUT_DIR/extapp/usr \
        --with-apr-util=$OUT_DIR/extapp/usr || return $(_err $LINENO 3);
    _ make && _ make $OUT_DIR/extapp/usr install;

    ln -fsv /var/subversion/bin/svn         $ROOTFS_DIR/usr/bin/;
    ln -fsv /var/subversion/bin/svnadmin    $ROOTFS_DIR/usr/bin/;
    ln -fsv /var/subversion/bin/svnlook     $ROOTFS_DIR/usr/bin/

}

__make_libcap2() {
    [ -s $ROOTFS_DIR/usr/lib/libcap.so ] && { printf "[WARN] skip make 'libcap2'\n"; return 0; };

    _wait4 libcap- || return $(_err $LINENO 3);
    _try_patch libcap-;

    sed -i '/install.*STALIBNAME/d' Makefile; # Prevent a static library from being installed
    sed -i 's/LIBATTR := yes/LIBATTR := no/' Make.Rules;
    mkdir -pv _install;

    _ make && _ make \
        RAISE_SETFCAP=no \
        lib=lib \
        prefix=$PWD/_install \
        install || return $(_err $LINENO 3);

    cp -adv ./_install/lib/libcap.so* $ROOTFS_DIR/usr/lib;
    mv -v $ROOTFS_DIR/usr/lib/libcap.so.* $ROOTFS_DIR/lib;
    ln -sfv ../../lib/$(readlink $ROOTFS_DIR/usr/lib/libcap.so) $ROOTFS_DIR/usr/lib/libcap.so
}

_refreshe() {
    echo " --------------- refreshe -------------------------";
    # refresh libc cache
    chroot $ROOTFS_DIR ldconfig || return $(_err $LINENO);

    # Generate modules.dep
    find $ROOTFS_DIR/lib/modules -maxdepth 1 -type l -delete; # delete link
    [ "$kernel_version$CONFIG_LOCALVERSION" != "$(uname -r)" ] && \
        ln -sTv $kernel_version$CONFIG_LOCALVERSION $ROOTFS_DIR/lib/modules/`uname -r`;
    chroot $ROOTFS_DIR depmod || return $(_err $LINENO);
    [ "$kernel_version$CONFIG_LOCALVERSION" != "$(uname -r)" ] && \
        rm -v $ROOTFS_DIR/lib/modules/`uname -r`;

    # create sshd key
    chroot $ROOTFS_DIR ssh-keygen -A || return $(_err $LINENO);

}

# It builds an image that can be used as an ISO *and* a disk image.
# but read only...
_build_iso() {
    [ -n "$1" ] || {
        printf "\n[WARN] skip create iso.\n";
        return 0
    };

    set ${1##*/}; # trim path

    echo " ------------- build iso --------------------------";
    cd $ROOTFS_DIR || return $(_err $LINENO 3);

    # create 'initrd.img'
    find | cpio -o -H newc | \
        xz -9 --format=lzma --verbose --verbose --threads=0 --extreme > \
        $ISO_DIR/boot/initrd.img || return $(_err $LINENO 3);

    _hash $ISO_DIR/boot/initrd.img;

    # copy boot file
    cp -rv $THIS_DIR/isolinux $ISO_DIR/boot/;
    cp -v \
        /usr/lib/ISOLINUX/isolinux.bin \
        /usr/lib/syslinux/modules/bios/ldlinux.c32 \
        $ISO_DIR/boot/isolinux/;

    # Note: only "-isohybrid-mbr /..." is specific to xorriso.
    xorriso \
        -publisher "Docker Inc." \
        -as mkisofs -l -J -R -V $LABEL \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -b boot/isolinux/isolinux.bin \
        -c boot/isolinux/boot.cat \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -o "$OUT_DIR/$1" \
        $ISO_DIR || return $(_err $LINENO 3);

    _hash "$OUT_DIR/$1";
    return 0
}
