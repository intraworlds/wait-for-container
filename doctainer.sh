#!/usr/bin/env bash
#
# Shell script to
#  * service discovery
# and/or
#  * container start synchronization
# for Docker containers running on multiple host.
#
# Author:       vaclav.sykora@intraworlds.com
# Date:         2015-01-20
# Licence:      Copyright 2016 IntraWorlds s.r.o. (MIT LICENCE)
# Dependencies: curl,mktemp,grep,awk,sed,tr,echo
# Example:
#   $ ./doctainer.sh wait foo           # wait for service 'foo' in status 'running' forever (no timeout)
#   $ ./doctainer.sh wait foo -t 2      # wait for service 'foo' in status 'running' for 2 seconds
#   $ ./doctainer.sh wait foo -s bravo  # wait for service 'foo' in status 'bravo' forever


# exit the script when a command fails
set -o errexit

declare -xr etcd_url="${ETCD_URL:-http://127.0.0.1:4001}"
declare -xr temp_file=$(mktemp -u)


# The usage function.
usage() {
    echo "Usage: $0 command service <options>"
    echo "  command: notify|wait"
    echo "  service: the service name"
    echo "  options:"
    echo "    -t timeout: how long to wait (default: 0=forever)"
    echo "    -s state: expected state (default: running)"
    exit 1
}
# call usage() function if parameters not supplied
[[ $# -eq 0 ]] && usage


# Prints out error messages along with other status information.
err() {
  echo "[$(date +'%d-%m-%YT%H:%M:%S%z')]: $@" >&2
}


# Sets up a trap to delete the temp file when the script exits.
trap '[[ -f "${temp_file}" ]] && rm -f "${temp_file}"' EXIT


# Checks whether the 'etcd' engine is running.
# @return 0 if the engine works, otherwise >0
etcd_exist() {
    local -r rslt=$(curl -L ${etcd_url}/version 2>/dev/null)
    if [[ -z "$rslt" ]]; then # no response
        err "no response on ${etcd_url} (etcd not running?)"
        return 2
    fi
    if ! grep -q "etcdserver" <<<$rslt; then # bad response
        err "bad response"
        return 3
    fi
    echo "* etcd engine found and working: ${etcd_url}"
}


# Checks existing service and wait for it if does not exist right now.
# @param $1 the service name
# @param -t timeout how long to wait, default: 0s (forever)
# @param -s status to be expected, default: running
# @return 0 if service found
#         1 for timeout
#         2 if unexpected status received
#         >=10 for errors
etcd_wait() {
    etcd_exist
    if [ $? -ne 0 ]; then return 10; fi

    # get service name
    if [ -z "$1" ]; then
        err "missing service name"
        return 11
    fi
    local -r service=$1
    shift

    # parse options
    local timeout='' # how long to wait
    local estatus='' # expected status
    while getopts ":t:s:" opt; do
        case $opt in
            t)
                timeout=$OPTARG
                ;;
            s)
                estatus=$OPTARG
                ;;
            \?)
                err "invalid option: -$OPTARG"
                exit 11
                ;;
            :)
                err "option -$OPTARG requires an argument"
                exit 11
                ;;
        esac
    done
    timeout=${timeout:-0}
    estatus=${estatus:-running}

    echo "* checking for service '${service}' in status '${estatus}'"
    local rslt=''
    # check if the service already exists
    curl -i --silent --output ${temp_file} ${etcd_url}/v2/keys/service/${service}
    if ! grep -q "errorCode" ${temp_file}; then # no error, the service is here
        echo "* service '${service}' already there"
        rslt=$(grep 'key.*value' ${temp_file})
    else # we need to wait for the service
        echo "* service '${service}' not there -> expected status '${estatus}' in ${timeout} second(s)..."
        # extract the Etcd-Index from header
        local -r etcd_index=$(grep '^X-Etcd-Index' ${temp_file} | awk '{print $2}' | tr -d '\r')
        echo "* etcd event index: '${etcd_index}'"

        rslt=$(curl --silent --max-time ${timeout} ${etcd_url}/v2/keys/service/${service}?wait=true&waitIndex=${etcd_index})
        if [[ -z "$rslt" ]]; then # blank response -> timeouted
            echo "WARN: timeout"
            return 1
        fi
    fi

    # parse JSON about the service
    local -r status=$(echo ${rslt} | sed -n 's/.*value":"\([a-z]*\).*/\1/p')
    if [ "$status" != "$estatus" ]; then
        err "unexpected status: ${status}"
        return 2
    fi

    echo "* status received and OK"
    return 0
}


# Notifies all waiting clients that a given service is available.
# @param $1 the service name
# @param -s status to be fired, default: running
# @return 0 if notifying ok, otherwise >1
etcd_notify() {
    etcd_exist
    if [ $? -ne 0 ]; then return 10; fi

    if [ -z "$1" ]; then # blank response
        err "missing service name"
        return 11
    fi
    local -r service=$1
    shift

    # parse options
    local status='' # fired status
    while getopts ":s:" opt; do
        case $opt in
            s)
                status=$OPTARG
                ;;
            \?)
                err "invalid option: -$OPTARG"
                exit 11
                ;;
            :)
                err "option -$OPTARG requires an argument"
                exit 11
                ;;
        esac
    done
    status=${status:-running}

    echo "* service '${service}' notified, value=${status}"
    curl -X PUT ${etcd_url}/v2/keys/service/${service} -d value=${status} --output /dev/null 2>/dev/null
}


# The script entry point.
main() {
    case "$1" in
        "notify")
            shift
            etcd_notify $@
            ;;
        "wait")
            shift
            etcd_wait $@
            ;;
        *)
            err "unknown command"
            ;;
    esac
    # delete the temp file
    [[ -f "${temp_file}" ]] && rm -f "${temp_file}"
}

main "$@"
