#!/bin/bash

[ "$SHELL" == "/bin/bash" ] || exit 255;

: ${OUTPUT_PATH:=$1};
: ${TIMEOUT_SEC:=600};
: ${TIMELAG_SEC:=5};
: ${TMP:=/tmp};

LABEL=`date +tc-%y%m%d-%H`;
ROOTFS=$TMP/rootfs;
THIS_DIR=$(cd `dirname $0`; pwd);

# linux
: ${KERNEL_MAJOR_VERSION:=4.9};
KERNEL_DOWNLOAD=https://www.kernel.org/pub/linux/kernel;
KERNEL_PATH=$TMP/linux-kernel;

: ${LIBCAP2_VERSION:=2.22};

# docker
DOCKER_DOWNLOAD=https://download.docker.com/linux/static/stable/x86_64;

# tiny core linux
TCL_REPO_BASE=http://www.tinycorelinux.net/8.x/x86_64;

# tce-load -wi [tcz]
#   mdadm: raid-dm-KERNEL
#   iptables: netfilter-KERNEL

# fork: https://github.com/boot2docker/boot2docker/blob/master/Dockerfile
TCZ_DEPS="
    openssh openssl ncurses
    git curl ca-certificates expat2
    iproute2 db
    iptables
    sshfs-fuse glib2 fuse libffi
    lvm2 liblvm2 udev-lib readline
    cryptsetup libgcrypt libgpg-error
    rsync popt
    tar acl attr
    xz liblzma
    pcre bzip2-lib
    ntpclient
    mdadm
    e2fsprogs
    net-tools
    procps
    portmap
    tcp_wrappers
    acpid
";

# debian sources
DEBIAN_SOURCE='deb http://deb.debian.org/debian stretch main
deb http://deb.debian.org/debian stretch-updates main
deb http://security.debian.org stretch/updates main
';

DEBIAN_CN_SOURCE='deb http://ftp.cn.debian.org/debian stretch main contrib non-free
deb-src http://ftp.cn.debian.org/debian stretch main contrib non-free
deb http://ftp.cn.debian.org/debian stretch-updates main contrib non-free
deb-src http://ftp.cn.debian.org/debian stretch-updates main contrib non-free
deb http://ftp.cn.debian.org/debian-security stretch/updates main contrib non-free
deb-src http://ftp.cn.debian.org/debian-security stretch/updates main contrib non-free
';

APT_GET_LIST_MAKE="
    automake
    bc bsdtar build-essential
    curl
    kmod
    libc6 libc6-dev
    pkg-config
    squashfs-tools
    unzip
";

APT_GET_LIST_ISO="
    cpio
    genisoimage
    isolinux
    syslinux
    xorriso xz-utils
";

# import script
. $THIS_DIR/.lib;
. $THIS_DIR/.function;

