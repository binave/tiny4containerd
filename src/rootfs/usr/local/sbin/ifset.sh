#!/bin/busybox ash

# set static ip, dns, route. e.g. eth0 192.168.1.123 192.168.1.255 255.255.255.0

[ $(/usr/bin/id -u) = 0 ] || { echo 'must be root' >&2; exit 1; }

# import settings from profile
for i in /etc/profile.d/*.sh; do [ -r $i ] && . $i; done; unset i;

: ${IF_PREFIX:='eth'};
: ${IF_CONFIG:="$PERSISTENT_PATH/tiny/etc/if.cfg"};

# init
[ -s $IF_CONFIG ] || printf "# [interface] [ip] [broadcast] [netmask]\n\n" > $IF_CONFIG;

# The DHCP portion is now separated out, in order to not slow the boot down
_dhcp() {
    mkdir -p /var/run;

    # This waits until all devices have registered
    /sbin/udevadm settle --timeout=5;

    echo "-------- dhcp ----------------"
    local n_dev net_devices="$(/usr/bin/awk -F: '/'$IF_PREFIX'.:|tr.:/{print $1}' /proc/net/dev 2>/dev/null)";

    for n_dev in $net_devices;
    do
        /sbin/ifconfig $n_dev | /bin/grep -q "inet addr" || {
            trap 2 3 11;
            /sbin/udhcpc \
                -b -i $n_dev -x hostname:$(/bin/hostname) \
                -p /var/run/udhcpc.$n_dev.pid >/dev/null 2>&1 &

            trap "" 2 3 11;
            /bin/sleep 1
        }
    done
}

# close dhcp
/bin/cat /var/run/udhcpc.$IF_PREFIX*.pid 2>/dev/null | /usr/bin/xargs kill 2>/dev/null;

# set static ip, dns, route. e.g. eth0 192.168.1.123 192.168.1.255 255.255.255.0
/usr/bin/awk -F# '{print $1}' $IF_CONFIG | /bin/grep -q $IF_PREFIX'[0-9].*[0-9\.]' && {
    # set ipv4
    echo "----- static ip --------------"
    /usr/bin/awk -F# '{print $1}' $IF_CONFIG | /bin/grep $IF_PREFIX'[0-9].*[0-9\.]' | /usr/bin/awk '{print "ifconfig "$1" "$2" broadcast "$3" netmask "$4" up"}' | /bin/sh
    [ $? == 0 ] && {
        # dns and route
        /usr/bin/awk -F# '{print $1}' $IF_CONFIG | /bin/grep $IF_PREFIX'[0-9].*[0-9\.]' | \
            /usr/bin/head -1 | /usr/bin/awk '{print $3}' | /usr/bin/awk -F\. '{print "nameserver "$1"."$2"."$3"."1}' >> /etc/resolv.conf && \
            /sbin/route add default gw $(/bin/grep '[0-9].*[0-9\.]' /etc/resolv.conf | /usr/bin/head -1 | /usr/bin/awk '{print $2}') || false
        # :
    } || false

# TODO wait for slow network cards
# Trigger the DHCP request sooner (the x64 bit userspace appears to be a second slower)
} || _dhcp
