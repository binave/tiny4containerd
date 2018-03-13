#!/bin/bash

: ${OUTPUT_PATH:=$1};
: ${TIMEOUT_SEC:=600};
: ${TIMELAG_SEC:=5};
: ${TMP:=/tmp};

CORES=$(nproc);
LABEL=`date +tc-%y%m%d-%H`;
ROOTFS=$TMP/rootfs;

# linux
KERNEL_PUB=https://cdn.kernel.org/pub;
: ${KERNEL_MAJOR_VERSION:=4.9};
: ${UTIL_LINUX_MAJOR_VERSION:=2.31};
: ${GLIB_MAJOR_VERSION:=2.55};
KERNEL_DOWNLOAD=$KERNEL_PUB/linux/kernel;
UTIL_LINUX_DOWNLOAD=$KERNEL_PUB/linux/utils/util-linux;
LIBCAP2_DOWNLOAD=$KERNEL_PUB/linux/libs/security/linux-privs/libcap2;
MDADM_DOWNLOAD=$KERNEL_PUB/linux/utils/raid/mdadm; # http://neil.brown.name/blog/mdadm
GIT_DOWNLOAD=$KERNEL_PUB/software/scm/git;
# XFSPROGS_DOWNLOAD=$KERNEL_PUB/linux/utils/fs/xfs/xfsprogs;
BUSYBOX_DOWNLOAD=https://www.busybox.net/downloads;
GLIBC_DOWNLOAD=https://ftp.gnu.org/gnu/libc;
NINJA_REPOSITORY=https://github.com/ninja-build/ninja.git; # release
MESON_REPOSITORY=https://github.com/mesonbuild/meson.git; # master
GLIB_DOWNLOAD=http://ftp.gnome.org/pub/gnome/sources/glib;
PCRE_DOWNLOAD=https://ftp.pcre.org/pub/pcre; # not pcre2
SSHFS_DOWNLOAD=https://github.com/libfuse/sshfs;
LIBFUSE_DOWNLOAD=https://github.com/libfuse/libfuse;
CERTDATA_DOWNLOAD=http://anduin.linuxfromscratch.org/BLFS/other/certdata.txt;
CA_CERTIFICATES_DOWNLOAD=https://salsa.debian.org/debian/ca-certificates/repository/master/archive.tar.bz2;
ZLIB_DOWNLOAD=http://www.zlib.net;
OPENSSL_VERSION=1.0.2n;
OPENSSL_DOWNLOAD=https://www.openssl.org/source;
OPENSSH_DOWNLOAD=http://ftp.openbsd.org/pub/OpenBSD/OpenSSH/portable; # DROPBEAR_DOWNLOAD=https://matt.ucc.asn.au/dropbear;
IPTABLES_DOWNLOAD=http://netfilter.org/projects/iptables;
EUDEV_DOWNLOAD=https://dev.gentoo.org/~blueness/eudev;
# READLINE_DOWNLOAD=http://ftp.gnu.org/gnu/readline;
LVM2_DOWNLOAD=https://sourceware.org/ftp/lvm2/releases;
CURL_DOWNLOAD=https://curl.haxx.se/download;
DOCKER_DOWNLOAD=https://download.docker.com/linux/static/stable/x86_64;

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
    bc bsdtar build-essential
    curl
    file
    bison gawk
    git-core
    gperf
    libbz2-dev libreadline-dev
    pkg-config
    python
    python3 python-docutils re2c libglib2.0-dev
";

APT_GET_LIST_ISO="
    cpio
    genisoimage
    isolinux
    syslinux
    xorriso xz-utils
";
