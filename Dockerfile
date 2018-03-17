FROM debian:stretch-slim

# comment to skip create iso

# ENV TIMEOUT_SEC 600
# ENV TIMELAG_SEC 5

ENV STATE_DIR /tmp
# ENV ISO_DIR $STATE_DIR/iso
ENV OUT_DIR /out
# ENV CELLAR_DIR $STATE_DIR/cellar

# ENV KERNEL_MAJOR_VERSION 4.9
# ENV UTIL_LINUX_MAJOR_VERSION 2.31
# ENV GLIB_MAJOR_VERSION 2.55


# command same as 'docker cp'
COPY src $STATE_DIR/src

# command run in container, can not access local path.
RUN bash $STATE_DIR/src/main.sh tiny4containerd.iso; \
    cat $STATE_DIR/iso/version >/dev/null 2>&1 || exit 1

# print tiny4containerd.is to stdout
CMD ["sh", "-c", "[ -t 1 ] && exec bash || exec cat /out/tiny4containerd.iso"]
