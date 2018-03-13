# /etc/inittab: init configuration for busybox init.
# Boot-time system configuration/initialization script.
#
::sysinit:/etc/init.d/rc S

# /sbin/getty respawn shell invocations for selected ttys.
tty1::respawn:/sbin/getty -nl /sbin/sulogin 38400 tty1
#tty2::respawn:/sbin/getty 38400 tty2
#tty3::respawn:/sbin/getty 38400 tty3
#tty4::askfirst:/sbin/getty 38400 tty4
#tty5::askfirst:/sbin/getty 38400 tty5
#tty6::askfirst:/sbin/getty 38400 tty6

# Stuff to do when restarting the init
# process, or before rebooting.
::restart:/etc/init.d/rc K
::restart:/sbin/init
::ctrlaltdel:/sbin/reboot
::shutdown:/etc/init.d/rc K
