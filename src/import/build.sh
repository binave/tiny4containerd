#!/bin/bash

# [need]: 'bc'
_make_kernel() {
    [ -s $ISO_DIR/boot/vmlinuz64 ] && { printf "[WARN] skip make 'kernel'\n"; return 0; };

    # fix: Directory renamed before its status could be extracted
    _untar $CELLAR_DIR/linux.tar.xz || return $(_err $LINENO 3);
    _try_patch linux-;

    # make ARCH=x86_64 menuconfig # ncurses-dev
    cp -v $THIS_DIR/config/kernel.cfg ./.config;

    # put in queue
    make -j $CORES_COUNT bzImage && make -j $CORES_COUNT modules || return $(_err $LINENO 3)

    # Install the kernel modules in $ROOTFS_DIR
    make INSTALL_MOD_PATH=$ROOTFS_DIR modules_install firmware_install || return $(_err $LINENO 3);

    # remove empty link
    rm -fv $ROOTFS_DIR/lib/modules/[0-9]*-tc/{build,source};

    _hash ./arch/x86/boot/bzImage;

    # ./arch/x86_64/boot/bzImage -> ../../x86/boot/bzImage
    cp -v ./arch/x86/boot/bzImage $ISO_DIR/boot/vmlinuz64

}

_make_libcap2(){
    [ -s $ROOTFS_DIR/usr/lib/libcap.so ] && { printf "[WARN] skip make 'libcap2'\n"; return 0; };

    _wait4 libcap.tar.xz || return $(_err $LINENO 3);
    _try_patch libcap-;

    sed -i '/install.*STALIBNAME/d' Makefile; # Prevent a static library from being installed
    sed -i 's/LIBATTR := yes/LIBATTR := no/' Make.Rules;
    mkdir -pv _install $ROOTFS_DIR/usr/local/lib;

    make && make \
        RAISE_SETFCAP=no \
        lib=lib \
        prefix=$PWD/_install \
        install || return $(_err $LINENO 3);

    cp -adv $PWD/_install/lib64/* $ROOTFS_DIR/usr/local/lib;
    rm -fv $ROOTFS_DIR/usr/local/lib*.a

}

_undep() {
    local dep;
    for dep in $CELLAR_DIR/*.tcz;
    do
        printf "\nundep '${dep##*/}', ";
        _wait4 ${dep##*/} $ROOTFS_DIR || return $(_err $LINENO 3);
    done
    cd $ROOTFS_DIR;

    _hash $CELLAR_DIR/rootfs.gz;

    # Install Tiny Core Linux rootfs
    zcat $CELLAR_DIR/rootfs.gz | cpio -f -i -H newc -d --no-absolute-filenames || \
        return $(_err $LINENO 3)

}


_apply_rootfs(){
    # Copy our custom rootfs,
    cp -frv $THIS_DIR/rootfs/* $ROOTFS_DIR;

    # trim suffix
    local sf sh;
    for sf in $(cd $THIS_DIR/rootfs; find . -type f -name "*.sh");
    do
        [ "${sf#**/}" == "bootsync.sh" ] && continue;
        sf="$ROOTFS_DIR/${sf#*/}";
        mv -f "$sf" "${sf%.*}";
        # chmod
    done

    _modify_config;

    echo "----------- ca-certificates ----------------------";
    # Extract ca-certificates, TCL changed something such that these need to be extracted post-install
    chroot $ROOTFS_DIR sh -xc ' \
        ldconfig \
        && /usr/local/tce.installed/openssl \
        && /usr/local/tce.installed/ca-certificates \
    ' || return $(_err $LINENO 3);

    ln -sTv lib                  $ROOTFS_DIR/lib64;
    ln -sTv ../usr/local/etc/ssl $ROOTFS_DIR/etc/ssl

}

# It builds an image that can be used as an ISO *and* a disk image.
# but read only...
_build_iso() {
    [ -n "$1" ] || {
        printf "\n[WARN] skip create iso.\n";
        return 0
    };

    set ${1##*/};

    echo " ------------- build iso --------------------------";
    cd $ROOTFS_DIR || return $(_err $LINENO 3);

    # create initrd.img
    find | cpio -o -H newc | \
        xz -9 --format=lzma --verbose --verbose --threads=0 --extreme > \
        $ISO_DIR/iso/boot/initrd.img || return $(_err $LINENO 3);

    _hash $ISO_DIR/iso/boot/initrd.img;

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
        $TMP/iso || return $(_err $LINENO 3);

    _hash "$OUT_DIR/$1";

    return 0
}
