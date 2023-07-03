#!/bin/bash

# *******************************************************************************
#
# IBM CONFIDENTIAL
# OCO SOURCE MATERIALS
#
# COPYRIGHT: P#2 P#1
# (C) COPYRIGHT IBM CORPORATION 2016
#
# The source code for this program is not published or otherwise divested of
# its trade secrets, irrespective of what has been deposited with the U.S.
# Copyright Office.
#
# *******************************************************************************

#####################################################################
# This standalone tool validates:
#   * If all the required ports for internode communication are open.
#   * If passwordless SSH works for root and dashDB database users.
#####################################################################

# We need to get OS env set by RUNTIME_ENV
source /etc/profile

# Source the common function library
source /usr/lib/dashDB_local_common_functions.sh

# Record the time cost
start_time=$(logger_time_sec)

# Define global VARs
doneInit=true
chkAll=true
chkHADR=false
showHeaders=true
skipSSHchk=false
skipPortChk=false

NPING_ECHO_PORT=9929
DASHDB_PORT=50000
DASHDB_SSL_PORT=50001
DASHDB_HADR_START_PORT=60006
DASHDB_HADR_END_PORT=60007
DASHDB_FCM_START_PORT=60000
DASHDB_FCM_END_PORT=60024
DASHDB_SSH_PORT=50022
SPARK_START_PORT=25000
SPARK_END_PORT=25005
CALLHOME_CONNECTOR_PORT=8993
CALLHOME_SMCONNECTOR_PORT=9443

logfileAll="/tmp/comm_test.out"
npingErrLog="/var/log/nping_err.log"

while test $# -gt 0; do
   case "$1" in
      -init) doneInit=false
      ;;
      -single) chkAll=false
      ;;
      -noheaders) showHeaders=false
      ;;
      -hadr) shift; rhost=$1; chkHADR=true && skipSSHchk=true
      ;;
      -fast) skipPortChk=true
      ;; 
      -*)
      ;;
   esac
   shift
done

chk_ports()
{
   local RC=0
   local logfile="$logfileAll"
   while test $# -gt 0; do
      case "$1" in
         -h) shift; local hostSrv=$1
         ;;
         -p) shift; local portList=$1
         ;;
         -o) shift; local logfile=$1
         ;;
         -*)
         ;;
      esac
      shift
   done

   # Check if nping trace-back port is open
   nping_out="$(nping -c 1 --tcp-connect -p $NPING_ECHO_PORT $hostSrv 2>>$npingErrLog)"
   echo $nping_out | grep -q "Successful connections: 1"
   if [ $? -ne 0 ]; then
      cat <<EOF >> $logfile
The communication test needs port $NPING_ECHO_PORT to be opened.
Check the network and firewall settings, and ensure that the indicated port is open
On MPP clusters, check network and firewall settings on each node
EOF
   fi

   # Run nping ports checking
   nping -c 1 --echo-client --no-crypto --tcp --flags SAR -p $portList $hostSrv 2>> $(dirname $npingErrLog)/nping_err_$hostSrv.log 1>> /dev/null
   cat $(dirname $npingErrLog)/nping_err_$hostSrv.log | tee -a $npingErrLog | grep --ignore-case -q failed
   if [[ $? -eq 0 ]]; then
      RC=1
      cat <<EOF >> $logfile
Unable to communticate to node $hostSrv over the port(s) $portList
Check the network and firewall settings, and ensure that the indicated port/port range is open
On MPP clusters, check network and firewall settings on each node
  * port(s) $portList: `printf "${RED}CLOSED${NC}"`
EOF
   else
      echo "  * port(s) $portList: `printf "${GREEN}OPEN${NC}"`" >> $logfile
   fi
   rm -f $(dirname $npingErrLog)/nping_err_$hostSrv.log

   return $RC
}

