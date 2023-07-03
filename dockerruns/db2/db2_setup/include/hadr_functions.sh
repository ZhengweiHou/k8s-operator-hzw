#!/bin/bash

# *******************************************************************************
#
# IBM CONFIDENTIAL
# OCO SOURCE MATERIALS
#
# COPYRIGHT: P#2 P#1
# (C) COPYRIGHT IBM CORPORATION 2016, 2017, 2018
#
# The source code for this program is not published or otherwise divested of
# its trade secrets, irrespective of what has been deposited with the U.S.
# Copyright Office.
#
# *******************************************************************************

# *******************************************************************************
# Conmmon functon libraries for HADR setup and management
# *******************************************************************************

source ${SETUPDIR?}/include/db2_constants
source ${SETUPDIR?}/include/logger.sh
source /etc/profile

###  Global Variables

abs() {
    [ $1 -lt 0 ] && echo $((-$1)) || echo $1
}

#
### Verify HADR Primary and Secondary system cloks are synchronized
### within 5sec of each other
#
chk_clock_sync () {
    local RC=0
    local rhost
    local sec_since_epoc_local=$(date +%s | bc)
    local sec_since_epoc_remote=$(ssh $rhost "date +%s" | bc)
    local clock_drift=0

    (( clock_drift=sec_since_epoc_local - sec_since_epoc_remote ))
    clock_drift=$(abs $clock_drift | bc)
    [ $clock_drift -gt 5 ] && { logger_error "$HADR_CLOCK_DRIFT_OVER_LIMIT" && RC=1; }

    return $RC
}

#
### Stop console and deactivate dashDB engine
#
deactivate_db() {
    local RC=0
    local database=$1
    local instance=$2
    logger_info "Deactivating ${database?} in preparation for HADR setup ..."

    su - ${instance?} -c "db2 -v terminate; db2 -v force applications all; db2 -v deactivate db ${database?}" 2>&1 | logger_info
    sleep 15
    if [ $(su - ${instance?} -c "db2 -v list active databases" | grep ${database} | wc -l) -gt 0 ]; then
        logger_warning "Failed to deactivate ${database?}"
        logger_warning "Reycling the ${instance?} instance ..."
        su - db2inst1 -c "db2stop force; db2start" 2>&1 | logger_debug
        RC=${PIPESTATUS[0]}
        [[ ! $RC =~ 0|1 ]] && RC=1
    fi
    return $RC
}

#
### Update BLUDB database configuration with HADR parameters
#
update_HADR_dbcfg_params() {
    local lhost=$(hostname -f)
    local rhost=$1
    local lsvc=$2
    local rsvc=$3
    local database=$4
    local instance=$5
    local rdb2inst=${instance?}
    local RC=0

    # Check if the HADR ports are defined in the /etc/services
    grep -q -E "db2_hadrp|db2_hadrs" /etc/services || { logger_error "$HADR_MISSING_SVCE_NAMES" && RC=1 && return $RC; }

    ### Update the HADR db configuration
    logger_info "Updating HADR database configuration parameters on BLUDB ..."
cat <<EOF > /tmp/hadr_db.cfg
LOGINDEXBUILD ON
HADR_LOCAL_HOST $lhost
HADR_LOCAL_SVC $lsvc
HADR_REMOTE_HOST $rhost
HADR_REMOTE_SVC $rsvc
HADR_REMOTE_INST $rdb2inst
HADR_TIMEOUT 120
HADR_SYNCMODE NEARSYNC
HADR_PEER_WINDOW 120
EOF

    logger_debug "HADR parameters used:"
    cat /tmp/hadr_db.cfg 2>&1 | logger_debug
    ${SETUPDIR?}/lib/update_db_cfg.sh /tmp/hadr_db.cfg ${database?} ${instance?} 2>&1 | logger_debug
    RC=${PIPESTATUS[0]}
    rm -f /tmp/hadr_db.cfg

    return $RC
}

