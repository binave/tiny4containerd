FROM debian:stretch-slim

# comment to skip create iso

# ENV TIMEOUT_SEC 600
# ENV TIMELAG_SEC 5
# ENV THREAD_COUNT 2

ENV STATE_DIR /tmp
# ENV ISO_DIR $STATE_DIR/iso
ENV OUT_DIR /out
# ENV CELLAR_DIR $STATE_DIR/cellar

# ENV KERNEL_MAJOR_VERSION 4.9
# ENV TCL_MAJOR_VERSION 8


# command same as 'docker cp'
COPY src $STATE_DIR/src

# command run in container, can not access local path.
RUN bash $STATE_DIR/src/main.sh tiny4containerd.iso; \
    test -f $OUT_DIR/tiny4containerd.iso || exit 1

# print tiny4containerd.is to stdout
CMD ["sh", "-c", "[ -t 1 ] && exec bash || exec cat /out/tiny4containerd.iso"]