# Test password-less SSH to root and db2inst1
chk_passwdless_ssh()
{
   local user="root"
   local logfile="$logfileAll"
   local RC=0

    while test $# -gt 0; do
        case "$1" in
           -u) shift; local user=$1
         ;;
            -h) shift; local hostSrv=$1
         ;;
            -o) shift; local logfile=$1
         ;;
            -*)
         ;;
      esac
      shift
   done

   if [[ "$user" != "root" ]]; then
      su - $user -c "ssh -q -o StrictHostKeyChecking=no -o NumberOfPasswordPrompts=1 -o ConnectTimeout=10 -p $DASHDB_SSH_PORT $dataNode date" &>> $logfile
   else
      ssh -q -o StrictHostKeyChecking=no -o NumberOfPasswordPrompts=1 -o ConnectTimeout=10 -p $DASHDB_SSH_PORT root@$hostSrv date &>> $logfile
   fi

   if [ $? -ne 0 ]; then
      RC=$?
      echo "Unable to communicate with node $hostSrv using passwordless SSH for the $user user." | sed -e 's/db2inst1/dbuser/' >> $logfile
      echo "  * $user user: `printf "${RED}FAIL${NC}"`" | sed -e 's/db2inst1/dbuser/' >> $logfile
   else
      echo "  * $user user: `printf "${GREEN}PASS${NC}"`" | sed -e 's/db2inst1/dbuser/' >> $logfile
   fi
   return $RC
}

# Check ports on the specific node
chk_ports_on_one_node()
{
   local RC=0
   local dataNode=$1
   local dbPortList=$2
   local logfile=$3

   local port_chk=$(printf "${GREEN}SUCCESS${NC}")
   local root_pwdlessSSH_chk=$(printf "${GREEN}SUCCESS${NC}")
   local dbusr_pwdlessSSH_chk=$(printf "${GREEN}SUCCESS${NC}")
   
   # Running port check on self (in docker run code path) does not need this header
   if [[ "$chkAll" == true ]]; then
      cat <<EOF >> $logfile
==============================================
Running communication test on node: $dataNode
==============================================
EOF
   fi

   if [[ "$skipPortChk" != true ]]; then
      # Test if we can probe the TCP ports used by dashDB database engine
      echo "Running database port check ..." >> $logfile
      chk_ports -h $dataNode -p "$dbPortList" -o "$logfile"
      ((RC=RC|$?))

      if [[ "$RC" != "0" ]]; then
         port_chk=$(printf "${RED}FAILURE${NC}")
      elif [[ "$chkHADR" != true ]]; then
         # We'll not do a hard port check for Spark -- IE even if Spark ports are
         # blocked we'll let the deployment go through, since not all deployments
         # will use Spark, and Spark may be disabled later as well.
         echo "Running Spark port check ..." >> $logfile
         chk_ports -h $dataNode -p "$SPARK_START_PORT-$SPARK_END_PORT" -o "$logfile"

         # Similar to spark Callhome ports will not have a hard check for now.
         echo "Running Callhome connector ports check ..." >> $logfile
         chk_ports -h $dataNode -p "$CALLHOME_CONNECTOR_PORT,$CALLHOME_SMCONNECTOR_PORT" -o "$logfile"
      fi

      if [[ "$RC" == "0"  &&  "$skipSSHchk" != true ]]; then
         echo "Running SSH port check ..." >> $logfile
         chk_ports -h $dataNode -p "$DASHDB_SSH_PORT" -o "$logfile"
         ((RC=RC|$?))
      fi
   fi

   if [[ "$RC" == "0" && "$doneInit" == true && "$skipSSHchk" != true ]]; then
      echo "Running passwordless SSH check ..." >> $logfile
      chk_passwdless_ssh -u root -h $dataNode
      if [[ $? -ne 0 ]]; then
         root_pwdlessSSH_chk=$(printf "${RED}FAILURE${NC}")
         ((RC=RC|1))
      fi

      chk_passwdless_ssh -u db2inst1 -h $dataNode
      if [[ $? -ne 0 ]]; then
         dbusr_pwdlessSSH_chk=$(printf "${RED}FAILURE${NC}")
         ((RC=RC|1))
      fi
   fi

   if [[ "$showHeaders" == true ]]; then
      cat <<EOF >> $logfile

************************************************************************
---                The $IBM_PRODUCT communication test summary             ---
************************************************************************
The node name: $dataNode
EOF
      if [[ "$skipPortChk" != true ]]; then
         echo "The communication test: $port_chk" >> $logfile
      fi

      if [[ "$doneInit" == true ]]; then
         echo "The password-less SSH test:" >> $logfile
         echo " * root user: $root_pwdlessSSH_chk" >> $logfile
         echo " * The database user: $dbusr_pwdlessSSH_chk" >> $logfile
      fi

      cat <<EOF >> $logfile
************************************************************************
EOF
      echo ""
   fi
   return $RC
}


