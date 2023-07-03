#!/bin/bash

###############################################################################
#   Use DB2 recommended settings for DB, DBM, WLM
#
# Copyright 2017, IBM Corporation
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################

dbname=$1

cd /tmp
db2 connect to ${dbname?}

db2 "call SYSPROC.ADMIN_CMD( 'AUTOCONFIGURE USING MEM_PERCENT 80 APPLY NONE' )" > autoconfig_sysproc.out

recvalues=`cat autoconfig_sysproc.out | sed '/.*LEVEL NAME.*/d' | sed '/.*Result set.*/d' | sed '/.*Return Status.*/d' | sed '/.*record(s) selected.*/d' | sed '/^\s*$/d' | sed 's/^.*-----//' | awk {'print $1":"$2":"$3":"$4'}`

for line in ${recvalues?}
do
   type=`echo ${line?} | cut -d: -f1`
   name=`echo ${line?} | cut -d: -f2`
   curval=`echo ${line?} | cut -d: -f3`
   recval=`echo ${line?} | cut -d: -f4`

   if [ "${type?}" == "DB" ] && [ "${curval?}" != "${recval?}" ]
   then
      if [ "${name?}" == "{logfilsiz?}" ]
      then
         recval=$((${recval?} * 4))
      fi

      if [ "${name?}" == "logprimary" ] || [ "${name?}" == "logsecond" ]
      then
         recval=$((${recval?} * 2))
      fi

      echo "Updating ${type?} CFG ${name?} - Current value (${curval?}); new value (${recval?})" >> set_rec_values.out
      db2 update db cfg using ${name?} ${recval?}
   fi
done

# Restart DBM to take effect for non-dynamic settings
db2 connect reset
db2stop
db2start
