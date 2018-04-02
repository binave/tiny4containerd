#!/bin/busybox ash

# /etc/init.d/rcK - used by /etc/inittab to shutdown the system.

# clear;

printf "\n\n[`date`]\n";

# stop container daemon
containerd stop;

# shutdown script
find $PERSISTENT_PATH/etc/init.d -type f -perm /u+x -name "K*.sh" -exec sh -c {} \;

wtmp;

# PID USER COMMAND
ps -ef | grep "crond\|monitor\|ntpd\|sshd\|udevd" | \
    awk "{print \"kill \"\$1}" | sh 2>/dev/null
