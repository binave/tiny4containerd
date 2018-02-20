#!/bin/bash
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

# Message Queue
_message_queue() {
    case $1 in
        --init)
            mkfifo "/tmp/.message_queue+$USER+$$+${0//\//\+}.fifo";
            # &6
            exec 6<> "/tmp/.message_queue+$USER+$$+${0//\//\+}.fifo";
            # make handler
            {
                local cmd;
                time while read -u 6 cmd;
                do
                    [ "$cmd" == "0" ] && {
                        exec 6>&-;
                        exec 6<&-;
                        rm -f "/tmp/.message_queue+$USER+$$+${0//\//\+}.fifo";
                        printf "queue close.\n";
                        break
                    };
                    # run command
                    eval ${cmd//%34/\\\"}
                done
            } &
            printf "queue open.\n"
        ;;
        --put)
            shift;
            local a;
            {
                for a in "$@";
                do
                    a="${a//\"/%34}";
                    [ "${a/ /}" == "$a" ] || a="\"$a\"";
                    printf %s "$a "
                done
                printf "\n"
            } >&6
        ;;
        --destroy)
            printf "0\n" >&6
        ;;
    esac
}

_err_line() {
    [ -s $TMP/.error ] || printf %s $1 > $TMP/.error;
    printf 1
}

# [file] [count_max]
_wait_file(){
    [ -s $TMP/.error ] && return 1;
    [ -f "$1" ] || return 0;
    local count=0 times=$((TIMEOUT_SEC / TIMELAG_SEC));
    until [ -f $1 ];
    do
        [ $((++count)) -gt $times ] && {
            printf "[ERROR]: '${1##*/}' time out\n" >&2;
            return 1
        };
        sleep $TIMELAG_SEC
    done
    return 0
}

_hash() {
    [ -f "$1" ] || return 1;
    local h=$({ cat "$1" | tee >(openssl dgst -sha1 >&2) >(openssl dgst -md5 >&2) | openssl dgst -sha256; } 2>&1 );
    printf "${1##*/}:\n${h//(stdin)= /    }\n";
    return 0
}

_case_version() {
    printf " $*\n$(tr "[:lower:]" "[:upper:]" <<< " ${2}_$3=")" >&2
}

_last_version() {
    local ver=$(sed 's/LVM\|\.tgz\|\.tar.*//g;' | sort --version-sort | tail -1);
    [[ $ver == [0-9]*\.*[0-9]* ]] && {
        printf $ver;
        printf "$ver\n" >&2;
        return 0
    };
    printf "UNKNOWN\n";
    return 1
}

_downlock() {
    local prefix=${1##*/} suffix;
    suffix=${prefix##*[0-9]};
    [ "${suffix:0:1}" != "." ] && suffix=".${suffix#*.}";
    prefix=${prefix%%-*};
    [ "$prefix" == "${1##*/}" ] && prefix="${prefix%%[0-9]*}";
    printf " ----------- download $prefix ---------------------\n";
    curl -L --retry 10 -o $TMP/$prefix$suffix $1 || {
        printf "[ERROR] download $prefix fail.\n";
        return 1
    };
    [ "$2" ] || touch $TMP/$prefix$suffix.lock;
    return 0
}
