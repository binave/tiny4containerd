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
envset; for i in /etc/profile.d/*.sh; do [ -r $i ] && . $i; done; unset i;

: ${PW_CONFIG:="$PERSISTENT_PATH/etc/pw.cfg"};

[ -s $PW_CONFIG ] || printf "# [username]:[[group]]:[MD5-based password]:[[shell]]\n\
# 'MD5-based password':    openssl passwd -1 [password]\n\n" > $PW_CONFIG;

# test group exist
_gd() {
    awk -F# '{print $1}' /etc/group | awk '{print $1}' | grep -q ^$1: && return 0;
    return 1
}

awk -F# '{print $1}' $PW_CONFIG | \
    awk '{print $1}' | \
    grep '^[a-z]\+:[a-zA-Z]\+\?:[$A-Za-z0-9\/\.]\+:\?[A-Za-z0-9\/\.]\+\?$' | \
    awk -F: '{print $1" "$3" \""$4"\" "$2}' | \
while read user passwd shell group;
do
    printf "will parse string: '$user:$group:$passwd:$shell'.\n";
    # test password length and format
    if [ ${#passwd} == 34 -a "${passwd:0:3}${passwd:11:1}" == "\$1\$$" ]; then
        printf "[\033[1;31mERROR\033[0;39m] '$user:$group:$passwd:$shell' password format cannot be recognized\n" >&2;
        continue;
    fi

    is_add_user=false is_add_group=false;

    # test user
    ginf=$(id $user) && {
        if [ "$group" ]; then
            [ "$group" == "root" ] && continue;
            # new group
            if ! _gd $group; then
                addgroup -S $group && is_add_group=true
            fi
            if [ "$ginf" == "${ginf/($group)/}" ]; then
                # add user in group
                addgroup $user $group || {
                    # if error
                    $is_add_group && delgroup $group;
                    continue
                }
            fi
        fi
        :
    } || {
        [ "$group" ] || group=$user; # same as user
        [ "$group" == "root" ] && continue;
        if ! _gd $group; then
            addgroup -S $group && is_add_group=true
        fi
        eval shell=$shell; # trim ""
        [ "$shell" ] && shell="-s $shell";
        adduser $shell -G $group -D $user && is_add_user=true || {
            # if error
            $is_add_group && delgroup $group;
            continue
        }
    };

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

        printf "[\033[1;31mERROR\033[0;39m] Failed to change the password for '$user:$group'.\n" >&2;
        continue
    };

    printf "\033[1;32mSuccessfully changed '$user:$group' password.\033[0;39m\n";

    # sudo -i, -s mast use root password
    if [ "$user" == "root" ]; then
        grep -q 'Defaults rootpw' /etc/sudoers || \
            printf '\nDefaults rootpw\n\n' >> /etc/sudoers
    fi
done

exit 0
