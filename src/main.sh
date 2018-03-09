#!/bin/bash
[ "$SHELL" == "/bin/bash" ] || exit 255;

THIS_DIR=$(cd `dirname $0`; pwd);

# import script
. $THIS_DIR/import/env.sh; # load environment variable
. $THIS_DIR/import/lib.sh; # load common function
. $THIS_DIR/import/build.sh;
. $THIS_DIR/import/profile.sh;

_main() {
    # set work path
    local kernel_version busybox_version glibc_version libcap2_version zlib_version dropbear_version openssh_version iptables_version mdadm_version lvm2_version docker_version curl_version;

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

    echo;
    _case_version ------------ kernel version ----------------------;
    kernel_version=$(curl -L $KERNEL_DOWNLOAD/v${KERNEL_MAJOR_VERSION%.*}.x 2>/dev/null | grep "linux-$KERNEL_MAJOR_VERSION.*xz" | \
        awk -F[-\"] '{print $3}' | _last_version) || return $((LINENO / 2));

    _case_version ------------ glibc version -----------------------;
    glibc_version=$(curl -L $GLIBC_DOWNLOAD 2>/dev/null | grep 'glibc-[0-9].*xz"' | awk -F[-\"] '{print $9}' | _last_version) || return $((LINENO / 2));

    _case_version ----------- busybox version ----------------------;
    busybox_version=$(curl -L $BUSYBOX_DOWNLOAD 2>/dev/null | grep 'busybox-[0-9].*bz2"' | awk -F[-\"] '{print $7}' | _last_version) || return $((LINENO / 2));

    _case_version ------------- zlib version -----------------------;
    zlib_version=$(curl -L $ZLIB_DOWNLOAD/ChangeLog.txt 2>/dev/null | grep Changes | awk '{print $3}' | _last_version) || return $((LINENO / 2));

    _case_version ----------- openssh version ----------------------;
    openssh_version=$(curl -L $OPENSSH_DOWNLOAD 2>/dev/null | grep 'tar\.gz"' | awk -F[-\"] '{print $3}' | _last_version) || return $((LINENO / 2));
    # dropbear_version=$(curl -L $DROPBEAR_DOWNLOAD 2>/dev/null | grep 'bz2"' | awk -F[-\"] '{print $3}' | _last_version) || return $((LINENO / 2));

    _case_version ------------ sshfs version -----------------------;
    sshfs_version=$(curl -L $SSHFS_DOWNLOAD/releases | grep '[0-9]\.zip"' | awk -F[-\"] '{print $3}' | grep zip | grep -v rc | _last_version) || return $((LINENO / 2));

    _case_version ----------- libfuse version ----------------------;
    libfuse_version=$(curl -L $LIBFUSE_DOWNLOAD/releases | grep '[0-9]\.zip"' | awk -F[-\"] '{print $3}' | grep zip | grep -v rc | _last_version) || return $((LINENO / 2));

    _case_version ----------- libcap2 version ----------------------;
    libcap2_version=$(curl -L $LIBCAP2_DOWNLOAD 2>/dev/null | grep 'xz"' | awk -F[-\"] '{print $3}' | _last_version)

    _case_version ----------- iptables version ---------------------;
    iptables_version=$(curl -L $IPTABLES_DOWNLOAD/downloads.html 2>/dev/null | grep '/iptables.*bz2"' | awk -F[-\"] '{print $5}' | _last_version) || return $((LINENO / 2));

    _case_version ------------- mdadm version ----------------------;
    mdadm_version=$(curl -L $MDADM_DOWNLOAD 2>/dev/null | grep "mdadm-.*.xz" | awk -F[-\"] '{print $3}' | _last_version) || return $((LINENO / 2));

    util_linux_version=$(curl -L $UTIL_LINUX_DOWNLOAD/v$UTIL_LINUX_MAJOR_VERSION 2>/dev/null | grep 'util-linux-.*tar.xz"' | grep -v '\-rc' | awk -F[-\"] '{print $4}' | _last_version) || return $((LINENO / 2));

    _case_version ------------- eudev version ----------------------;
    eudev_version=$(curl -L $EUDEV_DOWNLOAD 2>/dev/null | grep 'eudev-.*.tar.gz>' | awk -F[-\>\<] '{print $7}' | _last_version) || return $((LINENO / 2));

    _case_version -------------- lvm2 version ----------------------;
    lvm2_version=$(curl -L $LVM2_DOWNLOAD 2>/dev/null | grep 'tgz"' | awk -F[\"] '{print $2}' | _last_version) || return $((LINENO / 2));

    _case_version ------------- docker version ---------------------;
    # get docker stable version
    docker_version=$(curl -L $DOCKER_DOWNLOAD 2>/dev/null | grep 'docker-' | awk -F[-\"] '{print $3"-"$4}' | _last_version) || return $((LINENO / 2));

    _case_version -------------- curl version ----------------------;
    curl_version=$(curl -L $CURL_DOWNLOAD 2>/dev/null | grep 'xz"' | awk -F[-\"] '{print $9}' | _last_version) || return $((LINENO / 2));

    # _case_version ------------- git version ------------------------;
    # git_version=$(curl -L $GIT_DOWNLOAD 2>/dev/null | grep 'git-[0-9].*tar.xz' | awk -F[-\"] '{print $3}' | _last_version) || return $((LINENO / 2));
    echo;

    # clear for rebuild
    rm -fr $TMP/*.lock $TMP/.error $ROOTFS;

    # Make the rootfs, Prepare the build directory ($TMP/iso)
    mkdir -p $ROOTFS $TMP/iso/boot;

    echo " ------------- put in queue -----------------------"
    _message_queue --init;

    # is need build kernel
    if [ ! -s $TMP/iso/boot/vmlinuz64 ]; then
        # Fetch the kernel sources
        _downlock $KERNEL_DOWNLOAD/v${KERNEL_MAJOR_VERSION%.*}.x/linux-$kernel_version.tar.xz - || return $((LINENO / 2));

        _message_queue --put "_make_kernel"; # this may use most time
        _message_queue --put "_make_busybox";
        _message_queue --put "_make_glibc"; # this may use long time
        _message_queue --put "_make_zlib";
        _message_queue --put "_make_openssl";
        _message_queue --put "_make_ca_certificates";
        _message_queue --put "_make_openssh";
        _message_queue --put "_make_iptables";
        _message_queue --put "_make_mdadm";
        _message_queue --put "_make_libblkid";
        _message_queue --put "_make_eudev";
        _message_queue --put "_make_lvm2";
        _message_queue --put "_make_libcap2";
        _message_queue --put "_make_curl";
        _message_queue --put "_apply_rootfs";

        _downlock $GLIBC_DOWNLOAD/glibc-$glibc_version.tar.xz || return $((LINENO / 2));

        _downlock $BUSYBOX_DOWNLOAD/busybox-$busybox_version.tar.bz2 || return $((LINENO / 2));

        _downlock $ZLIB_DOWNLOAD/zlib-$zlib_version.tar.gz || return $((LINENO / 2)); # for openssl

        _downlock $OPENSSL_DOWNLOAD/openssl-$OPENSSL_VERSION.tar.gz || return $((LINENO / 2));

        curl --retry 10 -L -o $TMP/${CERTDATA_DOWNLOAD##*/} $CERTDATA_DOWNLOAD || return $((LINENO / 2));

        _downlock $CA_CERTIFICATES_DOWNLOAD || return $((LINENO / 2));

        _downlock $OPENSSH_DOWNLOAD/openssh-$openssh_version.tar.gz || return $((LINENO / 2));
        # _downlock $DROPBEAR_DOWNLOAD/dropbear-$dropbear_version.tar.bz2 || return $((LINENO / 2));

        _downlock $SSHFS_DOWNLOAD/archive/sshfs-$sshfs_version.tar.gz || return $((LINENO / 2));

        _downlock $LIBFUSE_DOWNLOAD/archive/libfuse-$libfuse_version.tar.gz || return $((LINENO / 2));

        _downlock $LIBCAP2_DOWNLOAD/libcap-$libcap2_version.tar.xz || return $((LINENO / 2));

        _message_queue --put "_create_etc";

        _downlock $IPTABLES_DOWNLOAD/files/iptables-$iptables_version.tar.bz2 || return $((LINENO / 2));

        _downlock $MDADM_DOWNLOAD/mdadm-$mdadm_version.tar.xz || return $((LINENO / 2));

        _downlock $UTIL_LINUX_DOWNLOAD/v$UTIL_LINUX_MAJOR_VERSION/util-linux-$util_linux_version.tar.xz || return $((LINENO / 2));

        _downlock $EUDEV_DOWNLOAD/eudev-$eudev_version.tar.gz || return $((LINENO / 2));

        _downlock $LVM2_DOWNLOAD/LVM$lvm2_version.tgz || return $((LINENO / 2));

        _downlock $CURL_DOWNLOAD/curl-$curl_version.tar.xz || return $((LINENO / 2));

        _downlock $GIT_DOWNLOAD/git-$git_version.tar.xz || return $((LINENO / 2));
    fi

    # Get the Docker binaries with version.
    _downlock "$DOCKER_DOWNLOAD/docker-$docker_version.tgz" - || return $((LINENO / 2));

    apt-get -y install $APT_GET_LIST_ISO;

    _message_queue --destroy; # close queue

    wait;

    # test queue error
    [ -s $TMP/.error ] && {
        ls $TMP/*.lock 2>/dev/null;
        return $(cat $TMP/.error)
    };

    _create_config;

    echo " ------------ install docker ----------------------";
    mkdir $ROOTFS/usr/local/bin;
    tar -zxvf $TMP/docker.tgz -C $ROOTFS/usr/local/bin --strip-components=1;

    # test docker command
    chroot $ROOTFS docker -v || return $((LINENO / 2));

    echo "-------------- addgroup --------------------------";
    # make sure the "docker" group exists already
    chroot $ROOTFS addgroup -S docker;

    # for dockerd: root map user
    # set up subuid/subgid so that "--userns-remap=default" works out-of-the-box (see also src/rootfs/etc/sub{uid,gid})
    chroot $ROOTFS addgroup -S dockremap;
    chroot $ROOTFS adduser -S -G dockremap dockremap;
    echo "dockremap:165536:65536" | tee $ROOTFS/etc/subgid > $ROOTFS/etc/subuid;

    # add user: tc
    chroot $ROOTFS adduser -s /bin/sh -G staff -D tc;
    chroot $ROOTFS addgroup tc docker;
    chroot $ROOTFS sh -xc 'printf "tc:tcuser" | /usr/sbin/chpasswd -m';
	printf "tc\tALL=NOPASSWD: ALL" >> /etc/sudoers;

    # for iso label
    printf %s "
kernel-$kernel_version
busybox-$busybox_version
ssh-$ssh_version
mdadm-$mdadm_version
iptables-$iptables_version
lvm2-$lvm2_version
docker-$docker_version
" | tee $TMP/iso/version;

    # build iso
    _build_iso || return $?;

    return 0
}

STATUS_CODE=0;
{
    printf "\n[`date`]\n";
    # $((LINENO / 2)) -> return|exit code: [0, 256)
    if time _main; then
        # clean
        rm -fr $TMP/tmp/*.*
    else
        echo "[ERROR]: build.sh: $(($? * 2)) line." >&2;
        STATUS_CODE=1
    fi

    # log path
    printf "\nuse command 'docker cp [container_name]:/build.log .' get log file.\n";
    # complete.
    printf "\ncomplete.\n\n"

} 2>&1 | tee -a "/build.log";

exit $STATUS_CODE
