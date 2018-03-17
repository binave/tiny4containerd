#!/bin/bash
[ "$SHELL" == "/bin/bash" ] || exit 255;

THIS_DIR=$(cd `dirname $0`; pwd) IMPORT=("${0##*/}" "env" "lib" "build" "profile");

# import script
. $THIS_DIR/import/env.sh; # load environment variable
. $THIS_DIR/import/lib.sh; # load common function
. $THIS_DIR/import/build.sh; # 3
. $THIS_DIR/import/profile.sh; # 4

_main() {
    # test complete, then pack it
    [ -f $ROOTFS_DIR/usr/local/bin/docker ] && {
        _build_iso $@;
        return $?
    };

    # load version info (upper key)
    [ -s $ISO_DIR/version ] && . $ISO_DIR/version;

    # clean the rootfs, prepare the build directory ($ISO_DIR)
    rm -fr $ISO_DIR $ROOTFS_DIR;
    mkdir -pv $ISO_DIR/boot $ROOTFS_DIR;

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
    _last_version sudo_version      $SUDO_DOWNLOAD      "'sudo-.*tar\\.gz\"'"       '-F[-\"]'       "'{print \$3}'" || return $(_err $LINENO);
    _last_version curl_version      $CURL_DOWNLOAD      "'xz\"'"                    '-F[-\"]'       "'{print \$9}'" || return $(_err $LINENO);
    # _last_version perl5_version     $PERL5_DOWNLOAD     "'perl.*bz2\"'"             '-F[-\"]'       "'{print \$3}'" "| grep '5\..*[24680]\.[0-9]'" || return $(_err $LINENO);
    # get docker stable version
    _last_version docker_version    $DOCKER_DOWNLOAD        docker-                 '-F[-\"]'       "'{print \$3\"-\"\$4}'" || return $(_err $LINENO);
echo;

    # is need build kernel
    if [ ! -s $ISO_DIR/boot/vmlinuz64 ]; then

        # Fetch the kernel sources
        _downlock $KERNEL_DOWNLOAD/v${KERNEL_MAJOR_VERSION%.*}.x/linux-$kernel_version.tar.xz - || return $(_err $LINENO);

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
        _message_queue --put "_make_sudo";
        _message_queue --put "_make_curl";
        # _message_queue --put "_make_perl5";
        _message_queue --put "__make_libcap2";

        # add file
        _message_queue --put "_create_etc";
        _message_queue --put "_apply_rootfs";

        _message_queue --destroy;

        # init thread valve
        _thread_valve --init 2;

        local url;
        for url in \
            $GLIBC_DOWNLOAD/glibc-$glibc_version.tar.xz \
            $BUSYBOX_DOWNLOAD/busybox-$busybox_version.tar.bz2 \
            $ZLIB_DOWNLOAD/zlib-$zlib_version.tar.gz \
            $OPENSSL_DOWNLOAD/openssl-$OPENSSL_VERSION.tar.gz \
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
            $SUDO_DOWNLOAD/sudo-$sudo_version.tar.gz \
            $CURL_DOWNLOAD/curl-$curl_version.tar.xz \
            $LIBCAP2_DOWNLOAD/libcap-$libcap2_version.tar.xz \
            $DOCKER_DOWNLOAD/docker-$docker_version.tgz;
            # $PERL5_DOWNLOAD/perl-$perl5_version.tar.bz2
        do
            # get thread and run
            _thread_valve --run _downlock $url
        done

        # destroy thread valve
        _thread_valve --destroy;
    fi

    # for '_build_iso'
    _install cpio genisoimage isolinux syslinux xorriso xz-utils || return $(_err $LINENO);
    wait;

    # test queue error
    [ -s $WORK_DIR/.error ] && return 1;

    echo " -------------- run chroot ------------------------";
    mkdir -pv $ROOTFS_DIR/dev;
    mknod -m 666 $ROOTFS_DIR/dev/null c 1 3;
    mknod -m 666 $ROOTFS_DIR/dev/zero c 1 5;
    mknod -m 666 $ROOTFS_DIR/dev/random c 1 8; # fix: PRNG is not seeded
    mknod -m 644 $ROOTFS_DIR/dev/urandom c 1 9;

    # refresh libc cache
    chroot $ROOTFS_DIR ldconfig;

    echo "-------------- addgroup --------------------------";
    # for dockerd: root map user
    # set up subuid/subgid so that "--userns-remap=default" works out-of-the-box (see also src/rootfs/etc/sub{uid,gid})
    chroot $ROOTFS_DIR sh -xc 'addgroup -S dockremap && adduser -S -G dockremap dockremap';
    echo "dockremap:165536:65536" | tee $ROOTFS_DIR/etc/subgid > $ROOTFS_DIR/etc/subuid;

    # add user: tc
    chroot $ROOTFS_DIR sh -xc 'addgroup -S docker && \
        adduser -s /bin/sh -G staff -D tc && \
        addgroup tc docker && \
        printf "tc:tcuser" | /usr/sbin/chpasswd -m';
	printf "tc\tALL=NOPASSWD: ALL" >> $ROOTFS_DIR/etc/sudoers;

    echo " ------------ install docker ----------------------";
    mkdir -pv $ROOTFS_DIR/usr/local/bin;
    tar -zxvf $CELLAR_DIR/docker.tgz -C $ROOTFS_DIR/usr/local/bin --strip-components=1 || return $(_err $LINENO);

    # create ssh key and test docker command
    chroot $ROOTFS_DIR sh -xc 'ssh-keygen -A && docker -v' || return $(_err $LINENO);

    # clear dev
    rm -frv $ROOTFS_DIR/{dev,var}/*;

    # for iso label
    mv -v $ISO_DIR/version.swp $ISO_DIR/version;

    # build iso
    _build_iso $@ || return $?;
    return 0
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
    [ "$1" ] && printf "\nuse command 'docker cp [container_name]:$OUT_DIR/$1 .' get iso file.\n";
    # complete.
    printf "\ncomplete.\n\n";
    exit 0

} 2>&1 | tee -a "$OUT_DIR/build.log";

exit 0
