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

# load MD5-based password, create user and/or group
[ $(/usr/bin/id -u) = 0 ] || { echo 'must be root' >&2; exit 1; }

# import settings from profile
for i in /etc/profile.d/*.sh; do [ -r $i ] && . $i; done; unset i;

: ${PW_CONFIG:="$PERSISTENT_DATA/tiny/etc/pw.cfg"};

[ -s $PW_CONFIG ] || printf "# [username]:[[group]]:[MD5-based password]\n\
# 'MD5-based password':    /usr/bin/openssl passwd -1 [password]\n\n" > $PW_CONFIG;

/usr/bin/awk -F# '{print $1}' $PW_CONFIG | \
    /usr/bin/awk '{print $1}' | \
    /bin/grep '^[a-z]\+:[a-zA-Z]\+\?:[$A-Za-z0-9\/\.]\+$' | \
    /usr/bin/awk -F: '{print $1" "$3" "$2}' | \
while read user passwd group;
do
    # test password length
    [ ${#passwd} == 34 ] || continue;
    is_add_user=false is_add_group=false;

    # test group exist
    [ "$group" ] || group=$user;
    /usr/bin/awk -F# '{print $1}' /etc/group | /usr/bin/awk '{print $1}' | \
        /bin/grep -q ^$group: || {
            /usr/sbin/addgroup -S $group && is_add_group=true
    };

    # add user
    if /usr/bin/id $user >/dev/null 2>&1; then
        /usr/sbin/addgroup $user $group
    else
        /usr/sbin/adduser -s /bin/sh -G $group -D $user && is_add_user=true
    fi

    # update password
    printf "$user:$passwd" | /usr/sbin/chpasswd -e 2>&1 | \
        /bin/grep -q 'password.*changed' || {
        $is_add_user && /usr/sbin/deluser $user;
        $is_add_group && /usr/sbin/delgroup $group;
        printf "Failed to change the password for '$user:$group'.\n" >&2;
        continue
    };

    printf "Successfully changed '$user:$group' password.\n";

    # chang sudo
    /bin/sed -i 's/NOPASSWD/PASSWD/g' /etc/sudoers && \
        printf '\n%%staff ALL=(ALL) NOPASSWD: WRITE_CMDS\n' >> /etc/sudoers;

    # sudo -i, -s mast use root password
    [ "$user" == "root" ] && printf '\nDefaults rootpw\n\n' >> /etc/sudoers;

    # # no auto login
    # echo booting > /etc/sysconfig/noautologin;

done

exit 0
