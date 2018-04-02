#!/bin/sh

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin;

# import settings from profile
for i in /etc/profile.d/*.sh; do [ -r $i ] && . $i; done; unset i;

# create empty config
[ -s $PERSISTENT_PATH/tiny/etc/env.cfg ] || printf \
    "# set environment variable\n\n" > \
    $PERSISTENT_PATH/tiny/etc/env.cfg;

# filter env
{
    awk -F# '{print $1}' $PERSISTENT_PATH/tiny/etc/env.cfg 2>/dev/null | \
        sed 's/[\|\;\&]/\n/g;s/export//g;s/^[ ]\+//g' | grep '^[_A-Z]\+=';
    echo
} > /etc/profile.d/local_envar.sh;
