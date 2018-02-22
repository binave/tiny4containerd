#!/bin/bash

: ${OUTPUT_PATH:=$1};
: ${TIMEOUT_SEC:=600};
: ${TIMELAG_SEC:=5};
: ${TMP:=/tmp};

CORES=$(nproc);
LABEL=`date +tc-%y%m%d-%H`;
ROOTFS=$TMP/rootfs;

# linux
: ${KERNEL_MAJOR_VERSION:=4.9};
KERNEL_DOWNLOAD=https://www.kernel.org/pub/linux/kernel;

BUSYBOX_DOWNLOAD=https://www.busybox.net/downloads;

LIBCAP2_DOWNLOAD=https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2;

ZLIB_DOWNLOAD=http://www.zlib.net;

DROPBEAR_DOWNLOAD=https://matt.ucc.asn.au/dropbear;

IPTABLES_DOWNLOAD=http://netfilter.org/projects/iptables;

# http://neil.brown.name/blog/mdadm
MDADM_DOWNLOAD=https://www.kernel.org/pub/linux/utils/raid/mdadm;

LVM2_DOWNLOAD=http://mirrors.kernel.org/sourceware/lvm2;

OPENSSL_VERSION=1.0.2n;
OPENSSL_DOWNLOAD=https://www.openssl.org/source;

CURL_DOWNLOAD=https://curl.haxx.se/download;

# docker
DOCKER_DOWNLOAD=https://download.docker.com/linux/static/stable/x86_64;

GIT_DOWNLOAD=https://www.kernel.org/pub/software/scm/git;

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

# libcurl-devel
APT_GET_LIST_MAKE="
    automake
    bc bsdtar build-essential
    curl
    kmod
    libc6 libc6-dev libcap-dev
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

# apt-get install -y ncurses-dev
# make allnoconfig
# make ARCH=x86_64 menuconfig
