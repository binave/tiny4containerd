#!/bin/sh

/usr/bin/openssl rand -base64 ${1:-9} | \
    /usr/bin/tr -d '\n' | \
    /bin/sed "s/[^0-9A-Za-z]/${RANDOM:0:1}/g";

printf "\n"
