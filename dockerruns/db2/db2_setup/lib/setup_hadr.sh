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
# Standalone tool to setup HADR in a dashDB Local configuration.
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


logger_info "${HADR_SETUP_HEADER?}"

# Global Variables
current_node="unknown"
standby_init_method="unknown"
reinit_hadr=false
remote_host="unknown"
instance="db2inst1"
database="BLUDB"

[ ! $# -gt 0 ] && { logger_error "${HADR_SETUP_USAGE?}" && exit ${FALSE}; }

while test $# -gt 0; do
    case $1 in
        -primary) current_node="primary"
        ;;
        -standby) current_node="standby"
        ;;
        -remote) shift; remote_host=$1
        ;;
        -use_backup) standby_init_method="backup"
        ;;
        -use_snapshot) standby_init_method="snapshot"
        ;;
        -reinit) reinit_hadr=true
        ;;
        -database) shift; database=$1
        ;;
        -instance) shift; instance=$1
        ;;
        *)
            logger_error "Invalid HADR setup option(s) specified."
            logger_error "${HADR_SETUP_USAGE?}" && exit ${FALSE}
        ;;
    esac
    shift
done

database=`echo ${database?} | awk '{print toupper($0)}'`

# Check if HADR is already configured and allow setup if they only want to re-initialize
role_in_dbcfg=$(get_HADR_role_dbcfg ${instance?} ${database?})
if [[ "${role_in_dbcfg?}" =~ PRIMARY|STANDBY ]] && [[ "${reinit_hadr?}" != true ]]; then
    logger_warning "HADR is already configured on this system."
    logger_warning "Re-issue 'setup_hadr' command with '-reinit' option if you want to re-initialize HADR."
    logger_warning "If you re-initialize HADR on the primary system you will need to re-initialize HADR on standby system as well."
    exit ${FALSE?}
fi

# If using backup method to init standby, verify if backup image and keystore are available before proceeding.
if [ "${current_node?}" == "standby" -a "${standby_init_method?}" == "backup" ]; then

    bkp_image=$(get_db_backup_image ${database?} ${HADR_SHARED_DIR?})
    case $? in
        0)  logger_info "Found backup image ${bkp_image?}"
        ;;
        1)  logger_error "The database backup file was not found under ${HADR_SHARED_DIR?}"
            exit ${FALSE?}
        ;;
        2)  logger_error "Multiple database backup files found under ${HADR_SHARED_DIR?}"
            logger_error "Please cleanup/move other backup images and retry"
            exit ${FALSE?}
        ;;
        *)  logger_error "There was a problem getting the backup image."
            exit ${FALSE?}
        ;;
    esac

    #keystore_file=$(get_keystore_backup_file ${HADR_SHARED_DIR?})
    #if [ $? -ne ${TRUE?} ]; then
    #    logger_error "The keystore tar file not found under ${HADR_SHARED_DIR?}"
    #    exit ${FALSE?}
    #fi

fi

# Parse hostname, IP from remote host user input
echo "${remote_host?}" | grep -q -E '(.*):(.*)' || \
    { logger_error "The remote host value specified $remote_host is invalid. You must use hostname:IP format." && exit ${FALSE}; }
remote_node_name=$(echo "${remote_host?}" | awk -F':' '{print $1}')
remote_node_ip=$(echo "${remote_host?}" | awk -F':' '{print $2}')
domain=$(dnsdomainname)

# Update /etc/hosts if needed with remote host info
remote_node_short_hostname=$(cut -d '.' -f 1 <<< "${remote_node_name?}")
update_etc_hosts "${remote_node_short_hostname?}" "${remote_node_ip?}" "${domain?}"

# Test if the required engine and HADR ports are opened on the current node
#${SETUPDIR}/lib/comm_test.sh -hadr "${remote_host?}" -noheaders

# FIXME -- Add error handling logic for both Console stop & BLUDB deactivate

