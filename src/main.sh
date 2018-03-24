#!/bin/bash
[ "$SHELL" == "/bin/bash" ] || exit 255;

THIS_DIR=$(cd `dirname $0`; pwd) IMPORT=("${0##*/}" "env.sh" "lib.sh" "build.sh" "profile.sh");

# import script
for i in `seq 1 $((${#IMPORT[@]} - 1))`; do . $THIS_DIR/import/${IMPORT[$i]}; done; unset i;

_main() {
    # test complete, then pack it
    [ -f $ROOTFS_DIR/usr/local/bin/docker ] && {
        _create_etc;
        _apply_rootfs;
        _build_iso $@;
        return $?
    };

    # load version info (upper key)
    [ -s $ISO_DIR/version ] && . $ISO_DIR/version;

    # clean the rootfs, prepare the build directory ($ISO_DIR)
    rm -fr $ROOTFS_DIR; mkdir -pv $ISO_DIR/boot $ROOTFS_DIR;

    echo " ------------- init apt-get ------------------------";
    # install pkg
    _init_install && _install gawk && _install build-essential bsdtar curl git-core || return $(_err $LINENO);

    echo;
    _last_version kernel_version    $KERNEL_DOWNLOAD/v${KERNEL_MAJOR_VERSION%.*}.x  "\"linux-$KERNEL_MAJOR_VERSION.*xz\""   '-F[-\"]'   "'{print \$3}'" || return $(_err $LINENO);
    _last_version glibc_version     $GLIBC_DOWNLOAD     "'glibc-[0-9].*xz\"'"       '-F[-\"]'       "'{print \$9}'" || return $(_err $LINENO);
    _last_version busybox_version   $BUSYBOX_DOWNLOAD   "'busybox-[0-9].*bz2\"'"    '-F[-\"]'       "'{print \$7}'" || return $(_err $LINENO);
    _last_version zlib_version      $ZLIB_DOWNLOAD/ChangeLog.txt Changes                            "'{print \$3}'" || return $(_err $LINENO);
    _last_version openssh_version   $OPENSSH_DOWNLOAD   "'tar\.gz\"'"               '-F[-\"]'       "'{print \$3}'" || return $(_err $LINENO);
    _last_version iptables_version  $IPTABLES_DOWNLOAD  "'\"iptables-.*bz2\"'"      '-F[-\"]'       "'{print \$9}'" || return $(_err $LINENO);
    _last_version mdadm_version     $MDADM_DOWNLOAD     "\"mdadm-.*.xz\""           '-F[-\"]'       "'{print \$3}'" || return $(_err $LINENO);
    _last_version util_linux_version    $UTIL_LINUX_DOWNLOAD/v$UTIL_LINUX_MAJOR_VERSION     "'util-linux-.*tar.xz\"'"   '-F[-\"]'   "'{print \$4}'" || return $(_err $LINENO);
    _last_version eudev_version     $EUDEV_DOWNLOAD     "'eudev-.*.tar.gz>'"        '-F[-\>\<]'     "'{print \$7}'" || return $(_err $LINENO);
    _last_version lvm2_version      $LVM2_DOWNLOAD      "'tgz\"'"                   '-F[\"]'        "'{print \$8}'" || return $(_err $LINENO);
    _last_version libfuse_version   $LIBFUSE_DOWNLOAD/tags  tag-name                '-F[-\>\<]'     "'{print \$5}'" || return $(_err $LINENO);
    _last_version glib_version      $GLIB_DOWNLOAD/$GLIB_MAJOR_VERSION  "'xz\"'"    '-F[-\"]'       "'{print \$9}'" || return $(_err $LINENO);
    _last_version pcre_version      $PCRE_DOWNLOAD      "'pcre-.*bz2\"'"            '-F[-\"]'       "'{print \$3}'" || return $(_err $LINENO);
    _last_version sshfs_version     $SSHFS_DOWNLOAD/tags    tag-name                '-F[-_\>\<]'    "'{print \$5}'" || return $(_err $LINENO);
    _last_version libcap2_version   $LIBCAP2_DOWNLOAD   "'xz\"'"                    '-F[-\"]'       "'{print \$3}'" || return $(_err $LINENO);
    # _last_version procps_version    $PROCPS_DOWNLOAD    "'\-ng-.*.tar.xz\"'"        '-F[-\"]'       "'{print \$10}'"|| return $(_err $LINENO);
    _last_version git_version       $GIT_DOWNLOAD       "'git-[0-9].*tar.xz'"       '-F[-\"]'       "'{print \$3}'" || return $(_err $LINENO);
    _last_version sudo_version      $SUDO_DOWNLOAD      "'sudo-.*tar\\.gz\"'"       '-F[-\"]'       "'{print \$3}'" || return $(_err $LINENO);
    _last_version e2fsprogs_version $E2FSPROGS_DOWNLOAD "'v.*/'"                    '-F[v/]'        "'{print \$2}'" || return $(_err $LINENO);
    _last_version curl_version      $CURL_DOWNLOAD      "'xz\"'"                    '-F[-\"]'       "'{print \$9}'" || return $(_err $LINENO);
    # get docker stable version
    _last_version docker_version    $DOCKER_DOWNLOAD    docker-                     '-F[-\"]'       "'{print \$3\"-\"\$4}'" || return $(_err $LINENO);

    # for iso label
    mv -v $ISO_DIR/version.swp $ISO_DIR/version;
    echo;

    # Fetch the kernel sources
    _downlock $KERNEL_DOWNLOAD/v${KERNEL_MAJOR_VERSION%.*}.x/linux-$kernel_version.tar.xz || return $(_err $LINENO);

    echo " ------------- put in queue -----------------------"
    _message_queue --init;

    # kernel, libc, rootfs
    _install bc;                _message_queue --put "_make_kernel"; # this may use most time
    _install bison gawk;        _message_queue --put "_make_glibc"; # this may use long time
    _message_queue --put "_make_busybox";

    # ssl
    _message_queue --put "__make_zlib";
    _message_queue --put "_make_openssl";
    # libnss3-tools p11-kit
    _install python;            _message_queue --put "_make_ca";
    _message_queue --put "_make_openssh";

    # firewall
    _message_queue --put "_make_iptables";

    # dev
    _message_queue --put "_make_mdadm";
    _message_queue --put "__make_util_linux";
    _install gperf;             _message_queue --put "_make_eudev";
    _install pkg-config;        _message_queue --put "_make_lvm2";

    # sshfs
    _install re2c python3;      _message_queue --put "_build_meson";
    _message_queue --put "_make_fuse";
    _install libbz2-dev libreadline-dev;    _message_queue --put "__make_pcre";
    _install libffi-dev gettext;            _message_queue --put "__make_glib";
    _install python-docutils;   _message_queue --put "_make_sshfs";

    # tools
    _message_queue --put "_make_git";
    # _install ncurses-dev;       _message_queue --put "_make_procps";
    _message_queue --put "_make_sudo";
    _message_queue --put "_make_e2fsprogs";
    _message_queue --put "_make_curl";
    _message_queue --put "__make_libcap2";

    # add file
    _message_queue --put "_create_etc";
    _message_queue --put "_apply_rootfs";

    _message_queue --destroy;

    # init thread valve
    _thread_valve --init $THREAD_COUNT;

    local url;
    for url in \
        $GLIBC_DOWNLOAD/glibc-$glibc_version.tar.xz \
        $BUSYBOX_DOWNLOAD/busybox-$busybox_version.tar.bz2 \
        $ZLIB_DOWNLOAD/zlib-$zlib_version.tar.gz \
        $OPENSSL_DOWNLOAD/openssl-$OPENSSL_VERSION.tar.gz \
        $CERTDATA_DOWNLOAD \
        $CA_CERTIFICATES_REPOSITORY.master \
        $OPENSSH_DOWNLOAD/openssh-$openssh_version.tar.gz \
        $IPTABLES_DOWNLOAD/iptables-$iptables_version.tar.bz2 \
        $MDADM_DOWNLOAD/mdadm-$mdadm_version.tar.xz \
        $UTIL_LINUX_DOWNLOAD/v$UTIL_LINUX_MAJOR_VERSION/util-linux-$util_linux_version.tar.xz \
        $EUDEV_DOWNLOAD/eudev-$eudev_version.tar.gz \
        $LVM2_DOWNLOAD/LVM$lvm2_version.tgz \
        $GLIB_DOWNLOAD/$GLIB_MAJOR_VERSION/glib-$glib_version.tar.xz \
        $PCRE_DOWNLOAD/pcre-$pcre_version.tar.bz2 \
        $MESON_REPOSITORY.master \
        $NINJA_REPOSITORY.release \
        $LIBFUSE_DOWNLOAD/archive/fuse-$libfuse_version.tar.gz \
        $SSHFS_DOWNLOAD/archive/sshfs-$sshfs_version.tar.gz \
        $GIT_DOWNLOAD/git-$git_version.tar.xz \
        $SUDO_DOWNLOAD/sudo-$sudo_version.tar.gz \
        $E2FSPROGS_DOWNLOAD/v$e2fsprogs_version/e2fsprogs-$e2fsprogs_version.tar.xz \
        $CURL_DOWNLOAD/curl-$curl_version.tar.xz \
        $LIBCAP2_DOWNLOAD/libcap-$libcap2_version.tar.xz \
        $DOCKER_DOWNLOAD/docker-$docker_version.tgz;
        # $PROCPS_DOWNLOAD/procps-ng-$procps_version.tar.xz \
    do
        # get thread and run
        _thread_valve --run _downlock $url
    done

    # destroy thread valve
    _thread_valve --destroy;

    # for '_build_iso'
    _install cpio genisoimage isolinux syslinux xorriso xz-utils || return $(_err $LINENO);
    wait;

    # test queue error
    [ -s $WORK_DIR/.error ] && return 1;

    echo " -------------- run chroot ------------------------";
    # refresh libc cache
    chroot $ROOTFS_DIR ldconfig || return $(_err $LINENO);

    # Generate modules.dep
    find $ROOTFS_DIR/lib/modules -maxdepth 1 -type l -delete; # delete link
    [ "$CONFIG_LOCALVERSION" != "$(uname -r)" ] && \
        ln -sTv $kernel_version$CONFIG_LOCALVERSION $ROOTFS_DIR/lib/modules/`uname -r`;
    chroot $ROOTFS_DIR depmod || return $(_err $LINENO);
    [ "$CONFIG_LOCALVERSION" != "$(uname -r)" ] && \
        rm -v $ROOTFS_DIR/lib/modules/`uname -r`;

    # create sshd key
    chroot $ROOTFS_DIR ssh-keygen -A || return $(_err $LINENO);

    echo "-------------- addgroup --------------------------";
    # for dockerd: root map user
    # set up subuid/subgid so that "--userns-remap=default" works out-of-the-box (see also src/rootfs/etc/sub{uid,gid})
    chroot $ROOTFS_DIR sh -xc 'addgroup -S dockremap && adduser -S -G dockremap dockremap';
    echo "dockremap:165536:65536" | tee $ROOTFS_DIR/etc/subgid > $ROOTFS_DIR/etc/subuid;
    chroot $ROOTFS_DIR addgroup -S docker;

    echo "--------------- adduser --------------------------";
    # add user: tc
    local add_user=tc;
    chroot $ROOTFS_DIR sh -xc "adduser -s /bin/sh -G staff -D $add_user && \
        addgroup $add_user docker && \
        printf $add_user:tcuser | /usr/sbin/chpasswd -m";
	printf "$add_user\tALL=NOPASSWD: ALL\n" >> $ROOTFS_DIR/etc/sudoers.d/${add_user}_sudo;

    echo " ------------ install docker ----------------------";
    mkdir -pv $ROOTFS_DIR/usr/local/bin;
    _untar $CELLAR_DIR/docker- $ROOTFS_DIR/usr/local/bin --strip-components=1 && \
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
