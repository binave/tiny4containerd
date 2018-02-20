#!/bin/sh
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

# dockerd start script
[ $(id -u) = 0 ] || { echo 'must be root' >&2; exit 1; }

# import settings from env (e.g. HTTP_PROXY, HTTPS_PROXY)
[ -s /etc/env ] && . /etc/env;

: ${IF_PREFIX:=eth};
: ${CONTAINERD_ULIMITS:="1048576"};
: ${CONTAINERD_HOST:='-H tcp://0.0.0.0:2375'};
: ${CONTAINERD_USER:=tc};

: ${ORG:="tinycorelinux"};
: ${SERVER_ORG:="$ORG"};
: ${CA_ORG:="${ORG}CA"};
: ${CERT_DAYS:=365};

: ${WAIT_LIMIT:=20};

Ymd=`date +%Y%m%d`;
CERT_INTERFACES="switch0 ${IF_PREFIX}0 ${IF_PREFIX}1 ${IF_PREFIX}2 ${IF_PREFIX}3 ${IF_PREFIX}4";

CONTAINERD_LOG="/log/tiny/${Ymd:0:6}/${0##*/}_$Ymd.log";
CONTAINERD_DIR="/var/${0##*/}ata";

SERVER_TLS_DIR="/var/tiny/tls";
SERVER_KEY="$SERVER_TLS_DIR/serverkey.pem";
SERVER_CSR="$SERVER_TLS_DIR/servercsr.pem";
SERVER_CERT="$SERVER_TLS_DIR/server.pem";
SERVER_EXTFILE="$SERVER_TLS_DIR/srvextfile.txt";

CA_KEY="$SERVER_TLS_DIR/cakey.pem";
CA_CERT="$SERVER_TLS_DIR/ca.pem";

CLIENT_TLS_DIR="/home/$CONTAINERD_USER/.docker";
CLIENT_KEY="$CLIENT_TLS_DIR/key.pem";
CLIENT_CSR="$CLIENT_TLS_DIR/csr.pem";
CLIENT_CERT="$CLIENT_TLS_DIR/cert.pem";
CLIENT_EXTFILE="$CLIENT_TLS_DIR/cliextfile.txt";

_start() {
    _check && {
        printf "container already running.\n";
        return 0
    };

    [ -e "/etc/docker" ] || {
        mkdir -p "/var/tiny/etc/docker";
        ln -sf "/var/tiny/etc/docker" "/etc/docker"
    };

    _install_tls;

    # Server args
    EXTRA_ARGS="$EXTRA_ARGS --tlsverify --tlscacert=$CA_CERT --tlscert=$SERVER_CERT --tlskey=$SERVER_KEY";

    # now make the client certificates available to the client user
    mkdir -p "$CONTAINERD_DIR" "${CONTAINERD_LOG%/*}";
    chown -R $CONTAINERD_USER:staff "$CLIENT_TLS_DIR";

    # Increasing the number of open files and processes by docker
    ulimit -n $CONTAINERD_ULIMITS;
    ulimit -p $CONTAINERD_ULIMITS;

    printf %s "------------------------------
dockerd --data-root \"$CONTAINERD_DIR\" -H unix:// $CONTAINERD_HOST $EXTRA_ARGS >> \"$CONTAINERD_LOG\"
" >> "$CONTAINERD_LOG";

    dockerd --data-root "$CONTAINERD_DIR" -H unix:// $CONTAINERD_HOST $EXTRA_ARGS >> "$CONTAINERD_LOG" 2>&1 &

    [ $? == 0 ] || return 1

    printf "container daemon is running.\n";
    _start_container
}

_srv_ext_var() {
    printf %s "subjectAltName = IP:$(hostname -i)";
    local ip interface;
    for interface in ${CERT_INTERFACES};
    do
        for ip in $(ip addr show $interface 2>/dev/null | sed -nEe 's/^[ \t]*inet[ \t]*([0-9.]+)\/.*$/\1/p');
        do
            printf %s ",IP:$ip";
        done
    done
    printf "\nextendedKeyUsage = serverAuth\n"
}

