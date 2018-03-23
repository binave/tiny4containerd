#!/bin/busybox ash

# /etc/init.d/rcK - used by /etc/inittab to shutdown the system.

# /usr/bin/clear;

printf "\n\n[`date`]\n";

# stop container daemon
/usr/local/sbin/containerd stop;

# shutdown script
/usr/bin/find $PERSISTENT_PATH/tiny/etc/init.d -type f -perm /u+x -name "K*.sh" -exec /bin/sh -c {} \;

/usr/local/bin/wtmp;

# PID USER COMMAND
/bin/ps -ef | /bin/grep "crond\|monitor\|ntpd\|sshd\|udevd" | /usr/bin/awk "{print \"kill \"\$1}" | /bin/sh 2>/dev/null
