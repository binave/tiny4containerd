#!/bin/bash
[ "$SHELL" == "/bin/bash" ] || exit 255;

THIS_DIR=$(cd `dirname $0`; pwd);

# import script
. $THIS_DIR/import/env.sh; # load environment variable
. $THIS_DIR/import/lib.sh; # load common function
. $THIS_DIR/import/build.sh;
. $THIS_DIR/import/profile.sh;

_main() {
    # test complete, then pack it
    [ -s $TMP/iso/version ] && {
        cat $TMP/iso/version 2>/dev/null;
        printf "\n";
        _build_iso || return $?;
        return 0
    };

    echo " ------------- init apt-get ------------------------";
    # install pkg
    _init_install && _install bsdtar build-essential curl git-core || return $((LINENO / 2));

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

    _case_version ----------- iptables version ---------------------;
    iptables_version=$(curl -L $IPTABLES_DOWNLOAD/downloads.html 2>/dev/null | grep '/iptables.*bz2"' | awk -F[-\"] '{print $5}' | _last_version) || return $((LINENO / 2));

    _case_version ------------- mdadm version ----------------------;
    mdadm_version=$(curl -L $MDADM_DOWNLOAD 2>/dev/null | grep "mdadm-.*.xz" | awk -F[-\"] '{print $3}' | _last_version) || return $((LINENO / 2));

    _case_version ----------- util-linux version -------------------;
    util_linux_version=$(curl -L $UTIL_LINUX_DOWNLOAD/v$UTIL_LINUX_MAJOR_VERSION 2>/dev/null | grep 'util-linux-.*tar.xz"' | awk -F[-\"] '{print $4}' | _last_version) || return $((LINENO / 2));

    _case_version ------------- eudev version ----------------------;
    eudev_version=$(curl -L $EUDEV_DOWNLOAD 2>/dev/null | grep 'eudev-.*.tar.gz>' | awk -F[-\>\<] '{print $7}' | _last_version) || return $((LINENO / 2));

    _case_version -------------- lvm2 version ----------------------;
    lvm2_version=$(curl -L $LVM2_DOWNLOAD 2>/dev/null | grep 'tgz"' | awk -F[\"] '{print $8}' | _last_version) || return $((LINENO / 2));

    _case_version ------------ libfuse version ---------------------;
    libfuse_version=$(curl -L $LIBFUSE_DOWNLOAD/releases | grep '[0-9]\.zip"' | awk -F[-\"] '{print $3}' | grep zip | _last_version) || return $((LINENO / 2));

    _case_version ------------- glib version -----------------------;
    glib_version=$(curl -L $GLIB_DOWNLOAD/$GLIB_MAJOR_VERSION 2>/dev/null | grep 'xz"' | awk -F[-\"] '{print $9}' | _last_version) || return $((LINENO / 2));

    _case_version ------------- pcre version -----------------------;
    pcre_version=$(curl -L $PCRE_DOWNLOAD 2>/dev/null | grep 'pcre-.*bz2"' | awk -F[-\"] '{print $3}' | _last_version) || return $((LINENO / 2));

    _case_version ------------ sshfs version -----------------------;
    sshfs_version=$(curl -L $SSHFS_DOWNLOAD/releases | grep '[0-9]\.zip"' | awk -F[-\"] '{print $3}' | grep zip | _last_version) || return $((LINENO / 2));

    _case_version ----------- libcap2 version ----------------------;
    libcap2_version=$(curl -L $LIBCAP2_DOWNLOAD 2>/dev/null | grep 'xz"' | awk -F[-\"] '{print $3}' | _last_version) || return $((LINENO / 2));

    _case_version ------------- curl version -----------------------;
    curl_version=$(curl -L $CURL_DOWNLOAD 2>/dev/null | grep 'xz"' | awk -F[-\"] '{print $9}' | _last_version) || return $((LINENO / 2));

    # _case_version ------------ perl5 version -----------------------;
    # perl5_version=$(curl -L $PERL5_DOWNLOAD 2>/dev/null | grep 'perl.*bz2"' | awk -F[-\"] '{print $3}' | grep '5\..*[24680]\.[0-9]' | _last_version) || return $((LINENO / 2));

    # get docker stable version
    _case_version ------------- docker version ---------------------;
    docker_version=$(curl -L $DOCKER_DOWNLOAD 2>/dev/null | grep 'docker-' | awk -F[-\"] '{print $3"-"$4}' | _last_version) || return $((LINENO / 2));
    echo;

    # clear for rebuild
    rm -fr $TMP/*.lock $TMP/.error $ROOTFS;

    # Make the rootfs, Prepare the build directory ($TMP/iso)
    mkdir -pv $ROOTFS $TMP/iso/boot;

    echo " ------------- put in queue -----------------------"
    _message_queue --init;

    # is need build kernel
    if [ ! -s $TMP/iso/boot/vmlinuz64 ]; then
        # Fetch the kernel sources
        _downlock $KERNEL_DOWNLOAD/v${KERNEL_MAJOR_VERSION%.*}.x/linux-$kernel_version.tar.xz - || return $((LINENO / 2));

        # kernel, libc, rootfs
        _install bc || return $(_err_line $((LINENO / 2)));
        _message_queue --put "_make_kernel"; # this may use most time

        _install bison gawk || return $(_err_line $((LINENO / 2)));
        _message_queue --put "_make_glibc"; # this may use long time
        _message_queue --put "_make_busybox";

        # ssl
        _message_queue --put "__make_zlib";
        _message_queue --put "_make_openssl";

        _install python || return $(_err_line $((LINENO / 2)));
        _message_queue --put "_make_ca_certificates";
        _message_queue --put "_make_openssh";

        # firewall
        _message_queue --put "_make_iptables";

        # dev
        _message_queue --put "_make_mdadm";
        _message_queue --put "__make_util_linux";

        _install gperf || return $(_err_line $((LINENO / 2)));
        _message_queue --put "_make_eudev";

        _install pkg-config || return $(_err_line $((LINENO / 2)));
        _message_queue --put "_make_lvm2";

        # sshfs
        _install re2c python3 || return $(_err_line $((LINENO / 2)));
        _message_queue --put "_build_meson";
        _message_queue --put "_make_fuse";

        _install libbz2-dev libreadline-dev || return $(_err_line $((LINENO / 2)));
        _message_queue --put "__make_pcre";

        _install libffi-dev gettext || return $(_err_line $((LINENO / 2)));
        _message_queue --put "__make_glib";

        _install python-docutils || return $(_err_line $((LINENO / 2)));
        _message_queue --put "_make_sshfs";

        _message_queue --put "_make_curl";
        # _message_queue --put "_make_perl5";
        _message_queue --put "__make_libcap2";

        # add file
        _message_queue --put "_create_etc";
        _message_queue --put "_apply_rootfs";

        _downlock $GLIBC_DOWNLOAD/glibc-$glibc_version.tar.xz || return $((LINENO / 2));

        _downlock $BUSYBOX_DOWNLOAD/busybox-$busybox_version.tar.bz2 || return $((LINENO / 2));

        _downlock $ZLIB_DOWNLOAD/zlib-$zlib_version.tar.gz || return $((LINENO / 2)); # for openssl

        _downlock $OPENSSL_DOWNLOAD/openssl-$OPENSSL_VERSION.tar.gz || return $((LINENO / 2));

        curl --retry 10 -L -o $TMP/${CERTDATA_DOWNLOAD##*/} $CERTDATA_DOWNLOAD || return $((LINENO / 2));

        _downlock $CA_CERTIFICATES_DOWNLOAD || return $((LINENO / 2));

        _downlock $OPENSSH_DOWNLOAD/openssh-$openssh_version.tar.gz || return $((LINENO / 2));
        # _downlock $DROPBEAR_DOWNLOAD/dropbear-$dropbear_version.tar.bz2 || return $((LINENO / 2));

        _downlock $IPTABLES_DOWNLOAD/files/iptables-$iptables_version.tar.bz2 || return $((LINENO / 2));

        _downlock $MDADM_DOWNLOAD/mdadm-$mdadm_version.tar.xz || return $((LINENO / 2));

        _downlock $UTIL_LINUX_DOWNLOAD/v$UTIL_LINUX_MAJOR_VERSION/util-linux-$util_linux_version.tar.xz || return $((LINENO / 2));

        _downlock $EUDEV_DOWNLOAD/eudev-$eudev_version.tar.gz || return $((LINENO / 2));

        _downlock $LVM2_DOWNLOAD/LVM$lvm2_version.tgz || return $((LINENO / 2));

        git clone -b release --depth 1 $NINJA_REPOSITORY $TMP/ninja-release || return $((LINENO / 2));

        git clone --depth 1 $MESON_REPOSITORY $TMP/meson-master || return $((LINENO / 2));

        _downlock $LIBFUSE_DOWNLOAD/archive/fuse-$libfuse_version.tar.gz || return $((LINENO / 2));

        _downlock $GLIB_DOWNLOAD/$GLIB_MAJOR_VERSION/glib-$glib_version.tar.xz || return $((LINENO / 2));

        _downlock $PCRE_DOWNLOAD/pcre-$pcre_version.tar.bz2 || return $((LINENO / 2));

        _downlock $SSHFS_DOWNLOAD/archive/sshfs-$sshfs_version.tar.gz || return $((LINENO / 2));

        _downlock $LIBCAP2_DOWNLOAD/libcap-$libcap2_version.tar.xz || return $((LINENO / 2));

        _downlock $CURL_DOWNLOAD/curl-$curl_version.tar.xz || return $((LINENO / 2));

        # _downlock $PERL5_DOWNLOAD/perl-$perl5_version.tar.bz2 || return $((LINENO / 2));
    fi

    # Get the Docker binaries with version.
    _downlock "$DOCKER_DOWNLOAD/docker-$docker_version.tgz" - || return $((LINENO / 2));

    # for '_build_iso'
    _install cpio genisoimage isolinux syslinux xorriso xz-utils || return $((LINENO / 2));

    _message_queue --destroy; wait; # close queue

    # test queue error
    [ -s $TMP/.error ] && {
        ls $TMP/*.lock 2>/dev/null;
        return $(cat $TMP/.error)
    };

    echo " ------------ install docker ----------------------";
    mkdir -pv $ROOTFS/usr/local/bin;
    tar -zxvf $TMP/docker.tgz -C $ROOTFS/usr/local/bin --strip-components=1 || return $((LINENO / 2));

    echo " -------------- run chroot ------------------------";
    mkdir -pv $ROOTFS/dev;
    mknod -m 666 $ROOTFS/dev/null c 1 3;
    mknod -m 666 $ROOTFS/dev/zero c 1 5;

    # fix: PRNG is not seeded
    mknod -m 666 $ROOTFS/dev/random c 1 8;
    mknod -m 644 $ROOTFS/dev/urandom c 1 9;

    # refresh libc cache
    chroot $ROOTFS ldconfig;

    # create ssh key and test docker command
    chroot $ROOTFS sh -xc 'ssh-keygen -A && docker -v' || return $((LINENO / 2));

    echo "-------------- addgroup --------------------------";
    # for dockerd: root map user
    # set up subuid/subgid so that "--userns-remap=default" works out-of-the-box (see also src/rootfs/etc/sub{uid,gid})
    chroot $ROOTFS sh -xc 'addgroup -S dockremap && adduser -S -G dockremap dockremap';
    echo "dockremap:165536:65536" | tee $ROOTFS/etc/subgid > $ROOTFS/etc/subuid;

    # add user: tc
    chroot $ROOTFS sh -xc 'addgroup -S docker && \
        adduser -s /bin/sh -G staff -D tc && \
        addgroup tc docker && \
        printf "tc:tcuser" | /usr/sbin/chpasswd -m';
	printf "tc\tALL=NOPASSWD: ALL" >> $ROOTFS/etc/sudoers;

    # clear dev
    rm -frv $ROOTFS/{dev,var}/*;

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
        rm -fr $TMP/*-* $TMP/LVM2*
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
