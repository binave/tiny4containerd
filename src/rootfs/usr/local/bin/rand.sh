#!/bin/sh

openssl rand -base64 ${1:-9} | tr -d '\n' | sed "s/[^0-9A-Za-z]/${RANDOM:0:1}/g";
printf "\n"
