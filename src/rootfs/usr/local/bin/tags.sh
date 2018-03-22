#!/bin/sh

# test args
[ "$1" ] || exit 1;

curl -Ls https://index.docker.io/v1/repositories/$1/tags | sed 's/,/\n/g' | \
    grep name | awk -F: '{gsub(/[^0-9A-Za-z.:-]/,"");print "'$1':"$2}';

exit 0