#
### Checks if database backup file exists under ${SCRATCHDIR}
### returns: full path to the database backup image file
### * RC=0 if one backup image is found
### * RC=1 if no backup image is found
### * RC=2 if or more than one backup image is found
#
get_db_backup_image(){
    local RC=0
    local database=`echo $1 | awk '{print toupper($0)}'`
    local backupdir=$2
    local bkp_image=$(ls -1 ${backupdir?}/${database?}.0.* 2> logger_debug)
    [ -z $bkp_image ] && { RC=1 && return $RC; }
    [ `echo "${bkp_image[@]}" | wc -l` -gt 1 ] && { RC=2 && return $RC; }

    logger_debug "Checksum of the backup image: $(md5sum $bkp_image 2>&1 | awk '{print $1}')"
    echo $bkp_image && return $RC
}

#
### Checks if keystore backup file exists under ${SCRATCHDIR}
### returns: full path to the keystore backup file
### RC=0 true (if found), RC=1 otherwise
#
get_keystore_backup_file() {
    local RC=0
    local backupdir=$1
    local keystore_file=$(ls -1 ${backupdir?}/keystore.tar 2> logger_debug)
    [ -z $keystore_file ] && { RC=1 && return $RC; }

    echo $keystore_file && return $RC
}

#
### Backup database and keystore. Failure in either will RC=1
#
backup_db_and_keystore() {
    local current_node=$1
    local instance=$2
    local database=$3
    local backupdir=$4
    local RC=0

    # Check if there is a backup image already and if so cleanup
    #local bkp_image=$(ls -1 ${SCRATCHDIR}/BLUDB.0.* 2> logger_debug)
    local bkp_image=$(get_db_backup_image ${database?} ${backupdir?})
    [ ! -z $bkp_image ] && { logger_info "Cleaning up old database backup image $bkp_image" && rm -f $bkp_image; }

    logger_info "Saving the (BLUDB) database backup image into <root of external volume>/scratch directory ..."
    su - ${instance?} -c "db2 -v backup db ${database?} to ${backupdir?}" 2>&1 | logger_info

    get_db_backup_image ${database?} ${backupdir?} &> /dev/null; RC=$?
    case $RC in
        1)  logger_error "The database backup file not found under ${backupdir?}"
        ;;
        2)  logger_error "There are more than one database backup file found under ${backupdir?}"
            logger_error "Please cleanup/move other backup images and retry"
        ;;
    esac
    [ $RC -ne 0 ] && return $RC

    # In addition to the backup, the keystore needs to be copied over to standby if databse
    # backup is used as the initialization method. With snapshot the keysore is also ported.
    # The Data Encryption Key (DEK) needs to be same between the systems to decrypt, otherwise
    # someone can use a backup and simply resotore on another system to access the data.
    # However, the master key (p12) can be and for best practices should be different between the systems.

    # Skip database encryption for now
    #logger_info "Saving the keystore file (keystore.tar) into <root of external volume>/scratch directory ..."
    #tar -cjvf ${backupdir?}/keystore.tar -C ${KEYSTORELOC?} . 2>&1 | logger_debug
    #get_keystore_backup_file ${backupdir?}&> /dev/null || \
    #    { logger_error "The keystore tar file not found found under ${SCRATCHDIR}" && RC=1 && return $RC; }

    logger_info "$HADR_SETUP_BACKUP_DB" && return $RC
}

