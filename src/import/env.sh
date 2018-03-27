#!/bin/bash

: ${TIMEOUT_SEC:=600};
: ${TIMELAG_SEC:=5};
: ${THREAD_COUNT:=2};

: ${STATE_DIR:=$HOME};
: ${ISO_DIR:=$STATE_DIR/iso};
: ${OUT_DIR:=$STATE_DIR/out};
: ${CELLAR_DIR:=$STATE_DIR/cellar};

: ${KERNEL_MAJOR_VERSION:=4.9};
: ${UTIL_LINUX_MAJOR_VERSION:=2.31};
: ${GLIB_MAJOR_VERSION:=2.55};

LOCK_DIR=$STATE_DIR/lock;
ROOTFS_DIR=$STATE_DIR/rootfs;
WORK_DIR=$STATE_DIR/work;
CORES_COUNT=$(nproc);
LABEL=`date +tc-%y%m%d-%H`;

# linux
KERNEL_PUB=https://cdn.kernel.org/pub; # https://mirrors.edge.kernel.org/pub

# base
KERNEL_DOWNLOAD=$KERNEL_PUB/linux/kernel;
GLIBC_DOWNLOAD=https://ftp.gnu.org/gnu/libc;
BUSYBOX_DOWNLOAD=https://www.busybox.net/downloads;

# ssl
MAKE_CA=https://raw.githubusercontent.com/djlucas/make-ca/master/make-ca; # text file
CERTDATA_DOWNLOAD=http://anduin.linuxfromscratch.org/BLFS/other/certdata.txt;
CA_CERTIFICATES_REPOSITORY=https://salsa.debian.org/debian/ca-certificates.git;
ZLIB_DOWNLOAD=http://www.zlib.net;
OPENSSL_VERSION=1.0.2n;
OPENSSL_DOWNLOAD=https://www.openssl.org/source;
OPENSSH_DOWNLOAD=http://ftp.openbsd.org/pub/OpenBSD/OpenSSH/portable; # DROPBEAR_DOWNLOAD=https://matt.ucc.asn.au/dropbear;

# firewall
IPTABLES_DOWNLOAD=http://netfilter.org/projects/iptables/files;

# dev
MDADM_DOWNLOAD=$KERNEL_PUB/linux/utils/raid/mdadm; # http://neil.brown.name/blog/mdadm
UTIL_LINUX_DOWNLOAD=$KERNEL_PUB/linux/utils/util-linux;
EUDEV_DOWNLOAD=https://dev.gentoo.org/~blueness/eudev;
LVM2_DOWNLOAD=https://sourceware.org/ftp/lvm2/releases;

# sshfs
MESON_REPOSITORY=https://github.com/mesonbuild/meson.git; # master
NINJA_REPOSITORY=https://github.com/ninja-build/ninja.git; # release
PCRE_DOWNLOAD=https://ftp.pcre.org/pub/pcre; # not pcre2
GLIB_DOWNLOAD=http://ftp.gnome.org/pub/gnome/sources/glib;
SSHFS_DOWNLOAD=https://github.com/libfuse/sshfs;
LIBFUSE_DOWNLOAD=https://github.com/libfuse/libfuse;

# for docker
GIT_DOWNLOAD=$KERNEL_PUB/software/scm/git;
XZ_DOWNLOAD=https://tukaani.org/xz;
# PROCPS_DOWNLOAD=https://jaist.dl.sourceforge.net/project/procps-ng/Production; # PROCPS_REPOSITORY=https://gitlab.com/procps-ng/procps.git; #

# tools
SUDO_DOWNLOAD=http://www.sudo.ws/dist;
CURL_DOWNLOAD=https://curl.haxx.se/download;
E2FSPROGS_DOWNLOAD=$KERNEL_PUB/linux/kernel/people/tytso/e2fsprogs;
LIBCAP2_DOWNLOAD=$KERNEL_PUB/linux/libs/security/linux-privs/libcap2;
APR_CGI_DOWNLOAD=http://apr.apache.org/download.cgi;
SQLITE_DOWNLOAD=http://www.sqlite.org;

DOCKER_DOWNLOAD=https://download.docker.com/linux/static/stable/x86_64; # https://docs.docker.com/install/linux/docker-ce/binaries/#prerequisites
# PERL5_DOWNLOAD=http://www.cpan.org/src/5.0;

IANA_ETC=http://sethwklein.net/iana-etc;
TZ_DATA=https://data.iana.org/time-zones/releases; # http://www.linuxfromscratch.org/lfs/view/stable/chapter06/glibc.html

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

eval $(grep 'CONFIG_LOCALVERSION=' $THIS_DIR/config/kernel.cfg) || return $(_err $LINENO 1)
