#!/bin/sh
#   Copyright 2018 bin jin
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

# set static ip, dns, route. e.g. eth0 192.168.1.123 192.168.1.255 255.255.255.0

[ $(id -u) = 0 ] || { echo 'must be root' >&2; exit 1; }

# import settings from env
[ -s /etc/env ] && . /etc/env;

: ${IF_PREFIX:=eth};
: ${IF_CONFIG:='/opt/tiny/etc/if.cfg'};

# init
[ -s $IF_CONFIG ] || printf "# [interface] [ip] [broadcast] [netmask]\n\n" > $IF_CONFIG;

# close dhcp
cat /var/run/udhcpc.eth*.pid 2>/dev/null | xargs kill 2>/dev/null;

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
} || {
    # Trigger the DHCP request sooner (the x64 bit userspace appears to be a second slower)
    /usr/local/etc/init.d/dhcp.sh
    echo "-------- dhcp ----------------"
}