# config: /home/*/.container_start
_start_container(){
    local count line exclude exiteds
    for count in `seq 0 $WAIT_LIMIT`;
    do
        [ -S /var/run/docker.sock ] && break;
        sleep 0.5
    done

    [ $count == $WAIT_LIMIT ] && {
        printf "[ERROR] Cannot connect to the Docker daemon at unix:///var/run/docker.sock.\n" >&2;
        return 1
    };

    # dot run, format like: [id-0]\|[id-1]\|[id-2]
    exclude=$(awk -F# '{print $1}' /home/*/.container_start 2>/dev/null | awk -F! '{print $2}' | awk '{printf $_" "}' | sed 's/\s\+/ /g;s/\s$\|^\s//g;s/\s/\\\|/g')
    while read line;
    do
        [ "$line" == "" ] && continue;

        # sleep some sec
        echo $line | grep -q '^sleep [.0-9]\+$' && {
            $line;
            continue
        };

        if [ "$exclude" ]; then
            # trim container id
            docker start $(echo $line | sed 's/\s/\n/g' | grep -v "$exclude" | awk '{printf " "$_}');
            exclude="$(echo $exclude $line | sed 's/\s/\\\|/g')"
        else
            docker start $line;
            exclude="$(echo $line | sed 's/\s/\\\|/g')"
        fi
    done <<-SH
    `awk -F#\|! '{print $1}' /home/*/.container_start 2>/dev/null | sed 's/\s\+/ /g;s/\s$\|^\s//g' | grep -v '^$'`
SH

    # others
    if [ "$exclude" ]; then
        exiteds="$(docker ps -f status=exited --format '{{.ID}} {{.Names}}' | grep -v "$exclude" | awk '{print $1}')"
    else
        exiteds="$(docker ps -f status=exited -q | awk '{printf " "$1}')"
    fi

    [ "$exiteds" ] && docker start $exiteds

}

_stop() {
    _stop_container;

    local PID=$(cat /var/run/docker.pid) || return 1;
    kill $PID;
    while kill -0 $PID &>/dev/null;
    do
        sleep 0.1
    done
    printf "container daemon is stop.\n"
}

# stop all container by config
_stop_container(){
    local exiteds=$(docker ps -q | awk '{printf " "$1}') || return 1;
    [ "$exiteds" ] && docker stop $exiteds
}

_restart() {
    local sum;
    if _check; then
        _stop;
        for sum in $(seq 0 $WAIT_LIMIT);
        do
            _check || break;
            sleep 1
        done
        [ $sum == $WAIT_LIMIT ] && { echo "[ERROR] Failed to stop container dameon. '$sum'"; return 1; }
    fi
    _start
}

_check() {
    ps -A -o pid | grep -q "^\s*$(cat /var/run/docker.pid 2>/dev/null)$" && return 0;
    return 1
}

_status() {
    printf 'container daemon is';
    _check || printf ' not';
    printf ' running\n';
    return 0
}

# -subj
#     /C=${COUNTRY}
#     /ST=${STATE}
#     /L=${CITY}
#     /O=${ORGANIZATION}
#     /OU=${ORGANIZATIONAL_UNIT}
#     /CN=${COMMON_NAME:=HOSTNAME,IP}
#     /emailAddress=${EMAIL}
_install_tls() {

    local ext_var ext_text;

    ext_var=$(_srv_ext_var);
    ext_text=$(cat "$SERVER_EXTFILE" 2>/dev/null);

    # test extfile same
    [ "$ext_var" == "$ext_text" ] && return 0;

    rm -fr "$SERVER_TLS_DIR" "$CLIENT_TLS_DIR";
    mkdir -p "$SERVER_TLS_DIR" "$CLIENT_TLS_DIR";
    chmod 700 "$SERVER_TLS_DIR" "$CLIENT_TLS_DIR";

    # write override
    printf "$ext_var" | tee "$SERVER_EXTFILE";
    printf '\n';
    printf "extendedKeyUsage = clientAuth" | tee "$CLIENT_EXTFILE";
    printf '\n';

    #----- CA -----#

    # Generating CA cert
    openssl genrsa -out $CA_KEY 4096;

    # Generate CA
    openssl req -new -x509 -days $CERT_DAYS -key $CA_KEY -out $CA_CERT -subj "/CN=$CA_ORG";

    #----- Server -----#

    # Create the Server Key
    openssl genrsa -out $SERVER_KEY 4096;

    # Create the Server Csr
    openssl req -new -key $SERVER_KEY -out $SERVER_CSR -subj "/CN=$SERVER_ORG";

    # Generating Server Certs
    openssl x509 -req -days $CERT_DAYS -in $SERVER_CSR -CA $CA_CERT -CAkey $CA_KEY -CAcreateserial -out $SERVER_CERT -extfile $SERVER_EXTFILE;

    #----- Client -----#

    # Create the Client Key
    openssl genrsa -out "$CLIENT_KEY" 4096;

    # Create the Client Csr
    openssl req -new -key "$CLIENT_KEY" -out $CLIENT_CSR -subj "/CN=client";

    # Generating Client Certs
    openssl x509 -req -days $CERT_DAYS -in $CLIENT_CSR -CA $CA_CERT -CAkey $CA_KEY -CAcreateserial -out $CLIENT_CERT -extfile $CLIENT_EXTFILE;

    return 0

}

case $1 in
    start) _start;;
    stop) _stop;;
    restart) _restart;;
    ""|status) _status;;
    *) echo "Usage ${0##*/} {start|stop|restart|status}" >&2; exit 1
esac
