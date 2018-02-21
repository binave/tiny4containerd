#!/bin/bash
[ "$SHELL" == "/bin/bash" ] || exit 255;

# import script
. $THIS_DIR/env.bash; # load environment variable
. $THIS_DIR/lib.bash; # load common function
. $THIS_DIR/function.bash;

_main() {
    # set work path
    local busybox_version docker_version dropbear_version git_version iptables_version kernel_version lvm2_version mdadm_version zlib_version;

    # test complete, then pack it
    [ -s $TMP/iso/version ] && {
        cat $TMP/iso/version 2>/dev/null;
        printf "\n";
        _build_iso || return $?;
        return 0
    };

    echo " --------------- apt-get --------------------------";
    # install pkg
    _apt_get_install || return $((LINENO / 2));

    _case_version ------------ kernel version ----------------------;
    kernel_version=$(curl -L $KERNEL_DOWNLOAD/v${KERNEL_MAJOR_VERSION%.*}.x | grep "linux-$KERNEL_MAJOR_VERSION.*xz" | \
        awk -F[-\"] '{print $3}' | _last_version) || return $((LINENO / 2));

    _case_version ----------- busybox version ----------------------;
    busybox_version=$(curl -L $BUSYBOX_DOWNLOAD | grep 'busybox-[0-9].*bz2"' | awk -F[-\"] '{print $7}' | _last_version) || return $((LINENO / 2));

    _case_version ----------- libcap2 version ----------------------;
    libcap2_version=$(curl -L $LIBCAP2_DOWNLOAD | grep 'xz"' | awk -F[-\"] '{print $3}' | _last_version)

    _case_version ------------- zlib version -----------------------;
    zlib_version=$(curl -L $ZLIB_DOWNLOAD/ChangeLog.txt | grep Changes | awk '{print $3}' | _last_version) || return $((LINENO / 2));

    _case_version ----------- dropbear version ---------------------;
    dropbear_version=$(curl -L $DROPBEAR_DOWNLOAD | grep 'bz2"' | awk -F[-\"] '{print $3}' | _last_version) || return $((LINENO / 2));

    _case_version ----------- iptables version ---------------------;
    iptables_version=$(curl -L $IPTABLES_DOWNLOAD/downloads.html | grep 'bz2"' | awk -F[-\"] '{print $5}' | _last_version) || return $((LINENO / 2));

    _case_version ------------- mdadm version ----------------------;
    mdadm_version=$(curl -L $MDADM_DOWNLOAD | grep "mdadm-.*.xz" | awk -F[-\"] '{print $3}' | _last_version) || return $((LINENO / 2));

    _case_version -------------- lvm2 version ----------------------;
    lvm2_version=$(curl -L $LVM2_DOWNLOAD | grep 'tgz"' | awk -F[\"] '{print $2}' | _last_version) || return $((LINENO / 2));

    _case_version ------------- docker version ---------------------;
    # get docker stable version
    docker_version=$(curl -L $DOCKER_DOWNLOAD | grep 'docker-' | awk -F[-\"] '{print $3"-"$4}' | _last_version) || return $((LINENO / 2));

    _case_version -------------- curl version ----------------------;
    curl_version=$(curl -L $CURL_DOWNLOAD | grep 'xz"' | awk -F[-\"] '{print $9}' | _last_version) || return $((LINENO / 2));

    # _case_version ------------- git version ------------------------;
    # git_version=$(curl -L $GIT_DOWNLOAD | grep 'git-[0-9].*tar.xz' | awk -F[-\"] '{print $3}' | _last_version) || return $((LINENO / 2));

    # clear for rebuild
    rm -fr $TMP/*.lock $TMP/.error $ROOTFS;

    # Make the rootfs, Prepare the build directory ($TMP/iso)
    mkdir -p $ROOTFS $TMP/iso/boot;

    echo " ------------- put in queue -----------------------"
    _message_queue --init;

    # is need build kernel
    if [ ! -s $TMP/iso/boot/vmlinuz64 ]; then
        # https://www.kernel.org/ Fetch the kernel sources
        _downlock $KERNEL_DOWNLOAD/v${KERNEL_MAJOR_VERSION%.*}.x/linux-$kernel_version.tar.xz - || return $((LINENO / 2));

        _message_queue --put "_make_kernel"; # this may use most time
        _message_queue --put "_make_busybox";
        _message_queue --put "_make_libcap2";
        _message_queue --put "_make_dropbear";
        _message_queue --put "_make_iptables";
        _message_queue --put "_make_mdadm";
        _message_queue --put "_make_lvm2";

        _downlock $BUSYBOX_DOWNLOAD/busybox-$busybox_version.tar.bz2 || return $((LINENO / 2));

        _downlock $LIBCAP2_DOWNLOAD/libcap-$libcap2_version.tar.xz || return $((LINENO / 2));

        # for dropbear
        _downlock $ZLIB_DOWNLOAD/zlib-$zlib_version.tar.gz ||  return $((LINENO / 2));

        _downlock $DROPBEAR_DOWNLOAD/dropbear-$dropbear_version.tar.bz2 || return $((LINENO / 2));

        _downlock $IPTABLES_DOWNLOAD/files/iptables-$iptables_version.tar.bz2 || return $((LINENO / 2));

        _downlock $MDADM_DOWNLOAD/mdadm-$mdadm_version.tar.xz || return $((LINENO / 2));

        _downlock $LVM2_DOWNLOAD/LVM$lvm2_version.tgz - || return $((LINENO / 2));

        # _downlock $GIT_DOWNLOAD/git-$git_version.tar.xz || return $((LINENO / 2));

        # https://www.openssl.org/source/openssl-1.0.2n.tar.gz

    fi

    apt-get -y install $APT_GET_LIST_ISO;

    _message_queue --put "_apply_rootfs";
    _message_queue --destroy; # close queue

    _downlock "$CURL_DOWNLOAD/curl-$curl_version.tar.xz" - || return $((LINENO / 2));

    # Get the Docker binaries with version.
    _downlock "$DOCKER_DOWNLOAD/docker-$docker_version.tgz" - || return $((LINENO / 2));

    wait;

    # test queue error
    [ -s $TMP/.error ] && {
        ls $TMP/*.lock 2>/dev/null;
        return $(cat $TMP/.error)
    };

    echo " ------------ install docker ----------------------";
    tar -zxvf $TMP/docker.tgz -C $ROOTFS/usr/local/bin --strip-components=1;

    # test docker command
    chroot $ROOTFS docker -v || return $((LINENO / 2));

    rm -f $TMP/docker.tgz; # clear

    echo " -------------- boot file -------------------------";
    # Copy boot params,
    cd $TMP; # fix: sh: 0: getcwd() failed: No such file or directory

    # add boot file
    cp -rv $THIS_DIR/isolinux $TMP/iso/boot/;
    cp -v \
        /usr/lib/ISOLINUX/isolinux.bin \
        /usr/lib/syslinux/modules/bios/ldlinux.c32 \
        $TMP/iso/boot/isolinux/;

    _modify_config;

    echo "-------------- addgroup --------------------------";
    # make sure the "docker" group exists already
    chroot $ROOTFS addgroup -S docker;

    # for dockerd: root map user
    # set up subuid/subgid so that "--userns-remap=default" works out-of-the-box (see also src/rootfs/etc/sub{uid,gid})
    chroot $ROOTFS addgroup -S dockremap;
    chroot $ROOTFS adduser -S -G dockremap dockremap;
    echo "dockremap:165536:65536" | tee $ROOTFS/etc/subgid > $ROOTFS/etc/subuid;

    # drop user: tc
    # sed -i 's/staff:.*/&tc/' $ROOTFS/etc/group;
    chroot $ROOTFS deluser tc 2>/dev/null;

    # for iso label
    printf %s "
kernel-$kernel_version
docker-$docker_version
busybox-$busybox_version
" | tee $TMP/iso/version;

    # build iso
    _build_iso || return $?;

    return 0
}

STATUS_CODE=0;
{
    printf "\n[`date`]\n";
    # $((LINENO / 2)) -> return|exit code: [0, 256)
    time _main || {
        echo "[ERROR]: build.sh: $(($? * 2)) line." >&2;
        STATUS_CODE=1
    };

    # log path
    printf "\nuse command 'docker cp [container_name]:$THIS_DIR/build.log .' get log file.\n";
    # complete.
    printf "\ncomplete.\n\n"

} 2>&1 | tee -a "${0%.*}.log";

exit $STATUS_CODE
