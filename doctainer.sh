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
declare -xr temp_file=$(mktemp -u)


# The usage function.
usage() {
    echo "Usage: $0 command service [options]"
    echo "  command: notify|wait"
    echo "  service: the service name"
    exit 1
}
# call usage() function if parameters not supplied
[[ $# -eq 0 ]] && usage


# Prints out error messages along with other status information.
err() {
  echo "[$(date +'%d-%m-%YT%H:%M:%S%z')]: $@" >&2
}


# Sets up a trap to delete the temp file when the script exits.
trap '[[ -f "$temp_file" ]] && rm -f "$temp_file"' EXIT


# Checks whether the engine is running.
# @return 0 if the engine works, otherwise >0
etcd_exist() {
    local -r rslt=$(curl -L $ETCD_URL/version 2>/dev/null)
    if [[ -z "$rslt" ]]; then # no response
        err "no response (etcd not running?)"
        return 2
    fi
    if ! grep -q "etcdserver" <<<$rslt; then # bad response
        err "bad response"
        return 3
    fi
    echo "* etcd engine found and working: ${ETCD_URL}"
}


# Checks existing service and wait for it if does not exist right now.
# @param $1 the service name
# @param $2 how long to wait, default=0s (forever)
# @return 0 if service found, 1 for timeout, >=10 for errors
etcd_wait() {
    local -r TIMEOUT=${2:-0} # timeout: default value

    etcd_exist
    if [ $? -ne 0 ]; then return 10; fi

    if [ -z "$1" ]; then
        err "missing service name"
        return 11
    fi

    echo "* checking for service '$1'"
    local rslt=''
    # check if the service already exists
    curl -i --silent --output $temp_file $ETCD_URL/v2/keys/service/$1
    if ! grep -q "errorCode" $temp_file; then # no error, the service is here
        echo "* service '$1' already there"
        rslt=$(grep 'key.*value' $temp_file)
    else # we need to wait for the service
        echo "* service '$1' not there -> wait for $TIMEOUT second(s)..."
        # extract the Etcd-Index from header
        local etcdIndex=$(grep '^X-Etcd-Index' $temp_file | awk '{print $2}')
        echo "* etcd event index: $etcdIndex"

        rslt=$(curl --silent --max-time $TIMEOUT $ETCD_URL/v2/keys/service/$1?wait=true&waitIndex=$etcdIndex)
        if [ -z "$rslt" ]; then # blank response -> timeouted
            echo "WARN: timeout"
            return 1
        fi
    fi

    # parse JSON about the service
    local -r status=$(echo ${rslt} | sed -n 's/.*value":"\([a-z]*\).*/\1/p')
    case ${status} in
        "running") echo "* service '$1': $status"; return 0 ;;
        *) err "unknown status: $status"; return 12 ;;
    esac
}


# Notifies all waiting clients that a given service is available.
# @param $1 the service name
# @param $2 the new state, default=running
# @return 0 if notifying ok, otherwise >1
etcd_notify() {
    local -r state=${2:-running} # state: default value

    etcd_exist
    if [ $? -ne 0 ]; then return 10; fi

    if [ -z "$1" ]; then # blank response
        err "missing service name"
        return 11
    fi

    echo "* service '$1' notified, value=${state}"
    curl -X PUT $ETCD_URL/v2/keys/service/$1 -d value=${state} --output /dev/null 2>/dev/null
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
            err "unknown command"
            ;;
    esac
}

main "$@"
