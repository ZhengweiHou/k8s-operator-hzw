#!/bin/bash

# *******************************************************************************
#
# IBM CONFIDENTIAL
# OCO SOURCE MATERIALS
#
# COPYRIGHT: P#2 P#1
# (C) COPYRIGHT IBM CORPORATION 2016, 2017
#
# The source code for this program is not published or otherwise divested of
# its trade secrets, irrespective of what has been deposited with the U.S.
# Copyright Office.
#
# *******************************************************************************

# *******************************************************************************
# Standalone tool to manage HADR in a dashDB Local configuration.
# *******************************************************************************

# Options for "set" command
setopts="${setopts:-+x}"
set ${setopts?}

source /etc/profile
source ${SETUPDIR?}/include/db2_constants
source ${SETUPDIR?}/include/db2_text.h
source ${SETUPDIR?}/include/logger.sh
source ${SETUPDIR?}/include/hadr_functions.sh
source ${SETUPDIR?}/include/db2_common_functions

param=$1
action="unknown"
instance="db2inst1"
database="BLUDB"
use_ssl_port="unkown"
force=${FALSE?}
RC=${TRUE?}

logger_info "$HADR_MANAGE_HEADER"
logger_info "Running HADR action $action on the database BLUDB ..."


while test $# -gt 0; do
    case $1 in
        -status )
            action="status"
        ;;
        -start_as )
            action="start"
            shift; role=$1  
        ;;
        -stop )
            action="stop"
        ;;
        -takeover )
            action="takeover"
        ;;
        -force )
            force=${TRUE?}
        ;;
        -update_db )
            action="update_db"
        ;;
        -enable_acr )
            action="enable_acr"
        ;;
        -instance )
            shift; instance=$1
        ;;
        -database )
            shift; database=$1
        ;;
        * )
            logger_error "${HADR_MANAGE_USAGE?}"
            RC=1
        ;;
    esac
    shift
done



case ${action?} in
    "status")
        status_HADR ${instance?} ${database?}
        RC=$?
    ;;
    "start")
        start_HADR ${role?} ${force?} ${instance?} ${database?} ${HADR_SHARED_DIR?}
        RC=$?
    ;;
    "stop")
        stop_HADR ${instance?} ${database?}
        RC=$?
    ;;
    "takeover")
        takeover_HADR ${force?} ${instance?} ${database?}
        RC=$?
    ;;
    "update_db")
        update_HADR_db ${instance?} ${database?}
        RC=$?
    ;;
    "enable_acr")
        configure_HADR_ACR ${use_ssl_port?} ${instance?} ${database?}
        RC=$?
    ;;
    *)
        logger_error "${HADR_MANAGE_USAGE?}"
        RC=1
    ;;
esac

if [ ${RC?} -ne ${TRUE?} ]; then 
    logger_error "${HADR_MANAGE_ERROR_GENERAL?}"
fi

exit ${RC?}
