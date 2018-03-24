#!/bin/bash

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
    make -j $CORES_COUNT bzImage && make -j $CORES_COUNT modules || return $(_err $LINENO 3)

    # Install the kernel modules in $ROOTFS_DIR
    make INSTALL_MOD_PATH=$ROOTFS_DIR modules_install firmware_install || return $(_err $LINENO 3);

    # remove empty link
    rm -fv $ROOTFS_DIR/lib/modules/[0-9]*/{build,source};

    _hash ./arch/x86/boot/bzImage;

    # ./arch/x86_64/boot/bzImage -> ../../x86/boot/bzImage
    cp -v ./arch/x86/boot/bzImage $ISO_DIR/boot/vmlinuz64

}

_undep() {
    local dep;
    for dep in $CELLAR_DIR/*.tcz;
    do
        _wait4 ${dep##*/} $ROOTFS_DIR || return $(_err $LINENO 3);
    done

    _hash $CELLAR_DIR/rootfs64.gz;
    cd $ROOTFS_DIR;

    # Install Tiny Core Linux rootfs
    zcat $CELLAR_DIR/rootfs64.gz | \
        cpio \
            --nonmatching \
            --verbose \
            --extract \
            --format=newc \
            --make-directories \
            --no-absolute-filenames || return $(_err $LINENO 3)
    # http://www.gnu.org/software/cpio/manual/cpio.html
    # 'newc': The new (SVR4) portable format, which supports file systems having more than 65536 i-nodes.

}

_make_libcap2(){
    [ -s $ROOTFS_DIR/usr/lib/libcap.so ] && { printf "[WARN] skip make 'libcap2'\n"; return 0; };

    _wait4 libcap- || return $(_err $LINENO 3);
    _try_patch libcap-;

    sed -i '/install.*STALIBNAME/d' Makefile; # Prevent a static library from being installed
    sed -i 's/LIBATTR := yes/LIBATTR := no/' Make.Rules;
    mkdir -pv _install $ROOTFS_DIR/usr/local/lib;

    make && make \
        RAISE_SETFCAP=no \
        lib=lib \
        prefix=$PWD/_install \
        install || return $(_err $LINENO 3);

    # cp -adv $PWD/_install/lib64/* $ROOTFS_DIR/usr/local/lib;
    cp -adv ./_install/lib/libcap.so* $ROOTFS_DIR/usr/lib;
    mv -v $ROOTFS_DIR/usr/lib/libcap.so.* $ROOTFS_DIR/lib;
    ln -sfv ../../lib/$(readlink $ROOTFS_DIR/usr/lib/libcap.so) $ROOTFS_DIR/usr/lib/libcap.so;
    rm -fv $ROOTFS_DIR/usr/local/lib*.a

}


_apply_rootfs(){
    [ -s $WORK_DIR/.error ] && return $(_err $LINENO 3);

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

    _modify_config;

    echo "----------- ca-certificates ----------------------";
    # Extract ca-certificates, TCL changed something such that these need to be extracted post-install
    chroot $ROOTFS_DIR sh -xc ' \
        ldconfig \
        && /usr/local/tce.installed/openssl \
        && /usr/local/tce.installed/ca-certificates \
    ' || return $(_err $LINENO 3);

    ln -sTv lib                  $ROOTFS_DIR/lib64;
    ln -sTv ../usr/local/etc/ssl $ROOTFS_DIR/etc/ssl;

    echo "----------- refresh modules ----------------------";
    # Generate modules.dep
    find $ROOTFS_DIR/lib/modules -maxdepth 1 -type l -delete; # delete link
    [ "$CONFIG_LOCALVERSION" != "$(uname -r)" ] && \
        ln -sTv $kernel_version$CONFIG_LOCALVERSION $ROOTFS_DIR/lib/modules/`uname -r`;
    chroot $ROOTFS_DIR depmod || return $(_err $LINENO);
    [ "$CONFIG_LOCALVERSION" != "$(uname -r)" ] && \
        rm -v $ROOTFS_DIR/lib/modules/`uname -r`


}

# It builds an image that can be used as an ISO *and* a disk image.
# but read only...
_build_iso() {
    [ -n "$1" ] || {
        printf "\n[WARN] skip create iso.\n";
        return 0
    };

    echo " --------------- trim file ------------------------";
    rm -fv $ROOTFS_DIR/etc/*-;

    set ${1##*/};

    echo " ------------- build iso --------------------------";
    cd $ROOTFS_DIR || return $(_err $LINENO 3);

    # create initrd.img
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