#
### Restore database and keystore. Failure in either will RC=1
#
restore_db_and_keystore() {
    local current_node=$1
    local database=$2
    local backupdir=$3
    local instance=$4
    local RC=0

    # Using cp without '-p' or differences in default umasks when moving the
    # image to the standby server can change mode-bits and permissions.
    # That can restict access to 'db2inst1' when backup image/keystore is
    # accessed druing restore. Therefore, change mode-bits/permissions so that
    # db2inst1 can restore the backup.
    local bkp_image=$(get_db_backup_image ${database?} ${backupdir?})
    chmod 600 $bkp_image; chown ${instance?} $bkp_image

    #logger_info "Restoring the keystore on the HADR standby system ..."
    #local keystore_file=$(get_keystore_backup_file ${backupdir?})
    #chmod 644 $keystore_file

    logger_info "Restoring the (${database?}) database on the HADR standby system ..."
    su - ${instance?} -c "db2 -v drop db ${database?}" 2>&1 | logger_info
    RC=${PIPESTATUS[0]}
    [ ${RC?} -ne 0 ] &&  { logger_error "Failed to drop the existing database on standby node" && RC=1 && return $RC; }

    # Skip the keystore restore for now
    #tar -xvf $keystore_file -C ${KEYSTORELOC} 2>&1 | logger_debug
    #RC=${PIPESTATUS[0]}
    #[ ${RC?} -ne 0 ] && { logger_error "Failed to restore the database encryption keystore" && RC=1 && return $RC; }
    #su - ${instance?} -c "db2 -v restore db ${database?} from ${backupdir?} encrypt" 2>&1 | logger_info

    su - ${instance?} -c "db2 -v RESTORE DATABASE ${database?} FROM ${backupdir?}" 2>&1 | logger_info
    RC=${PIPESTATUS[0]}
    [ ${RC?} -ne 0 ] && { logger_error "Failed to restore the HADR standby database" && RC=1 && return $RC; }

    logger_info "Cleaning up keystore tar file and database backup image ..."
    rm -f $bkp_image 2>&1 | logger_debug

    logger_info "${HADR_SETUP_RESTORE_DB?}" && return ${RC?}
}

#
### Configure for HADR ACR (Automatic Client Reroute)
#
configure_HADR_ACR() {
    local use_ssl_port=$1
    local instance=$2
    local database=$3
    local rhost=$(su - ${instance?} -c "db2 get db cfg for ${database?}" | awk -F'=' '/HADR_REMOTE_HOST/ {gsub(" |\t",""); print $2}')
    local port
    local RC=0

    # Select the DB2 SVCE port to use for alternate server -- IE normal or SSL
    if [[ "X$use_ssl_port" == "Xssl" ]]; then
        port=$(grep ^db2c_${instance?}_ssl /etc/services | awk '{print $2}' | sed 's|/tcp||')
    else
        port=$(grep ^db2c_${instance?} /etc/services | awk '{print $2}' | sed 's|/tcp||')
    fi

    # Check if current node is Primary
    #local role=$(get_HADR_role ${instance?} ${database?})
    #FIXME -- verify if we can configure alternate server even when HADR is not in PEER state
    #local state=$(get_HADR_state)

    #if [[ "X$role" != "XPRIMARY" ]]; then
    #    logger_warning "Current node (`hostname -s`) is not the HADR 'Primary' server."
    #    logger_warning "Issue 'manage_hadr' script with '-enable_acr' on the primary server to configure ACR"
    #    RC=1 && return $RC
    #fi

    logger_info "Using $rhost as remote host and $port as DB2 SVCE port to configure HADR alternate server settings ..."
    su - ${instance?} -c "db2 -v connect to ${database?}; \
        db2 -v update alternate server for db ${database?} using hostname $rhost port $port; \
        db2 -v connect reset" 2>&1 | logger_info

    logger_info "Listing the dataDB database system directory after ACR update:"
    su - ${instance?} -c "db2 list db directory" | awk '/alias/ && /${database?}/ { matched = 1 } matched { print }' 2>&1 | logger_info

    logger_info "${HADR_MANAGE_ENABLE_ACR_SUCCESS?}"
    return $RC
}

get_HADR_role() {
    local role="unknown"
    local instance=$1
    local database=$2
    role=$(su - ${instance?} -c "db2pd -hadr -db ${database?}" | egrep -i "HADR_ROLE" | head -1 | tr "[a-z]" "[A-Z]" | awk '{print $3}')
    [[ $role =~ STANDARD|PRIMARY|STANDBY ]] || role="unknown"
    echo $role
}

get_HADR_role_dbcfg() {
    local instance=$1
    local database=$2
    local role_in_dbcfg="unknown"
    role_in_dbcfg=$(su - ${instance?} -c "db2 get db cfg for ${database?}" | awk -F'=' '/HADR database role/ {gsub(" |\t",""); print $2}')
    [[ $role_in_dbcfg =~ STANDARD|PRIMARY|STANDBY ]] || role="unknown"
    echo $role_in_dbcfg
}

