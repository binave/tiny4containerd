#!/bin/bash

[ "$SHELL" == "/bin/bash" ] || exit 255;

THIS_DIR=$(cd `dirname $0`; pwd) IMPORT=("${0##*/}" "env.sh" "lib.sh" "build.sh" "profile.sh");

# import script
for i in `seq 1 $((${#IMPORT[@]} - 1))`; do . $THIS_DIR/import/${IMPORT[$i]}; done; unset i;

_main() {
    # test complete, then pack it
    [ -f $ROOTFS_DIR/usr/local/bin/docker ] && {
        _build_iso $@;
        return $?
    };

    # load version info (upper key)
    [ -s $ISO_DIR/version ] && . $ISO_DIR/version;

    rm -fr $ROOTFS_DIR; mkdir -pv $ISO_DIR/boot $ROOTFS_DIR;

    echo " ------------- init apt-get ------------------------";
    # install pkg
    _init_install && _install gawk && _install build-essential bsdtar curl || return $(_err $LINENO);

    echo;
    _last_version kernel_version    $KERNEL_DOWNLOAD/v${KERNEL_MAJOR_VERSION%.*}.x  "\"linux-$KERNEL_MAJOR_VERSION.*xz\""   '-F[-\"]'   "'{print \$3}'" || return $(_err $LINENO);
    _last_version libcap2_version   $LIBCAP2_DOWNLOAD   "'xz\"'"    '-F[-\"]'   "'{print \$3}'"         || return $(_err $LINENO);
    _last_version docker_version    $DOCKER_DOWNLOAD    docker-     '-F[-\"]'   "'{print \$3\"-\"\$4}'" || return $(_err $LINENO);

    # for iso label
    mv -v $ISO_DIR/version.swp $ISO_DIR/version;
    echo;

    # Fetch the kernel sources
    _downlock $KERNEL_DOWNLOAD/v${KERNEL_MAJOR_VERSION%.*}.x/linux-$kernel_version.tar.xz || return $(_err $LINENO);

    echo "------------- put in queue -----------------------";
    _message_queue --init;

    _install bc;                _message_queue --put "_make_kernel"; # this may use most time
    _message_queue --put "_make_libcap2";
    _install squashfs-tools;    _message_queue --put "_undep";
    _message_queue --put "_apply_rootfs";

    _message_queue --destroy;

    # init thread valve
    _thread_valve --init $THREAD_COUNT;

    local dep url;
    for dep in $TCZ_DEPS;
    do
        _thread_valve --run _downlock $TCL_REPO_DOWNLOAD/tcz/$dep.tcz
    done
    for url in \
        $LIBCAP2_DOWNLOAD/libcap-$libcap2_version.tar.xz \
        $TCL_REPO_DOWNLOAD/release/distribution_files/rootfs64.gz \
        $DOCKER_DOWNLOAD/docker-$docker_version.tgz;
    do
        _thread_valve --run _downlock $url # get thread and run
    done

    # destroy thread valve
    _thread_valve --destroy;

    # for '_build_iso'
    _install cpio genisoimage isolinux syslinux xorriso xz-utils || return $(_err $LINENO);
    wait;

    # test queue error
    [ -s $WORK_DIR/.error ] && return 1;

    echo "-------------- addgroup --------------------------";
    # for dockerd: root map user
    # set up subuid/subgid so that "--userns-remap=default" works out-of-the-box (see also src/rootfs/etc/sub{uid,gid})
    chroot $ROOTFS_DIR sh -xc 'addgroup -S dockremap && adduser -S -G dockremap dockremap';
    echo "dockremap:165536:65536" | tee $ROOTFS_DIR/etc/subgid > $ROOTFS_DIR/etc/subuid;
    chroot $ROOTFS_DIR addgroup -S docker;

    # drop user: tc
    # sed -i 's/staff:.*/&tc/' $ROOTFS_DIR/etc/group;
    chroot $ROOTFS_DIR deluser tc 2>/dev/null;

    echo " ------------ install docker ----------------------";
    mkdir -pv $ROOTFS_DIR/usr/local/bin;
    _untar docker- $ROOTFS_DIR/usr/local/bin --strip-components=1 && \
        chroot $ROOTFS_DIR docker -v || return $(_err $LINENO); # test docker command

    # build iso
    _build_iso $@;
    return $?
}

# create directory
rm -fr $LOCK_DIR $WORK_DIR;
printf "mkdir -pv$(set | grep _DIR= | awk -F= '{printf " "$2}')" | bash;

{
    printf "\n[`date`]\n";
    # return|exit code: [0, 256)
    time _main $@ || cat $WORK_DIR/.error >&2;

    # log path
    printf "\nuse command 'docker cp [container_name]:$OUT_DIR/build.log .' get log file.\n";
    [ "$1" ] && printf "use command 'docker cp [container_name]:$OUT_DIR/$1 .' get iso file.\n";
    # complete.
    printf "\ncomplete.\n\n";
    exit 0

} 2>&1 | tee -a "$OUT_DIR/build.log";

exit 0
