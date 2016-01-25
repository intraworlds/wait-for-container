#!/usr/bin/env bash
#
# Shell script to
#  * service discovery
# and/or
#  * container start synchronization
# for Docker containers running on multiple host.
#
# Copyright 2016 IntraWorlds s.r.o.
# MIT LICENCE
#
# Author:       vaclav.sykora@intraworlds.com
# Date :        2015-01-20
# Dependencies: curl,mktemp,grep,awk,sed,echo
# Example:
#   $ etcd_wait foo     # wait for service 'foo'
#   $ etcd_notify foo   # fire event that service 'foo' is running
#


# exit the script when a command fails
set -o errexit

ETCD_URL="${ETCD_URL:-http://127.0.0.1:4001}"


# The usage function.
usage() {
    echo "Usage: $0 command service [options]"
    echo "  command: notify|wait"
    echo "  service: the service name"
    exit 1
}
# call usage() function if parameters not supplied
[[ $# -eq 0 ]] && usage


# # TODO: set up a trap to delete the temp dir when the script exits
# unset temp_dir
# trap '[[ -d "$temp_dir" ]] && rm -rf "$temp_dir"' EXIT


# Checks whether the engine is running.
# @return 0 if the engine works, otherwise >0
etcd_exist() {
    local -r rslt=$(curl -L $ETCD_URL/version 2>/dev/null)
    if [[ -z "$rslt" ]]; then # no response
        echo "ERR: no response (etcd not running?)" >&2
        return 2
    fi
    if ! grep -q "etcdserver" <<<$rslt; then # bad response
        echo "ERR: bad response" >&2
        return 3
    fi
    echo "* etcd engine found and working: ${ETCD_URL}"
}


# Checks existing service and wait for it if does not exist right now.
# @param $1 the service name
# @param $2 how long to wait, default=0s (forever)
# @return 0 if service found, 1 for timeout, >=10 for errors
etcd_wait() {
    local TIMEOUT=${2:-0} # timeout: default value

    etcd_exist
    if [ $? -ne 0 ]; then return 10; fi

    if [ -z "$1" ]; then
        echo "ERR: missing service name" >&2
        return 11
    fi

    echo "* checking for service '$1'"
    local tempfile=$(mktemp -u)
    local rslt=''
    # check if the service already exists
    curl -i --silent --output $tempfile $ETCD_URL/v2/keys/service/$1
    if ! grep -q "errorCode" $tempfile; then # no error, the service is here
        echo "* service '$1' already there"
        rslt=$(grep 'key.*value' $tempfile)
    else # we need to wait for the service
        echo "* service '$1' not there -> wait for $TIMEOUT second(s)..."
        # extract the Etcd-Index from header
        local etcdIndex=$(grep '^X-Etcd-Index' $tempfile | awk '{print $2}')
        echo "* etcd event index: $etcdIndex"

        rslt=$(curl --silent --max-time $TIMEOUT $ETCD_URL/v2/keys/service/$1?wait=true&waitIndex=$etcdIndex)
        if [ -z "$rslt" ]; then # blank response -> timeouted
            echo "WARN: timeout"
            return 1
        fi
    fi

    # parse JSON about the service
    local status=$(echo $rslt | sed -n 's/.*value":"\([a-z]*\).*/\1/p')
    case $status in
        "running") echo "* service '$1': $status"; return 0 ;;
        *) echo "ERR: unknown status: $status" >&2; return 12 ;;
    esac
}


# Notifies all waiting clients that a given service is available.
# @param $1 the service name
# @param $2 the new state, default=running
# @return 0 if notifying ok, otherwise >1
etcd_notify() {
    local STATE=${2:-running} # state: default value

    etcd_exist
    if [ $? -ne 0 ]; then return 10; fi

    if [ -z "$1" ]; then # blank response
        echo "ERR: missing service name" >&2
        return 11
    fi

    echo "* service '$1' notified, value=$STATE"
    local rslt=$(curl -X PUT $ETCD_URL/v2/keys/service/$1 -d value="$STATE" 2>/dev/null)
}


# The script entry point.
main() {
    case "$1" in
        "notify")
            shift;
            etcd_notify $@;
            ;;
        "wait")
            shift;
            etcd_wait $@;
            ;;
        *)
            echo "ERR: unknown command" >&2
            ;;
    esac
}

main "$@"
