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

# load MD5-based password, use: /usr/bin/openssl passwd -1 [string]
[ $(/usr/bin/id -u) = 0 ] || { echo 'must be root' >&2; return 1; }

# import settings from profile
for i in /etc/profile.d/*.sh; do [ -r $i ] && . $i; done; unset i;

: ${PW_CONFIG:="$PERSISTENT_DATA/tiny/etc/pw.cfg"};

[ -s $PW_CONFIG ] || printf \
    "# [username]:[MD5-based password (/usr/bin/openssl passwd -1 [password])]\n\n" > $PW_CONFIG;

/usr/bin/awk -F# '{print $1}' $PW_CONFIG | /bin/grep '[a-z]\+:[$a-zA-Z\.]\+' | /usr/sbin/chpasswd -e 2>&1 | \
    /bin/grep -q 'password.*changed' || return 1;

# TODO add user

# # no auto login
# echo booting > /etc/sysconfig/noautologin;

# chang sudo
/bin/sed -i 's/NOPASSWD/PASSWD/g' /etc/sudoers && \
    echo -e '\n%staff ALL=(ALL) NOPASSWD: WRITE_CMDS\n' >> /etc/sudoers;

# sudo -i, -s mast use root password
/usr/bin/awk -F# '{print $1}' $PW_CONFIG | /bin/grep -q 'root:[$a-zA-Z\.]\+' && \
    printf '\nDefaults rootpw\n\n' >> /etc/sudoers

exit $?
