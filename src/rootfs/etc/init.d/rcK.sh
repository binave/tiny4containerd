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
ps -ef | grep -v ':[0-9][0-9] \[' | \
    awk "{print \"kill \"\$2}" | sh
