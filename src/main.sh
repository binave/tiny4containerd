#!/bin/bash

[ "$SHELL" == "/bin/bash" ] || exit 255;

THIS_DIR=$(cd `dirname $0`; pwd) IMPORT=("${0##*/}" "env.sh" "lib.sh" "build.sh" "profile.sh");

# import script
for i in `seq 1 $((${#IMPORT[@]} - 1))`; do . $THIS_DIR/import/${IMPORT[$i]}; done; unset i;

_main() {
    # test complete, then pack it
    [ -f $ROOTFS_DIR/usr/local/bin/docker ] && {
        _modify_config;
        _apply_rootfs;
        _build_iso $@;
        return $?
    };

    # load version info (upper key)
    [ -s $ISO_DIR/version ] && . $ISO_DIR/version;
    mkdir -pv $ISO_DIR/boot;

    echo " ------------- init apt-get ------------------------";
    # install pkg
    _init_install && _install gawk && _install build-essential bsdtar curl || return $(_err $LINENO);

    echo;
    _last_version kernel_version    $KERNEL_DOWNLOAD/v${KERNEL_MAJOR_VERSION%.*}.x  "\"linux-$KERNEL_MAJOR_VERSION.*xz\""   '-F[-\"]'   "'{print \$3}'" || return $(_err $LINENO);
    _last_version libcap_version    $LIBCAP_DOWNLOAD    "'xz\"'"    '-F[-\"]'   "'{print \$3}'"         || return $(_err $LINENO);
    _last_version docker_version    $DOCKER_DOWNLOAD    docker-     '-F[-\"]'   "'{print \$3\"-\"\$4}'" || return $(_err $LINENO);

    # for iso label
    mv -v $ISO_DIR/version.swp $ISO_DIR/version;
    echo;

    # Fetch the kernel sources
    _downlock $KERNEL_DOWNLOAD/v${KERNEL_MAJOR_VERSION%.*}.x/linux-$kernel_version.tar.xz || return $(_err $LINENO);

    echo " ------------- put in queue -----------------------";
    _message_queue --init;

    _install bc;                _message_queue --put "_make_kernel"; # this may use most time
    _install cpio squashfs-tools;    _message_queue --put "_undep";
    _message_queue --put "_make_libcap";
    _message_queue --put "_modify_config";
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
        $LIBCAP_DOWNLOAD/libcap-$libcap_version.tar.xz \
        $TCL_REPO_DOWNLOAD/release/distribution_files/rootfs64.gz \
        $DOCKER_DOWNLOAD/docker-$docker_version.tgz;
    do
        _thread_valve --run _downlock $url # get thread and run
    done

    # destroy thread valve
    _thread_valve --destroy;

    # for '_build_iso'
    _install genisoimage isolinux syslinux xorriso xz-utils || return $(_err $LINENO);
    wait;

    # test queue error
    [ -s $WORK_DIR/.error ] && return 1;

    _refreshe;
    _add_group;


    echo " ------------ install docker ----------------------";
    mkdir -pv $ROOTFS_DIR/usr/local/bin;
    _untar \
        $CELLAR_DIR/docker- \
        $ROOTFS_DIR/usr/local/bin --strip-components=1 && \
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
    printf "\nuse command:\n    'docker cp [container_name]:$OUT_DIR/build.log .' get log file.\n";
    [ "$1" ] && printf "    'docker cp [container_name]:$OUT_DIR/$1 .' get iso file.\n";
    printf "\ncomplete.\n\n";
    exit 0

} 2>&1 | tee -a "$OUT_DIR/build.log";

exit 0
