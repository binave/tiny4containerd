#!/bin/sh

# create empty config
[ -s $PERSISTENT_DATA/tiny/etc/env.cfg ] || printf \
    "# set environment variable\n\n" > \
    $PERSISTENT_DATA/tiny/etc/env.cfg;

# filter env
{
    /usr/bin/awk -F# '{print $1}' $PERSISTENT_DATA/tiny/etc/env.cfg 2>/dev/null | \
        /bin/sed 's/[\|\;\&]/\n/g;s/export//g;s/^[ ]\+//g' | /bin/grep '^[_A-Z]\+=';
    echo
} > /etc/profile.d/local_envar.sh;
