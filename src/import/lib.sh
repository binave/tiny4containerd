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

# Tag prefix each line, support `date` format
_prefix() {
    [ "$1" ] || return 1;
    if [ "${1/\%/}" == "$1" ]; then
        awk '{print '"$1"' $0};fflush(stdout)'
    else
        if which gawk >/dev/null; then
            gawk '{print strftime("'"$1"'") $0};fflush(stdout)';
        elif which perl >/dev/null; then
            perl -ne 'use POSIX qw(strftime); print strftime("'"$1"'", localtime), $_'
        else
            return 1;
        fi
    fi
}

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

                    eval set ${cmd//%34/\\\"} >/dev/null;

                    # run command with log
                    "$@" 2>&1 | _prefix "%F %T${1//_/ }, "

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

# thread valve
_thread_valve() {
    case $1 in
        # use before loop, need count
        --init)
            mkfifo "/tmp/.thread_valve+$USER+$$+${0//\//\+}.fifo";
            # &5
            exec 5<> "/tmp/.thread_valve+$USER+$$+${0//\//\+}.fifo";
            perl -e 'print "\n" x '$2 >&5
        ;;
        --run)
            shift;
            read -u 5;
            {
                "$@";
                printf "\n" >&5
            } &
        ;;
        # use after loop
        --destroy)
            wait;
            exec 5>&-;
            exec 5<&-
            rm -f "/tmp/.thread_valve+$USER+$$+${0//\//\+}.fifo"
        ;;

    esac
}

_err_line() {
    [ -s $STATE_DIR/.error ] || printf %s $1 > $STATE_DIR/.error;
    return 1
}

# Usage: _wait_file [file]
_wait_file(){
    [ -s $STATE_DIR/.error ] && return 1;
    [ "$1" ] || return 1;
    set ${1##*/};
    local count=0 times=$((TIMEOUT_SEC / TIMELAG_SEC));
    until [ -f "$STATE_DIR/$1.lock" ];
    do
        [ $((++count)) -gt $times ] && {
            printf "[ERROR]: '$1' time out\n" >&2;
            return 1
        };
        sleep $TIMELAG_SEC
    done
    [ -d $CELLAR_DIR/$1 ] || _untar $CELLAR_DIR/$1 || return 1;
    rm -f "$STATE_DIR/$1.lock";
    return 0
}

# decompression
_untar() {
    _hash $1 || return 1;
    case $1 in
        *.tar.gz) tar -C $STATE_DIR -xzf $1 || return 1;;
        *.tar.bz2) tar -C $STATE_DIR -xjf $1 || return 1;;
        *.tar.xz) bsdtar -C $STATE_DIR -xJf $1 || return 1;;
        *.tgz) tar -C $STATE_DIR -zxf $1 || return 1;;
        *) return 1;;
    esac
    return 0
}

_hash() {
    [ -f "$1" ] || return 1;
    local h=$({ cat "$1" | tee >(openssl dgst -sha1 >&2) >(openssl dgst -md5 >&2) | openssl dgst -sha256; } 2>&1 );
    printf "${1##*/}:\n${h//(stdin)= /    }\n";
    return 0
}

# Usage: _try_patch [prefix_name]-
_try_patch() {
    [ "$1" ] || return 1;
    cd $STATE_DIR/$1* || return 1;
    find $THIS_DIR/patch -type f -iname "${PWD##*/}*$2*.patch" -exec patch -Ntp1 -i {} \;
    return $?
}

# Usage: _last_version "[key]=[value_colume]"
_last_version() {
    [ -s $STATE_DIR/.error ] && return 1;
    local key="${@%%=*}" value="${@#*=}" ver;
    [ "$key" == "$value" ] && return 1;
    value=$(grep '[0-9]' <<< "$value" | grep -v 'beta\|[-0-9]rc\|[-0-9]RC' | sed 's/LVM\|\.tgz\|\.zip\|\.tar.*\|\///g' | sort --version-sort | tail -1);
    ver="$(tr "[:lower:]" "[:upper:]" <<< "$key")";
    [[ $value == *[0-9]\.[0-9]* ]] && {
        eval $key=$value;
        printf "$ver=$value\n" | tee -a $ISO_DIR/version.swp;
        return 0
    };
    printf "$ver=UNKNOWN\n";
    return 1
}

# Usage: _downlock [url]
_downlock() {
    [ -s $STATE_DIR/.error ] && return 1;
    local pre=${1##*/} suf swp;

    if [[ $1 == *\.git\.* ]]; then
        pre=${pre%\.git\.*};
        suf=${1##*\.git\.};
        swp="$CELLAR_DIR/$pre-$suf";
        printf "will clone '$pre' to '$swp'.\n";
        if [ -d "$swp" ]; then
            cd $swp;
            git pull && cd - >/dev/null && {
                [ "$2" ] || touch $STATE_DIR/$pre-$suf.lock;
                return 0
            };
        else
            git clone -b $suf --depth 1 ${1%\.git\.*}.git $swp && {
                [ "$2" ] || touch $STATE_DIR/$pre-$suf.lock;
                return 0
            };
        fi
        rm -fr "$swp"
    else
        # have int
        if [ "$pre" != "${pre#*[0-9]}" ]; then
            suf=${pre##*\.t}; # 'gz' 'ar.gz' 'ar.xz' 'ar.bz2'
            if [ "$pre" != "$suf" ]; then
                swp=${pre%%-[0-9]*};
                [ "$swp" == "$pre" ] && pre=${pre%%[0-9]*} || pre=$swp;
                suf=".t$suf";
                printf "will download '$pre$suf' to '$CELLAR_DIR'.\n";
                if [ ! -f "$CELLAR_DIR/$pre$suf" ]; then
                    mkdir -p $CELLAR_DIR;
                    swp=$$$RANDOM.$RANDOM;
                    curl -L --retry 10 -o $CELLAR_DIR/$swp $1 || {
                        rm -f $CELLAR_DIR/$swp;
                        printf "[ERROR] download $pre fail.\n";
                        printf 1 > $STATE_DIR/.error;
                        return 1
                    };
                    mv $CELLAR_DIR/$swp $CELLAR_DIR/$pre$suf
                fi
                [ "$2" ] || touch $STATE_DIR/$pre$suf.lock;
                return 0
            fi
        fi
    fi 2>&1 | _prefix "%F %T download '$pre', "
    return 1
}

_install() {
    [ -s $STATE_DIR/.error ] && return 1;
    apt-get -y install $* 2>&1 | _prefix "%F %T install ${1:0:5}.., "
}

_init_install() {
    # clear work path
    rm -fr /var/lib/apt/lists/*;
    {
        curl -L --connect-timeout 1 http://www.google.com >/dev/null 2>&1 && \
            printf %s "$DEBIAN_SOURCE" || printf %s "$DEBIAN_CN_SOURCE"
    } | tee /etc/apt/sources.list;
    apt-get update;

    return $?
}
