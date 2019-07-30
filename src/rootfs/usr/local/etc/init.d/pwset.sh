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
/usr/local/etc/init.d/envset;
for i in /etc/profile.d/*.sh; do [ -r $i ] && . $i; done; unset i;

: ${PW_CONFIG:="/home/etc/pw.cfg"};

[ -s $PW_CONFIG ] || printf "# [username]:[[group]]:[MD5-based password]:[[shell]]\n\
# 'MD5-based password':    openssl passwd -1 [password]\n\n" > $PW_CONFIG;

# test format
awk '/^([[:blank:]]+)?[a-z]+/ && ! /[a-z][0-9a-z]+:([a-z][0-9a-z]+:)?\$1(\$[0-9A-z\/\.]{8}){2}[0-9A-z\/\.]{14,}(:\/[a-z])?/' $PW_CONFIG | grep '[a-z]' 2>&1 && exit 1;

awk '/^([[:blank:]]+)?[a-z]+/{print $1}' $PW_CONFIG | \
    awk -F : '/[a-z][0-9a-z]+:([a-z][0-9a-z]+:)?\$1(\$[0-9A-z\/\.]{8}){2}[0-9A-z\/\.]{14,}(:\/[a-z])?/{
        if ($2 ~ /\$1\$[0-9A-z\/\.]+/) {
            print $1, $2
        } else print $1, $3, $2, $4
    }' | while read user passwd group shell;
do
    is_add_user=false is_add_group=false;

    [ "$group" == "root" ] && continue;

    # shell not exist
    [ "$shell" -a ! -e "$shell" ] && continue;

    # test user
    user_info=$(id $user 2>/dev/null) && {
        if [ "$group" ]; then
            # new group
            if ! grep -q ^$group: /etc/group; then
                addgroup -S $group && is_add_group=true
            fi
            if [ "$user_info" == "${user_info/($group)/}" ]; then
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
        if ! grep -q ^$group: /etc/group; then
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
            "$user" != "nobody" -a \
            "$user" != "lp" \
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

        # close local autologin
        printf "%s\n" booting > /etc/sysconfig/noautologin
    fi
done

exit 0
