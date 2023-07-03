#!/bin/bash
################################################################################

#   Initialize DB2 instance in a Docker container
#
# Copyright 2017, IBM Corporation
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################

source ${SETUPDIR?}/include/db2_constants
source ${SETUPDIR?}/include/db2_common_functions

#############################################################################
# Main configuration starts here
#############################################################################

if [ -z "${LICENSE?}" ];then
   echo ""
   echo >&2 'Error: you need to accept the license'
   echo >&2 "Did you forget to add '-e LICENSE=accept' ?"
   exit 1
fi

if [ "${LICENSE?}" != "accept" ]; then
   echo ""
   echo >&2 "error: LICENSE not set to 'accept'"
   echo >&2 "Please set '-e LICENSE=accept' to accept License before use the DB2 software contained in this image."
   exit 1
fi

if [ -z "${DB2INST1_PASSWORD?}" ]; then
   echo >&2 ""
   echo >&2 'error: DB2INST1_PASSWORD not set'
   echo >&2 'Did you forget to add -e "DB2INST1_PASSWORD=..." ?'
   exit 1
fi

# Make sure the instance user can write to the STORAGE_DIR
chmod 755 ${STORAGE_DIR?}
if [ ${HADR_ENABLED?} = "true" ]; then

    # The instance user needs to be able to read/write in hadr.cfg
    chmod 777 ${HADR_SHARED_DIR?}

    if [ ! -f ${HADR_SHARED_DIR?}/hadr.cfg ]; then
        touch ${HADR_SHARED_DIR?}/hadr.cfg 
        HADR_ROLE_FOR_SETUP="PRIMARY"
    else
        primary_ip=$(${DB2DIR?}/bin/db2fupdt -f ${HADR_SHARED_DIR?}/hadr.cfg -p primary_ipaddr)
        curr_ip=$(hostname -i)
        if [ "${primary_ip?}" == "${curr_ip?}" ]; then
            HADR_ROLE_FOR_SETUP="PRIMARY"
        fi
    fi

    echo "(*) HADR_ROLE_FOR_SETUP:${HADR_ROLE_FOR_SETUP?}"
fi

export_shared_data
restore_global_registry

if ! getent passwd ${DB2INSTANCE?} > /dev/null 2>&1; then
   echo "(*) Previous setup has not been detected. Creating the users... "
   create_users
fi

if [ "${IS_KUBE?}" = "true" ]; then
    echo "(*) On a k8s env. Cleaning up invalid IPC resources owned by detached Db2 users... "
    ${SETUPDIR}/lib/clean_ipc.sh 2>/dev/null
fi

if ! create_instance; then
   exit 1
fi

if [ "${DB2DEVCE}" = "true" ] && [ -d ${STORAGE_DIR?}/db2cfg ]; then
   enable_backward_compat
fi

echo "(*) Cataloging existing databases"
catalog_database

if [ -f ${CONFIG_DIR?}/licenses/nodelock ]; then
   import_license
else
   apply_license
fi

set_dbm_cfg
# If Docker for Windows is the engine, we need to import the backed up
# db and dbm cfg and database catalog
if [ "${PERSISTENT_HOME}" = "true" ] && [ -f ${CONFIG_FILE?} ]; then
   import_config
fi

test "${BLU?}" = "true" && enable_blu
test "${ENABLE_ORACLE_COMPATIBILITY?}" = "true" && enable_oracle_compat

echo "(*) Remounting ${STORAGE_DIR?} with suid... "
mount -o remount,suid ${STORAGE_DIR?}

if [ -n "${DBNAME?}" ]; then
   update_db2_code ${DBNAME?}
fi
if [ "${SAMPLEDB?}" = "true" ]; then
   update_db2_code "sample"
fi

start_db2

if [ "${TEXT_SEARCH}" = "true" ]; then 
  echo "(*) Starting TEXT SEARCH service ..."
  su - ${DB2INSTANCE?} -c "db2ts \"start for text\""
fi

# set up exit mode. These signals will bring down the container.
# docker stop gives us a sigterm, shut down hard. Requests a termination
trap on_sigterm SIGTERM

if [ -z "${UPDATEAVAIL?}" ]; then
    echo "This is not an update request."
fi


if [ ! -f ${SETUP_COMPLETE?} ]; then

   # Create SAMPLE database if user has chosen to create it
   if [ "${SAMPLEDB?}" = "true" ]; then
      echo "(*) User chose to create a SAMPLE database"
      if ! create_sample_db; then
         echo "(!) Failed to create SAMPLE database"
      else
         configure_db "sample"
      fi
   fi

   # Create DSM repository database if docker run has received a REPODB=true
   test "${REPODB?}" = "true" && create_repo_db

   if [ -n "${DBNAME?}" ]; then
      echo "(*) User chose to create ${DBNAME?} database"
      if ! create_db ${DBNAME?}; then
         echo "(!) Failed to create ${DBNAME?} database"
      else
         configure_db ${DBNAME?}
      fi
   fi

fi

if [ "${HADR_ENABLED?}" = "true" ]; then
  
    db_name_for_hadr=""
    if [ -n "${DBNAME?}" ]; then
      db_name_for_hadr=${DBNAME?}
    elif [ "${SAMPLEDB?}" = "true" ]; then
      db_name_for_hadr="SAMPLE"
    else
      echo "(!!!) There is no database for HADR setup ... "
    fi
 
    if ! setup_hadr ${HADR_ROLE_FOR_SETUP?} ${DB2INSTANCE?} ${db_name_for_hadr?} ; then
       echo "(!!!) There was a failure during HADR setup... "
    fi

    if [ -n "${ETCD_ENDPOINT?}" ]; then
       if ! setup_governor ${HADR_ROLE_FOR_SETUP?} ${DB2INSTANCE?} ${db_name_for_hadr?} ${ETCD_ENDPOINT?} ${ETCD_USERNAME?} ${ETCD_PASSWORD?} ; then
          echo "(!!!) There was a failure during Governor setup... "
       fi
    else
       echo "(*) Skipping governor setup. No ETCD_ENDPOINT. "
    fi

fi

start_supervisor

test ! -d ${CONFIG_DIR?}/.shared-data && mkdir ${CONFIG_DIR?}/.shared-data
touch ${CONFIG_DIR?}/.shared-data/db_activated && echo "(*) All databases are now active. "
touch ${SETUP_COMPLETE?} && echo "(*) Setup has completed."

#if ! setup_governor PRIMARY ${DB2INSTANCE} ${DBNAME?} ]; then
#       echo "(!!!) There was a failure during Governor setup... "
#       exit ${FALSE?}    
#fi

if [[ $1 = "db2start" ]]; then
    su - ${instance_name?} -c "db2start"
fi

# If the /var/custom directory exists, run all scripts there. It is for products that build on top of our base image
if [[ -d /var/custom ]]; then
    echo "(*) Running user-provided scripts ... "
    for script in `ls /var/custom`; do
       echo "(*) Running $script ..."
       /var/custom/$script
    done
fi

while :
   do
      tail -f ${DB2INSTANCE_HOME?}/sqllib/db2dump/DIAG0000/db2diag.log &
      wait
done

