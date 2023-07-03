#! /bin/bash

function check_governor_running(){
    pid=$(status governor | egrep -oi '([0-9]+)$' | head -n1)
    if [ ! -z ${pid} ]; then
        echo "governor is running and active"
    elif [ -z ${pid} ] && [ ! -e '/var/log/governor/.stopped' ]; then
        echo "governor is down and .stopped not found"
        sudo /opt/ibm/db2-governor/governor.sh start
    elif [ -z ${pid} ] && [ -e '/var/log/governor/.stopped' ]; then
        echo "governor is explicitly stopped for maintenace"
    fi
}

if [ "$(id -u)" != "0" ]; then
    echo "This script can only be run as root user" 1>&2
    exit 1

elif [[ $# -lt 1 ]]; then
    echo "governor.sh stop || governor.sh start || governor.sh status || governor.sh etcd || governor.sh leader || governor.sh switch_primary || governor.sh tbspc_health"
    exit 1

elif [[ $1 == "start" ]]; then
    while [[ `status governor | awk -F, '{print $1}' | awk '{print $2}'` != "start/running" ]]; do start governor; done
    if test `status governor | awk -F, '{print $1}' | awk '{print $2}'` == "start/running";then echo "governor is started";fi
    if [ -e '/var/log/governor/.stopped' ]; then
        rm -f /var/log/governor/.stopped
    fi

elif [[ $1 == "stop" ]]; then
    while [[ `status governor | awk -F, '{print $1}' | awk '{print $2}'` != "stop/waiting" ]]; do stop governor; done
    if test `status governor | awk -F, '{print $1}' | awk '{print $2}'` == "stop/waiting";then echo "governor is stopped"; fi
    if [ ! -e '/var/log/governor/.stopped' ]; then
        touch /var/log/governor/.stopped
    fi

elif [[ $1 == "status" ]]; then
    state=`status governor | awk '{print $2}' | awk -F / '{print $2}' | tr -d ,`
    if [[ ${state} == "running" ]]; then 
        echo "GOVERNOR: RUNNING"
    elif [[ ${state} == "waiting" ]]; then
        echo "GOVERNOR: FAILURE"
    fi

elif [[ $1 == "etcd" ]]; then
    su - db2inst1 -c "cd /opt/ibm/db2-governor/; /opt/ibm/dynamite/python/bin/python2.7 -m standalone.check_endpoint etcd"

elif [[ $1 == "leader" ]]; then
    su - db2inst1 -c "cd /opt/ibm/db2-governor/; /opt/ibm/dynamite/python/bin/python2.7 -m standalone.check_endpoint leader"

elif [[ $1 == "switch_primary" ]]; then
    su - db2inst1 -c "cd /opt/ibm/db2-governor/; /opt/ibm/dynamite/python/bin/python2.7 -m standalone.switch_role"

elif [[ $1 == "tbspc_health" ]]; then
    su - db2inst1 -c "cd /opt/ibm/db2-governor/; /opt/ibm/dynamite/python/bin/python2.7 -m standalone.check_endpoint tablespaces"

elif [[ $1 == "check" ]]; then
    check_governor_running

elif [[ $1 == "hijack" ]]; then
    # assume 2nd arguement is the value to put up
    if [ -n "$2" ]; then
        su - db2inst1 -c "cd /opt/ibm/db2-governor/; /opt/ibm/dynamite/python/bin/python2.7 -m standalone.force_etcd --value $2"
    else
        su - db2inst1 -c "cd /opt/ibm/db2-governor/; /opt/ibm/dynamite/python/bin/python2.7 -m standalone.force_etcd"
    fi
fi
