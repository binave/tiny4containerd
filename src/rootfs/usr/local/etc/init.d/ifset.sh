#!/bin/busybox ash

# set static ip, dns, route. e.g. eth0 192.168.1.123 192.168.1.255 255.255.255.0

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin;

[ $(id -u) = 0 ] || { echo 'must be root' >&2; exit 1; }

# import settings from profile
/usr/local/etc/init.d/envset;

for i in /etc/profile.d/*.sh; do [ -r $i ] && . $i; done; unset i;

: ${IF_PREFIX:=eth};
: ${IF_CONFIG:="/home/etc/if.cfg"};

# init
[ -s $IF_CONFIG ] || printf "# [interface] [ip] [broadcast] [netmask]\n\n" > $IF_CONFIG;

# The DHCP portion is now separated out, in order to not slow the boot down
_dhcp() {
    mkdir -p /var/run;

    # This waits until all devices have registered
    udevadm settle --timeout=5;

    echo "-------- dhcp ----------------"
    local n_dev net_devices="$(awk -F: '/'$IF_PREFIX'.:|tr.:/{print $1}' /proc/net/dev 2>/dev/null)";

    for n_dev in $net_devices;
    do
        ifconfig $n_dev | grep -q "inet addr" || {
            trap 2 3 11;
            udhcpc \
                -b -i $n_dev -x hostname:$(hostname) \
                -p /var/run/udhcpc.$n_dev.pid >/dev/null 2>&1 &

            trap "" 2 3 11;
            sleep 1
        }
    done
}

# close dhcp
cat /var/run/udhcpc.$IF_PREFIX*.pid 2>/dev/null | xargs kill 2>/dev/null;

# set static ip, dns, route. e.g. eth0 192.168.1.123 192.168.1.255 255.255.255.0
awk -F# '{print $1}' $IF_CONFIG | grep -q $IF_PREFIX'[0-9].*[0-9\.]' && {
    # set ipv4
    echo "----- static ip --------------"
    awk -F# '{print $1}' $IF_CONFIG | grep $IF_PREFIX'[0-9].*[0-9\.]' | awk '{print "ifconfig "$1" "$2" broadcast "$3" netmask "$4" up"}' | sh
    [ $? == 0 ] && {
        # dns and route
        awk -F# '{print $1}' $IF_CONFIG | grep $IF_PREFIX'[0-9].*[0-9\.]' | \
            head -1 | awk '{print $3}' | awk -F\. '{print "nameserver "$1"."$2"."$3"."1}' >> /etc/resolv.conf && \
            route add default gw $(grep '[0-9].*[0-9\.]' /etc/resolv.conf | head -1 | awk '{print $2}') || false
        # :
    } || false

# TODO wait for slow network cards
# Trigger the DHCP request sooner (the x64 bit userspace appears to be a second slower)
} || _dhcp