get_HADR_state() {
    local instance=$1
    local database=$2
    local state="unknown"
    state=$(su - ${instance?} -c "db2pd -hadr -db ${database?}" | egrep -i "HADR_STATE" | head -1 | tr "[a-z]" "[A-Z]" | awk '{print $3}')
    [[ "$state" =~ DISCONNECTED|LOCAL_CATCHUP|REMOTE_CATCHUP_PENDING|REMOTE_CATCHUP|PEER|DISCONNECTED_PEER ]] || state="unknown"
    echo ${state?}
}

is_HADR_load_copy_path_mounted() {
    local load_copy_path=$1
    local RC=0

    grep -q ${load_copy_path?} /etc/mtab
    if [ $? -ne 0 ]; then
        logger_warning "The LOAD copy path ${load_copy_path?} is not mounted."
        logger_warning "If you plan to use LOAD to move data into ${IBM_PRODUCT?} with HADR enabled,"
        logger_warning "you need bind-mount a shared file system during docker run."
        RC=1
    fi
    return $RC
}

write_suspend_and_resume_for_snapshots() {
    local RC=0
    /usr/bin/write-suspend || return $?

    logger_info "$HADR_SETUP_DO_P_SNAP"
    # Read user input and time-out in 30min
    read -e -p "* Press the enter key when you are ready to resume write access to the database ..." -t 1800 input || \
        logger_warning "No user-input received within 30 min, automatically resuming writes to the primary database copy"

    /usr/bin/write-resume
    RC=$? && return $RC
}

#
### HADR Command functions for following tasks:
### * stop HADR
### * start HADR
### * display HADR status
### * takeover (role-switch) HADR
#
start_HADR() {
    local start_role=$1
    local force=$2
    local instance=$3
    local database=$4
    local backupdir=$5
    local RC=0

    logger_info "################################################################################"
    logger_info "###                       Starting HADR configuration                        ###"
    logger_info "################################################################################"

    start_role=$(echo $start_role | tr [:lower:] [:upper:])

    if [[ "X$start_role" =~ XPRIMARY|XSTANDBY ]]; then
        # Handle all the scenario that are blocked before we proceed to issue the start HADR as
        # Ref: https://www.ibm.com/support/knowledgecenter/en/SSEPGG_11.1.0/com.ibm.db2.luw.admin.cmd.doc/doc/r0011551.html

        local role_in_dbcfg=$(get_HADR_role_dbcfg ${instance?} ${database?})
        local current_role=$(get_HADR_role ${instance?} ${database?})

        ### 1) If STANDARD, db and trying to start as standby, block some scenarios ###
        if [[ "$role_in_dbcfg" == "STANDARD" && "$start_role" == "STANDBY" ]]; then
            ## 1a) Inactive STANDARD db
            if [[ "$current_role" == "unknown" ]]; then
                local rlfwd_pending=$(su - ${instance?} -c "db2 get db cfg for ${database?}" | awk -F'=' '/Rollforward pending/ {gsub(" |\t",""); print $2}')
                if [[ "$rlfwd_pending" != "DATABASE" ]]; then
                    logger_error "The HADR standby database copy is not in rollforward pending state."
                    logger_error "The HADR standby initialization failed."
                    RC=1 && return $RC
                fi
            elif [[ "$current_role" == "STANDARD" ]]; then  ## 1b) Active STANDARD db
                logger_error "You are not allowed to start HADR as standby on an active database that is not already enabled for HADR."
                logger_error "Run 'manage_hadr' command with '-stop' option to stop hadr and deactivate database on this node $(hostname -s)"
                logger_error "Then retry the 'manage_hadr' command to start HADR as standby, if 'setup_hadr' was already run before."
                RC=1 && return $RC
            fi
        fi

        ### 2) If Active or Inactive standby, block start as 'primary' ###
        if [[ "$role_in_dbcfg" == "STANDBY" || "$current_role" == "STANDBY" ]] && [[ "$start_role" == "PRIMARY" ]]; then
            logger_error "The HADR database (${database?}) is already configured and/or running as 'standby'"
            logger_error "Therefore, you cannot start HADR with $start_role role on ${database?} database."
            logger_error "Retry running 'manage_hadr' tool with option -start_as $role_in_dbcfg to start HADR."
            RC=1 && return $RC
        fi

        ### 3) If already Active standby, block start as 'standby' ###
        ###    if already Active primary, block start as 'primary' ###
        if [[ "$start_role" == "$current_role" ]]; then
            logger_warning "The HADR database (${database?}) is already running as $current_role"
            RC=1 && return $RC
        fi

        ### 4) if already Active primary, block start as 'standby' ###
        if [[ "$current_role" == "PRIMARY" && "$start_role" == "STANDBY" ]]; then
            logger_error "The HADR database (${database?}) is already running as $current_role"
            logger_error "Therefore, you cannot start HADR on (${database?}) database using $start_role role."
            RC=1 && return $RC
        fi

        ### ************ Now handle the start HADR as actions ************** ###
        if [ "$start_role" == "PRIMARY" -a ${force?} -eq ${TRUE?} ]; then
            logger_info "Starting HADR on database ${database?} as $start_role by FORCE ..."
            hadr_start_out=$(su - ${instance?} -c "db2 -v start hadr on db ${database?} as $start_role by FORCE")
        else
            logger_info "Starting HADR on database ${database?} as $start_role ..."
            hadr_start_out=$(su - ${instance?} -c "db2 -v start hadr on db ${database?} as $start_role")
        fi
        echo $hadr_start_out | grep -v SQL1777N | grep -q "^SQL17[67][0-9]" && RC=1
        [ $RC -ne 0 ] && \
            { logger_error "Start HADR on ${database?} as $start_role failed." && logger_error "$hadr_start_out" && return $RC; }
        logger_info "$hadr_start_out"
    else
        logger_error "Please specify the HADR role [ primary | standby ] to start HADR"
        RC=1 && return $RC
    fi

    # The backup image and keystore is cleaned up on standby when hadr setup
    # is done. However, we can't clean it up during setup on primary, hence,
    # should at least do so when HADR on primary is started for the first time.
    local bkp_image=$(get_db_backup_image ${database?} ${backupdir?})
    #local keystore_file=$(get_keystore_backup_file ${backupdir?})
    #if [ ! -z "${bkp_image?}" ] || [ ! -z "${keystore_file?}" ]; then
    if [ ! -z "${bkp_image?}" ]; then
        logger_info "Cleaning up keystore tar file and/or database backup image ..."
        rm -f ${keystore_file?} ${bkp_image?} 2>&1 | logger_debug
    fi

    logger_info "${HADR_MANAGE_START_SUCCESS?}"
    return $RC
}

