# /etc/inittab init(8) configuration for BusyBox
#
# Copyright (C) 1999-2004 by Erik Andersen <andersen@codepoet.org>
#
#
# Note, BusyBox init doesn't support runlevels.  The runlevels field is
# completely ignored by BusyBox init. If you want runlevels, use sysvinit.
#
#
# Format for each entry: <id>:<runlevels>:<action>:<process>
#
# <id>: WARNING: This field has a non-traditional meaning for BusyBox init!
#
#	The id field is used by BusyBox init to specify the controlling tty for
#	the specified process to run on.  The contents of this field are
#	appended to "/dev/" and used as-is.  There is no need for this field to
#	be unique, although if it isn't you may have strange results.  If this
#	field is left blank, then the init's stdin/out will be used.
#
# <runlevels>: The runlevels field is completely ignored.
#
# <action>: Valid actions include: sysinit, respawn, askfirst, wait, once,
#                                  restart, ctrlaltdel, and shutdown.
#
#       Note: askfirst acts just like respawn, but before running the specified
#       process it displays the line "Please press Enter to activate this
#       console." and then waits for the user to press enter before starting
#       the specified process.
#
#       Note: unrecognized actions (like initdefault) will cause init to emit
#       an error message, and then go along with its business.
#
# <process>: Specifies the process to be executed and it's command line.
#
# Note: BusyBox init works just fine without an inittab. If no inittab is
# found, it has the following default behavior:
#         ::sysinit:/etc/init.d/rcS
#         ::askfirst:/bin/sh
#         ::ctrlaltdel:/sbin/reboot
#         ::shutdown:/sbin/swapoff -a
#         ::shutdown:/bin/umount -a -r
#         ::restart:/sbin/init
#         tty2::askfirst:/bin/sh
#         tty3::askfirst:/bin/sh
#         tty4::askfirst:/bin/sh
#
# Boot-time system configuration/initialization script.
# This is run first except when booting in single-user mode.
::sysinit:/etc/init.d/rc S

# /bin/sh invocations on selected ttys
#
# Note below that we prefix the shell commands with a "-" to indicate to the
# shell that it is supposed to be a login shell.  Normally this is handled by
# login, but since we are bypassing login in this case, BusyBox lets you do
# this yourself...
#
# Start an "askfirst" shell on the console (whatever that may be)
# ::askfirst:-/bin/sh
# Start an "askfirst" shell on /dev/tty2-4
# tty2::askfirst:-/bin/sh
# tty3::askfirst:-/bin/sh
# tty4::askfirst:/sbin/getty 38400 tty4

# /sbin/getty invocations for selected ttys
tty1::respawn:-/bin/login
# tty4::respawn:/sbin/getty 38400 tty5
# tty5::respawn:/sbin/getty 38400 tty6

# Example of how to put a getty on a serial line (for a terminal)
#::respawn:/sbin/getty -L ttyS0 9600 vt100
#::respawn:/sbin/getty -L ttyS1 9600 vt100
#
# Example how to put a getty on a modem line.
#::respawn:/sbin/getty 57600 ttyS2

# Stuff to do when restarting the init process
::restart:/etc/init.d/rc K
::restart:/sbin/init

# Stuff to do before rebooting
::ctrlaltdel:/sbin/reboot
::shutdown:/etc/init.d/rc K
::shutdown:/bin/umount -a -r
::shutdown:/sbin/swapoff -a
