#!/bin/bash

###############################################################################
#
# Copyright 2017, IBM Corporation
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################
# Options for "set" command
setopts="${setopts:-+x}"
set ${setopts?}

SETUPDIR=/var/db2_setup
source ${SETUPDIR?}/include/db2_constants
source ${SETUPDIR?}/include/db2_common_functions

# Container IP address changes on ICP environment during container restart.
# We need to make sure /etc/hosts has the correct IP for the HADR remote host
if [ -f "${HADR_SHARED_DIR?}/hadr.cfg" ]; then

    my_hostname=$(hostname -f)
    my_ip_addr=$(hostname -i)
    domain=$(dnsdomainname)

    while [ -f "${HADR_CONFIG_LOCKFILE?}" ]; do
        echo "(*) Waiting to acquire ${HADR_CONFIG_LOCKFILE?} ...";
        sleep 10
    done

    touch ${HADR_CONFIG_LOCKFILE?}

    remote_host=$(${DB2DIR?}/bin/db2fupdt -f ${HADR_SHARED_DIR?}/hadr.cfg -p primary_hostname)
    remote_ip=$(${DB2DIR?}/bin/db2fupdt -f ${HADR_SHARED_DIR?}/hadr.cfg -p primary_ipaddr)
    if [ "${my_hostname?}" = "${remote_host?}" ]; then
        remote_host=$(${DB2DIR?}/bin/db2fupdt -f ${HADR_SHARED_DIR?}/hadr.cfg -p standby1_hostname)
        remote_ip=$(${DB2DIR?}/bin/db2fupdt -f ${HADR_SHARED_DIR?}/hadr.cfg -p standby1_ipaddr)
    fi

    remote_node_name=$(cut -d '.' -f 1 <<< "${remote_host?}")
    update_etc_hosts "${remote_node_name?}" "${remote_ip?}" "${domain?}"

    rm -f ${HADR_CONFIG_LOCKFILE?}
   
fi

sleep 10