stop_HADR() {
    local instance=$1
    local database=$2
    local RC=0
    local role=$(get_HADR_role ${instance?} ${database?})

    logger_info "################################################################################"
    logger_info "###                      Stopping HADR configuration                         ###"
    logger_info "################################################################################"

    [[ "X$role" == "XSTANDBY" ]] && su - ${instance?} -c "db2 -v deactivate db ${database?}" 2>&1 | logger_info
    su - ${instance?} -c "db2 -v stop hadr on db ${database?}" 2>&1 | logger_info
    RC=${PIPESTATUS[0]}
    [ $RC -ne 0 ] && logger_error "Stop HADR on ${database?} failed."
    logger_info "${HADR_MANAGE_STOP_SUCCESS?}"
    return $RC
}

status_HADR() {
    local RC=0
    local instance=$1
    local database=$2
    local keywords="Database|HADR_ROLE|HADR_STATE|PRIMARY_MEMBER_HOST|STANDBY_MEMBER_HOST|HADR_CONNECT_STATUS|_LOG_FILE|PEER_WINDOW_END"
    local state=$(get_HADR_state ${instance?} ${database?})
    [[ "$state" == "unknown" ]] && { logger_error "Unable to query HADR status." && RC=1 && return $RC; }

    logger_info "################################################################################"
    logger_info "###                       The HADR status summary                            ###"
    logger_info "################################################################################"
    su - ${instance?} -c "db2pd -db ${database?} -hadr" | grep -E "$keywords"
    RC=$?
    [ $RC -ne 0 ] && logger_error "Unable to query HADR status."
    return $RC
}

