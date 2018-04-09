#!/bin/sh

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin;

[ $(id -u) = 0 ] || { echo 'must be root' >&2; exit 1; }

# import settings from profile
for i in /etc/profile.d/*.sh; do [ -r $i ] && . $i; done; unset i;

# create empty config
[ -s $PERSISTENT_PATH/etc/env.cfg ] || printf \
    "# set environment variable\n\n" > \
    $PERSISTENT_PATH/etc/env.cfg;

# filter environment variables
env_text=$(
    awk -F# '{print $1}' $PERSISTENT_PATH/etc/env.cfg 2>/dev/null | \
        sed 's/[\|\;\&]/\n/g;s/export//g;s/^[ ]\+//g' | grep '^[_A-Z]\+=';
    echo
);

if [ -f /etc/profile.d/local_envar.sh ]; then
    echo "$env_text" | diff - /etc/profile.d/local_envar.sh >/dev/null || \
        echo "$env_text" > /etc/profile.d/local_envar.sh
fi
