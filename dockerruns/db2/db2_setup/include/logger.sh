#!/bin/bash

# *******************************************************************************
#
# IBM CONFIDENTIAL
# OCO SOURCE MATERIALS
#
# COPYRIGHT: P#2 P#1
# (C) COPYRIGHT IBM CORPORATION 2018
#
# The source code for this program is not published or otherwise divested of
# its trade secrets, irrespective of what has been deposited with the U.S.
# Copyright Office.
#
# *******************************************************************************

timestamp() 
{
    date +'%Y-%m-%d %H:%M:%S.%3N'
}

logger_time_sec() 
{
    date '+%s'
}

logger ()
{
    if [ -z "$DB2_LOGFILE" ]; then
        export DB2_LOGFILE=/var/log/db2_local.log
    fi
    echo "[$(timestamp): (`basename -- $0`)] $*" >> $DB2_LOGFILE 
    return 0
}

# Docker logs mechanism is attached to PID 1 in the container.
# With the multiple staging mechanism used to bring up IBM DB2,
# there are multiple processes involved and thus we need to ensure
# we output the information to the PID 1 so that 'docker logs'
# will capture it. But as both PID 1 and subsequent script use this
# same function, location is controlled by setting (or not setting)
# the environment variable PID_1_LOGGING.  If set, output will go
# to /proc/1/fd/1. Otherwise it will go to /dev/stdout
console_msg()
{
    if [[ -z "$PID_1_LOGGING" ]]; then
        echo "$*"
    else
        echo "$*" > /proc/1/fd/1
    fi
}

# Logs an elapsed time for a give operation.  Takes 2 arguments
#
#   1) A string descriding the operation the elapsed time is for (db2rbind)
#   2) The time the operation began, in seconds, as per date +%s
#
# No need to pass in the end time, it is determined here
#
logger_elapsed()
{
    logger " ELAPSED_TIME (seconds): \"$1\" | $(($(logger_time_sec)-$2))"
}

logger_info ()
{
    local LEVEL="INFO"
    if [ -n "$1" ]; then
        logger " $LEVEL: $1"
        console_msg "$1"
    else
        while read IN
        do
            logger " $LEVEL: $IN"
            console_msg "$IN"
        done
    fi
    return 0
}

logger_debug ()
{
    local LEVEL="DEBUG"
    if [ -n "$1" ]; then
        logger " $LEVEL: $1"
    else
        while read IN
        do
            logger " $LEVEL: $IN"
        done
    fi
    return 0
}

logger_warning ()
{
    local LEVEL="WARNING"
    if [ -n "$1" ]; then
        logger " $LEVEL: $1"
        console_msg "$1"
    else
        while read IN
        do
            logger " $LEVEL: $IN"
            console_msg "$IN"
        done
    fi
    return 0
}

logger_error ()
{
    local LEVEL="ERROR"
    if [ -n "$1" ]; then
        logger " $LEVEL: $1"
        console_msg "$1"
    else
        while read IN
        do
            logger " $LEVEL: $IN"
            console_msg "$IN"
        done
    fi
    return 0
}

logger_header ()
{
    logger_debug "===================================================="
    logger_debug "RUNNING SCRIPT $1"
    logger_debug "===================================================="
}
