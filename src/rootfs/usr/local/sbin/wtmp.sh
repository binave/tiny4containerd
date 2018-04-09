#!/bin/busybox ash
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

[ $(id -u) = 0 ] || { echo 'must be root' >&2; exit 1; }

# import settings from profile
envset; for i in /etc/profile.d/*.sh; do [ -r $i ] && . $i; done; unset i;

_incremental() {
    touch $1;
    diff $1 - | grep '^+[^+]' | sed 's/^\+//g' >> $1
}

_latnemercni() {
    touch $1;
    sed '1!G;h;$!d' | diff $1 - | grep '^+[^+]' | \
        grep -v 'still logged in' | sed 's/^\+//g' >> $1
}

YmdH=`date +%Y%m%d%H`;
mkdir -p $PERSISTENT_PATH/log/sys/${YmdH:0:6};

awk -F: '{print $1" "$6}' /etc/passwd | \
while read name home;
do
    if [ -s "$home/.ash_history" ]; then
        awk '{print "'"$name"'$ "$_}' "$home/.ash_history" | \
            _incremental $PERSISTENT_PATH/log/sys/${YmdH:0:6}/history_$YmdH.log;
    fi
done

# > $PERSISTENT_PATH/log/wtmp
last | _latnemercni $PERSISTENT_PATH/log/sys/${YmdH:0:6}/last_${YmdH:0:8}.log
