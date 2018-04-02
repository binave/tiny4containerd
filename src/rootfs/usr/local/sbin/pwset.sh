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

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin;

# load MD5-based password, create user and/or group
[ $(id -u) = 0 ] || { echo 'must be root' >&2; exit 1; }

# import settings from profile
for i in /etc/profile.d/*.sh; do [ -r $i ] && . $i; done; unset i;

: ${PW_CONFIG:="$PERSISTENT_PATH/etc/pw.cfg"};

[ -s $PW_CONFIG ] || printf "# [username]:[[group]]:[MD5-based password]\n\
# 'MD5-based password':    openssl passwd -1 [password]\n\n" > $PW_CONFIG;

awk -F# '{print $1}' $PW_CONFIG | \
    awk '{print $1}' | \
    grep '^[a-z]\+:[a-zA-Z]\+\?:[$A-Za-z0-9\/\.]\+$' | \
    awk -F: '{print $1" "$3" "$2}' | \
while read user passwd group;
do
    # test password length
    [ ${#passwd} == 34 ] || continue;
    is_add_user=false is_add_group=false;

    # test group exist
    [ "$group" ] || group=$user;
    awk -F# '{print $1}' /etc/group | awk '{print $1}' | \
        grep -q ^$group: || {
            addgroup -S $group && is_add_group=true
        };

    # add user
    if id $user >/dev/null 2>&1; then
        addgroup $user $group
    else
        adduser -s sh -G $group -D $user && is_add_user=true
    fi

    # update password
    printf "$user:$passwd" | chpasswd -e 2>&1 | \
        grep -q 'password.*changed' || {
        $is_add_user && [ \
            "$user" != "root" -a \
            "$user" != "dockremap" -a \
            "$user" != "nobody" \
            "$user" != "lp" -a \
        ] && deluser $user;
        $is_add_group && [ \
            "$user" != "root" -a \
            "$user" != "dockremap" -a \
            "$user" != "nogroup" -a \
            "$user" != "lp" -a \
            "$user" != "staff" -a \
            "$user" != "docker" \
        ] && delgroup $group;

        # TODO $shell

        printf "Failed to change the password for '$user:$group'.\n" >&2;
        continue
    };

    printf "Successfully changed '$user:$group' password.\n";

    # sudo -i, -s mast use root password
    [ "$user" == "root" ] && printf '\nDefaults rootpw\n\n' >> /etc/sudoers;

done

exit 0
