#!/bin/bash

###############################################################################
#   Backup licenses and DB/DBM CFG
#
# Copyright 2017, IBM Corporation
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################
SETUPDIR=/var/db2_setup
source ${SETUPDIR?}/include/db2_constants

# Make a backup of the nodelock file only if the user applied
# a different license than what is shipped in the docker image.
# A backup is needed so that it can be restored later on without the user
# having to reapply the same license.
# The logic assumes that the user applied a different license if the checksum of
# the $DB2DIR/nodelock and the checksum of the original license do not match.
# Note that once a user applies any license explicitly (eg: using db2licm -a)
# then they will be responsible for the license from then on.
actual=`openssl md5 ${DB2DIR?}/license/nodelock | awk '{print $2}'`
expected=`${DB2DIR?}/bin/db2fupdt -f ${CONFIG_DIR?}/instance.cfg -s license -p checksum`

if [ "${actual?}" != "${expected?}" ]; then

   date && mkdir ${CONFIG_DIR?}/licenses/
   echo "(*) Backing up the nodelock file... "
   echo "nodelock checksum in DB2DIR: ${actual?}"
   echo "nodelock checksum in backup: ${expected?}"

   cp ${DB2DIR?}/license/nodelock* ${CONFIG_DIR?}/licenses
fi

# Make a backup of the global.reg file
rm -f ${CONFIG_DIR?}/global.reg
cp /var/db2/global.reg ${CONFIG_DIR?}/global.reg.new
mv ${CONFIG_DIR?}/global.reg.new ${CONFIG_DIR?}/global.reg

# Export DB and DBM cfg only when PERSISTENT_HOME is set to false.
# If we export it periodically via supervisor, db2cfexp throws warnings
# in the db2diag log, which may confuse users.
# Reason is the known issue with Docker for Windows where chown and chmod are
# allowed on shared drives.
# See https://docs.docker.com/docker-for-windows/troubleshoot/#permissions-errors-on-data-directories-for-shared-volumes

test "${PERSISTENT_HOME?}" = "false" && su - ${DB2INSTANCE?} -c "db2cfexp ${CONFIG_FILE?} template"

# For connection with DSM, we need to export the list of databases created 
# so DSM can catalog them 
dblist=`su - ${DB2INSTANCE?} -c "db2 list db directory | grep \"Database alias\"" | cut -d= -f2 | sed -e 's/ //g' | tr '\n' ',' | sed 's/,\s*$//'`
${DB2DIR?}/bin/db2fupdt -f ${CONFIG_DIR?}/instance.cfg -s database -p list -v "${dblist}"


sleep 2m