takeover_HADR() {
    local force=$1
    local instance=$2
    local database=$3
    local RC=0

    # Check if current node is Primary
    local role=$(get_HADR_role ${instance?} ${database?})
    local state=$(get_HADR_state ${instance?} ${database?})

    logger_info "################################################################################"
    logger_info "###                     Running takeover HADR on BLUDB                       ###"
    logger_info "################################################################################"

    if [[ "X$role" == "XPRIMARY" ]]; then
        logger_warning "Current node (`hostname -s`) is already the HADR 'Primary'"
        logger_warning "Issue manage_hadr script on the standby server to takeover"
        RC=1 && return $RC
    fi

    if [ ${force?} -eq ${TRUE?} ]; then
        # Lets first attempt to force down standby shutdown within peer window.
        hadr_takeover_out=$(su - ${instance?} -c "db2 -v takeover hadr on db ${database?} by force peer window only")
        RC=$?
        echo $hadr_takeover_out | grep -q -E 'SQL1770N(.*)Reason code = "9"'
        if [ $? -eq 0 ]; then
            su - ${instance?} -c "db2 -v takeover hadr on db ${database?} by force" 2>&1 | logger_info
            RC=${PIPESTATUS[0]}
        fi
        [ $RC -ne 0 ] && logger_error "Attempts to takeover HADR on ${database?} by force with and without peer window failed."
    else
        su - ${instance?} -c "db2 -v takeover hadr on db ${database?}" 2>&1 | logger_info
        RC=${PIPESTATUS[0]}
        [ $RC -ne 0 ] && logger_error "Takeover HADR on ${database?} failed. Retry with 'force' if applicable"

    fi

    if [ $RC -eq 0 ]; then
        logger_info "$HADR_MANAGE_TAKEOVER_SUCCESS"
    fi
    return $RC
}

#
### Run the db object update on primary if in PEER state.
#
update_HADR_db() {
    local instance=$1
    local database=$2
    local role=$(get_HADR_role ${instance?} ${database?})
    local state=$(get_HADR_state ${instance?} ${database?})
    local RC=0

    logger_info "################################################################################"
    logger_info "###                      Updating HADR database ${database?}                        ###"
    logger_info "################################################################################"

    # Confirm this is the PRIMARY and HADR is in PEER state
    if [[ "X$role" != "XPRIMARY" ]]; then
        logger_warning "Current node (`hostname -s`) is not the HADR 'primary'"
        logger_warning "You need to run 'manage_hadr' tool with '-update_db' option on the primary only."
        RC=1 && return $RC
    fi
    if [[ "X$state" != "XPEER" ]]; then
        logger_warning "The HADR configuration is not in the 'PEER' state"
        logger_warning "Run the 'manage_hadr' tool with '-status' option to query the HADR status,"
        logger_warning "and retry '-update_db' option after 'PEER' state is achieved."
        RC=1 && return $RC
    fi

    # The dashDB update script will recycle engine in order to re-enable rbind
    # daemon, so we'll need to start and active db post-update. And that will
    # start HADR as primary automatically on this node.
    su - ${instance?} -c "db2start; db2 -v activate db ${database?}" 2>&1 | logger_debug
    # FIXME
    #RC=${PIPESTATUS[0]}
    #[[ ! $RC =~ 0|1 ]] && \
    #   { logger_error "Failed start dashDB engine and/or activate the database after update" && RC=1 && return $RC}

    # Run updateDSM.sh again incl. repo db updates.
    update_dsm

    # start web console
    logger_info "${HADR_MANAGE_UPDATE_SUCCESS?}"
    return $RC
}

disable_reduced_redo_logging () {
    local instance=$1
    local RC=0
    if [[ -z "$({DB2DIR}/bin/db2ilist)" ]]; then
        logger_debug "Missing ${IBM_PRODUCT} instance record"
        logger_debug "Dumping ${IBM_PRODUCT} global registry ..."
        ${DB2DIR}/bin/db2greg -dump 2>&1 | logger_debug
        logger_debug "Unable to disable reduced logging redo" && return 1
    fi

    su - ${instance?} -c "db2set 'DB2_CDE_REDUCED_LOGGING=REDUCED_REDO:NO'" 2>&1 | logger_debug
    RC=${PIPESTATUS[0]}
    return $RC
}