#----------------------------------------------------------
#  MAIN
#----------------------------------------------------------

if [[ -f "$logfileAll" ]]; then
   mv "$logfileAll" "$logfileAll.bak"
fi

if [[ -f "$npingErrLog" ]]; then
   mv "$npingErrLog" "$npingErrlog.bak"
fi

if [[ "$showHeaders" == true ]]; then
   cat <<EOF | tee $logfileAll

***************************************
 Running $IBM_PRODUCT communication test ...
***************************************

EOF
fi

#if ! [ $(wc -l ${BLUMETAHOME}/db2inst1/sqllib/db2nodes.cfg | awk '{print $1}') -gt 1 ]; then
if [ ! -f $NODESFILE ]; then
   echo "The $IBM_PRODUCT configuration: SMP" | tee -a /tmp/comm_test.out
   nodeList=("$(hostname -s):$(hostname -i)")
   dbPortList="$DASHDB_PORT-$DASHDB_SSL_PORT"
   if [[ "$chkHADR" == true ]]; then
      nodeList+=("$rhost")
      dbPortList="$DASHDB_PORT-$DASHDB_SSL_PORT,$DASHDB_HADR_START_PORT-$DASHDB_HADR_END_PORT"
   fi
else
   echo "The $IBM_PRODUCT configuration: MPP" | tee -a /tmp/comm_test.out
   if [[ "$chkAll" != true ]]; then
      echo "Testing communications on the current node only ..."
      echo ""
      nodeList=("$(hostname -s):$(hostname -i)")
   else
      #nodeList=($(python2.7 -c "from nodes_helper import *; print_nodes(get_valid_nodes())"))
      nodeList=($(/usr/lib/nodes_helper.py --file $NODESFILE --valid-nodes))
   fi
   dbPortList="$DASHDB_PORT-$DASHDB_SSL_PORT,$DASHDB_FCM_START_PORT-$DASHDB_FCM_END_PORT"
fi

# Set ANSI control codes to annotate output of devOps health check script
RED=$(echo '\033[0;31m'); GREEN=$(echo '\033[0;32m'); NC=$(echo '\033[0m') # No Color

RC=0
for h in "${nodeList[@]}"; do
   dataNode=$(echo $h | awk -F':' '{print $1}')
   logfile="/tmp/comm_test_$dataNode.out"

   if [[ -f "$logfile" ]]; then
      mv "$logfile" "$logfile.bak"
   fi

   # Run the port check on each node in parallel
   ( chk_ports_on_one_node $dataNode "$dbPortList" "$logfile" ) &

   # Store pids of all processes
   pids+=("$!")
done

# Wait all processes to finish
for p in ${pids[@]}; do
   wait $p
   if [[ "$?" != "0" ]]; then
      RC=$?
      break
   fi
done

for h in "${nodeList[@]}"; do
   dataNode=$(echo $h | awk -F':' '{print $1}')
   logfile="/tmp/comm_test_$dataNode.out"
   cat $logfile | tee -a $logfileAll
done

logger_elapsed "comm_test" $start_time
exit $RC