_main() {
    # set work path
    local docker_version kernel_version;

    # test complete, then pack it
    [ -s $TMP/iso/version ] && {
        cat $TMP/iso/version 2>/dev/null;
        printf "\n";
        _build_iso || return $?;
        return 0
    };

    echo "--------------- apt-get --------------------------";
    # install pkg
    _apt_get_install || return $((LINENO / 2));

    echo "------------ kernel version ----------------------";
    kernel_version=$KERNEL_MAJOR_VERSION.$(curl -L $KERNEL_DOWNLOAD/v${KERNEL_MAJOR_VERSION%.*}.x | \
        grep "linux-$KERNEL_MAJOR_VERSION.*xz" | sed 's/\./ /g' | awk '{print $4}' | sort -n | tail -1);

    [[ $kernel_version == $KERNEL_MAJOR_VERSION.[0-9]* ]] || return $((LINENO / 2));
    echo "KERNEL_VERSION=$kernel_version";

    echo "------------ docker version ----------------------";
    # get docker stable version
    docker_version=$(curl -L $DOCKER_DOWNLOAD | \
        grep 'docker-' | awk -F[\>\<] '{print $3}' | tail -1 | sed 's/docker-//;s/\.tgz//');

    [[ $docker_version == *[0-9].[0-9]* ]] || return $((LINENO / 2));
    echo "DOCKER_VERSION=$docker_version";

    # clear for rebuild
    rm -fr \
        $TMP/*.lock $TMP/.error \
        $TMP/tcz $TMP/libcap-$LIBCAP2_VERSION \
        $ROOTFS $KERNEL_PATH;

    # Make the rootfs, Prepare the build directory ($TMP/iso)
    mkdir -p $ROOTFS $TMP/iso/boot;

    echo "------------- put in queue -----------------------";
    _message_queue --init;

    # is need build kernel
    if [ ! -s $TMP/iso/boot/vmlinuz64 ]; then
        echo "----------- download kernel ----------------------";
        # Fetch the kernel sources
        # http://wiki.tinycorelinux.net/wiki:custom_kernel https://www.kernel.org/
        curl -L --retry 10 -o $TMP/linux-kernel.tar.xz $KERNEL_DOWNLOAD/v${KERNEL_MAJOR_VERSION%.*}.x/linux-$kernel_version.tar.xz || \
            return $((LINENO / 2));

        _message_queue --put "_make_obm";
        _message_queue --put "_make_kernel"; # this may use most time
        _message_queue --put "_make_libcap2";

        echo "----------- download libcap2 ---------------------";
        # Install libcap
        curl -L --retry 10 -o $TMP/libcap2.tar.gz http://ftp.debian.org/debian/pool/main/libc/libcap2/libcap2_$LIBCAP2_VERSION.orig.tar.gz || \
            return $((LINENO / 2));
        touch $TMP/libcap2.tar.gz.lock
    fi

    _message_queue --put "_undep";

    apt-get -y install $APT_GET_LIST_ISO;

    _message_queue --put "_apply_rootfs";
    _message_queue --destroy; # close queue

    echo "------------ download dep ------------------------";
    mkdir $TMP/tcz;

    # Install the TCZ dependencies -> $ROOTFS
    local dep;
    for dep in $TCZ_DEPS;
    do
        printf "\nwill download '$dep.tcz' ...\n";
        curl -L --retry 10 -o $TMP/tcz/$dep.tcz $TCL_REPO_BASE/tcz/$dep.tcz;
        [ $? -gt 0 ] && return $((LINENO / 2))
    done
    touch $TMP/tcz.lock;

    echo "---------- download rootfs -----------------------";
    # Download the rootfs, don't unpack it though:
    curl -L --retry 10 -o $TMP/tc_rootfs.gz $TCL_REPO_BASE/release/distribution_files/rootfs64.gz;

    [ $? -gt 0 ] && return $((LINENO / 2));

    touch $TMP/tc_rootfs.gz.lock;

    echo "---------- download docker -----------------------";
    # Get the Docker binaries with version.
    curl -L --retry 10 -o $TMP/dockerbin.tgz "$DOCKER_DOWNLOAD/docker-$docker_version.tgz" || \
        return $((LINENO / 2));

    wait;

    # test queue error
    [ -s $TMP/.error ] && {
        ls $TMP/*.lock 2>/dev/null;
        return $(cat $TMP/.error)
    };

    echo "------------ install docker ----------------------";
    tar -zxvf $TMP/dockerbin.tgz -C $ROOTFS/usr/local/bin --strip-components=1;

    # test docker command
    chroot $ROOTFS docker -v || return $((LINENO / 2));

    rm -f $TMP/dockerbin.tgz; # clear

    echo "-------------- boot file -------------------------";
    # Copy boot params,
    cd $TMP; # fix: sh: 0: getcwd() failed: No such file or directory

    # add boot file
    cp -rv $THIS_DIR/isolinux $TMP/iso/boot/;
    cp -v \
        /usr/lib/ISOLINUX/isolinux.bin \
        /usr/lib/syslinux/modules/bios/ldlinux.c32 \
        $TMP/iso/boot/isolinux/;

    echo "---------- copy custom rootfs --------------------";
    # Copy our custom rootfs,
    cp -frv $THIS_DIR/rootfs/* $ROOTFS;

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
    printf "kernel-$kernel_version\ndocker-$docker_version" > $TMP/iso/version;

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