case "${current_node?}" in
    primary)
        if [[ "${standby_init_method?}" == "backup" ]]; then
            { deactivate_db ${database?} ${instance?} && backup_db_and_keystore ${current_node?} ${instance?} ${database?} ${HADR_SHARED_DIR?}; } || exit ${FALSE}
        elif [[ "${standby_init_method?}" == "snapshot" ]]; then
            { write_suspend_and_resume_for_snapshots && deactivate_db ${database?} ${instance?}; } || exit ${FALSE}
        else
            logger_error "Invalid HADR standby initialization method ${standby_init_method?}" && exit ${FALSE}
        fi

        update_HADR_dbcfg_params "${remote_node_name?}" "db2_hadrp" "db2_hadrs" ${database?} ${instance?} || exit ${FALSE}

        # Do a write test to the shared LOAD copy path. When setup_hadr is run
        # on the standby, we'll do a read to verify if the LOAD copy path used
        # for replaying LOAD images on standby is accessible.
        is_HADR_load_copy_path_mounted "${HADR_LOAD_COPY_PATH}"
        if [ $? -eq 0 ]; then
            echo "${current_node?}:$(hostname -s)" > ${HADR_LOAD_COPY_PATH}/.pathtest || \
                { logger_error "Unable to write to the LOAD copy file system mounted at ${HADR_LOAD_COPY_PATH?}." && \
                  logger_error "Check if the file system was properly bind-mounted during docker run." && exit ${FALSE}; }

            logger_info "Updating ${IBM_PRODUCT?} instance to use the new LOAD copy path ${HADR_LOAD_COPY_PATH?} ..."
            su - ${instance?} -c "db2set DB2_LOAD_COPY_NO_OVERRIDE='COPY YES TO ${HADR_LOAD_COPY_PATH}'"
            RC=$?
            # Recycle dashDB engine for the reg-var change to be effective
            su - ${instance?} -c "db2stop force; db2start" 2>&1 | logger_info
        fi
    ;;
    standby)
        suspended=`su - ${instance?} -c "db2 get db cfg for ${database?}" | awk -F'=' '/write suspend/ {gsub(" |\t",""); print $2}'`
        if [[ "${suspended?}" == "YES" ]]; then
            logger_info "Initializing the Snapshot copy as HADR standby ..."
            su - ${instance?} -c "db2inidb ${database?} as standby" 2>&1 | logger_info
            deactivate_db ${database?} ${instance?} || exit ${FALSE}
        else
            # Stop console and deactivate dashDB database
            { deactivate_db ${database?} ${instance?} && restore_db_and_keystore ${current_node?} ${database} ${HADR_SHARED_DIR?} ${instance?}; } || exit ${FALSE}
        fi
        logger_info "Update HADR database configuration parameters on ${current_node?} $(hostname -s)..."
        update_HADR_dbcfg_params ${remote_node_name?} "db2_hadrs" "db2_hadrp" ${database?} ${instance?} || exit ${FALSE}

        is_HADR_load_copy_path_mounted "${HADR_LOAD_COPY_PATH}"
        if [ $? -eq 0 ]; then
            if [ $(cat ${HADR_LOAD_COPY_PATH}/.pathtest | wc -l) -ne 1 ]; then
                logger_error "Read test of the LOAD copy file system mounted at ${HADR_LOAD_COPY_PATH?} failed."
                logger_error "Check if the file system that was bind-mounted during"
                logger_error "docker run -v </loadcopy/fs/path>:/mnt/loadcopy is shared between the HADR systems."
                exit ${FALSE}
            else
                logger_info "Updating ${IBM_PRODUCT?} instance to use the new LOAD copy path ${HADR_LOAD_COPY_PATH} ..."
                su - ${instance?} -c "db2set DB2_LOAD_COPY_NO_OVERRIDE='COPY YES TO ${HADR_LOAD_COPY_PATH?}'"
                su - ${instance?} -c "db2stop force; db2start"
            fi
        fi
    ;;
    unknown) logger_error "Unable to determine the current node" && exit ${FALSE}
    ;;
esac

if [[ "${current_node?}" == "standby" ]]; then
    rlfwd_pending=$(su - ${instance?} -c "db2 get db cfg for ${database?}" | awk -F'=' '/Rollforward pending/ {gsub(" |\t",""); print $2}')
    if [[ "${rlfwd_pending?}" == "DATABASE" ]]; then
        logger_info "The HADR standby database copy is in rollforward pending state and can be used to enable HADR"
    else
        logger_error "The HADR standby initialization failed." && exit ${FALSE}
    fi
fi

case "${current_node?}" in
    primary)
        if [[ "${standby_init_method?}" == "backup" ]]; then
            logger_info "${HADR_SETUP_NEXT_STEPS_P_BACKUP?}"
        else
            logger_info "${HADR_SETUP_NEXT_STEPS_P_SNAP?}"
        fi
        logger_info "${HADR_SETUP_TRAILER_P?}"
    ;;
    standby) logger_info "${HADR_SETUP_TRAILER_S?}"
    ;;
esac
