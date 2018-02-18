FROM debian:stretch-slim

# comment to skip create iso
ENV OUTPUT_PATH /tiny4containerd.iso

ENV TMP /tmp
# ENV TIMEOUT_SEC 600
# ENV TIMELAG_SEC 5
# ENV KERNEL_MAJOR_VERSION 4.4

# command same as 'docker cp'
COPY src $TMP/src

# command run in container, can not access local path.
RUN bash $TMP/src/build.sh; \
    cat $TMP/iso/version >/dev/null 2>&1

# print tiny4containerd.is to stdout
CMD ["sh", "-c", "[ -t 1 ] && exec bash || exec cat tiny4containerd.iso"]
