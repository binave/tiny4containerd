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

# set -x
_() {
    [ "$#" == 0 ] && return 0;
    printf "\nWill execute: '\n";
    echo "$@" | awk '{print "    " $0};fflush(stdout)';
    printf "' -> '$PWD'.\n\n";
    "$@"
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
                "$@" 2>&1 | _prefix "%F %T${1//_/ } ${2##*/}, ";
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

_case() {
    local pre=low suf=upp
    case $1 in
        -u|--up) :;;
        -l|--low) pre=upp suf=low;;
        *) return 1;;
    esac
    shift;
    printf %s "$@" | tr "[:${pre}er:]" "[:${suf}er:]"
}

# autocomplete by version value
_autocomplete() {
    if [ "$1" ]; then
        local path=${1##*/};
        path=($1*$(set | grep _VERSION= | grep -i ${path//-/_} | awk -F= '{print $2}')*);
        if [ ${#path[@]} == 1 -a -e $path ]; then
            printf "$path";
            return 0
        else
            printf "[ERROR] '$1' not found.\n" > $WORK_DIR/.error
        fi
    else
        printf "[ERROR] args is empty.\n" > $WORK_DIR/.error
    fi
    return 1
}

_err() {
    [ -s $WORK_DIR/.error ] || {
        mkdir -p $WORK_DIR;
        printf "[ERROR]: '${IMPORT[${2:-0}]}': $1 line.\n" | tee -a $WORK_DIR/.error
    };
    return 1
}

# Usage: _mkcfg [+-][path]'
# [text]
# '
_mkcfg() {
    local args file_path force=false LF="
";
    file_path="${@%%$LF*}";
    if [ "${file_path:0:1}" == "-" ]; then
        file_path="${file_path:1}";
        force=true # override
    elif [ "${file_path:0:1}" == "+" ]; then
        file_path="${file_path:1}";
        force=true;
        args="-a" # appand
    fi
    if ! $force && [ -s $file_path ]; then
        printf "[WARN] '$file_path' already exist.\n" >&2;
        return 1
    else
        mkdir -p ${file_path%/*};
        printf "\nwill ";
        if [ "$args" ]; then
            printf "appand"
        elif $force; then
            printf "OVERRIDE"
        else
            printf "create"
        fi
        printf " '$file_path' by: '\n";
        echo "${@#*$LF}" | tee $args ${file_path} | awk '{print "    " $0};fflush(stdout)';
        printf "';\n\n"
    fi
    return 0
}

# Usage: _wait4 [file]
_wait4(){
    [ "$1" ] || return 1;
    set $(_autocomplete $CELLAR_DIR/${1##*/}) $2 >/dev/null;
    [ -s $WORK_DIR/.error ] && return 1;
    set ${1##*/} $2 >/dev/null;
    local count=0 times=$((TIMEOUT_SEC / TIMELAG_SEC));
    until [ -f "$LOCK_DIR/$1.lock" ];
    do
        [ $((++count)) -gt $times ] && {
            printf "[ERROR]: '$1' time out\n" | tee -a $WORK_DIR/.error;
            return 1
        };
        sleep $TIMELAG_SEC
    done
    if [ -f $CELLAR_DIR/$1 ]; then
        _untar $CELLAR_DIR/$1 $2 || return 1;
    fi
    rm -f "$LOCK_DIR/$1.lock";
    return 0
}

# decompression
_untar() {
    local _1=$(_autocomplete $1) _2=${2:-$WORK_DIR};
    [ -s $WORK_DIR/.error ] && return 1;
    shift; shift;
    set $_1 $_2 $@ >/dev/null;
    _hash $1 || return 1;
    case $1 in
        *.tar.gz) tar -C $2 $3 -xzf $1 || return 1;;
        *.tar.bz2) tar -C $2 $3 -xjf $1 || return 1;;
        *.tar.xz) bsdtar -C $2 $3 -xJf $1 || return 1;;
        *.tcz) unsquashfs -f -d $2 $1 || return 1;;
        *.tgz) tar -C $2 $3 -zxf $1 || return 1;;
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
    cd $(_autocomplete $WORK_DIR/${1##*/}) || return 1;
    # find $THIS_DIR/patch -type f -iname "${PWD##*/}*$2*.patch" -exec patch -Ntp1 -i {} \;
    return $?
}

# Usage: _last_version [key] [url] [grep_args] [awk args] ...
_last_version() {
    [ -s $WORK_DIR/.error ] && return 1;
    [ $# -ge 4 ] || return 1;
    local key="$1" value tmp;
    # source $ISO_DIR/version
    value=$(eval printf \$$(_case --up $key) 2>/dev/null) || {
        value=$(printf %s "curl -L $2 2>/dev/null | grep $3 | awk $4 $5 $6 $7" | bash | \
            grep '[0-9]' | grep -v 'beta\|[-0-9]rc\|[-0-9]RC' | sed 's/^[^0-9]\+\|\.t.*\|\.zip\|\///g' | \
            sort --version-sort | tail -1);
    };
    tmp=$(_case --up $key);
    unset $tmp; # clear variable from $ISO_DIR/version
    [[ $value == *[0-9]\.[0-9]* ]] && {
        mkdir -p $ISO_DIR;
        eval $key=$value;
        printf "$tmp=$value\n" | tee -a $ISO_DIR/version.swp;
        return 0
    };
    printf "[ERROR]: $tmp is UNKNOWN\n" | tee -a $WORK_DIR/.error;
    return 1
}

# Usage: _downlock [url]
_downlock() {
    mkdir -p $CELLAR_DIR $LOCK_DIR $WORK_DIR;
    [ -s $WORK_DIR/.error ] && return 1;
    if [[ $1 == *\.git\.* ]]; then
        local pre=${1##*/} suf swp;
        pre=${pre%\.git\.*};
        suf=${1##*\.git\.};
        swp="$CELLAR_DIR/$pre-$suf";
        if [ -d "$swp" ]; then
            printf "will update '$swp'.\n";
            local args="--git-dir=$swp/.git --work-tree=$swp";
            git $args checkout .; # reset edit
            git $args clean -d -f; # remove new file
            git $args pull && {
                touch $LOCK_DIR/$pre-$suf.lock;
                return 0
            };
        else
            printf "will clone '$pre' to '$swp'.\n";
            git clone --branch $suf --depth 1 ${1%\.git\.*}.git $swp && {
                touch $LOCK_DIR/$pre-$suf.lock;
                return 0
            };
        fi
        rm -fr "$swp"
    else
        printf "will download '${1##*/}' to '$CELLAR_DIR'.\n";
        if [ ! -f "$CELLAR_DIR/${1##*/}" ]; then
            mkdir -p $CELLAR_DIR;
            local swp=$$$RANDOM.$RANDOM;
            curl -L --retry 10 -o $CELLAR_DIR/$swp $1 || {
                rm -f $CELLAR_DIR/$swp;
                printf "[ERROR] download '${1##*/}' fail.\n" | tee -a $WORK_DIR/.error;
                return 1
            };
            mv $CELLAR_DIR/$swp $CELLAR_DIR/${1##*/}
        fi
        touch $LOCK_DIR/${1##*/}.lock;
        return 0
    fi
}

_install() {
    [ -s $WORK_DIR/.error ] && return 1;
    apt-get -y install $* 2>&1 | _prefix "%F %T install ${1:0:5}.., "
}

_init_install() {
    # clear work path
    rm -fr /var/lib/apt/lists/*;
    {
        curl --location --connect-timeout 1 http://www.google.com >/dev/null 2>&1 && \
            printf %s "$DEBIAN_SOURCE" || printf %s "$DEBIAN_CN_SOURCE"
    } | tee /etc/apt/sources.list;
    apt-get update;

    return $?
}
