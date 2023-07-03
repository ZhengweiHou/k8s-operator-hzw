#!/bin/bash
#
# When running unprivileged containers with --ipc=host the IPC resources of the
# container is not namespaced -- IE. all containers on the host have the host's
# view of IPC resources. The problem with that is, if the container / POD in k8
# gets killed that can end up leaving IPC segments around in the memory map,
# which will eventually impact the memory allocation. Hence each container on
# start up, need to cleanup up invalid IPC resources before Db2 processes are
# started.
#
# To ensure we only remove IPC resources owned by Db2 users and detached (to
# support multi-tenanet Db2 envs) the following cleanup-logic will be applied:
# * IPC shared memory segments: look at nattach counter, and remove IPC memory
#   segments owned by Db2 users if the value is 0, IE detached. In addition
#   any IPC shared memory segments owned by Db2 users where creator/last-op PID
#   is init (PID 1) will be removed as well (see note).
# * IPC message queues: will be removed if owned by Db2 users and the current
#   state of the last process to send/receive a message is one of "Z (zombie)",
#   or "X (dead)".
#
# Note: A shared memory object is only removed after all currently attached
# processes (nattach counter=0) have detached the object from their virtual
# address space. When containers are killed without proper signal handling, PIDs
# under the process group of the container init PID can get reattached to hosts
# init PID (PID 1) -- I have seen this happen few times in the past.
# That is, trying to clean IPC shared resources from inside container namespace
# might not always work as expected.
#
# Ref: ipcrm(1), shmdt(2) and proc(5)
#
clean_ipc() {
    local clean_ipc_log="/tmp/clean_ipc.log"
    echo "Running IPC resource cleanup" | tee $clean_ipc_log
    echo "IPC clean output will be logged to ${clean_ipc_log} file inside container namespace"
    echo "Dumping all the IPC resources visible to the container namespace" &>> $clean_ipc_log
    ipcs -a &>> $clean_ipc_log
    echo "Cleaning up IPC shared memory and message queue resources" &>> $clean_ipc_log
    local db2usr_uid=$(id db2inst1 | awk '{print $1}' | sed -e 's/^.*=//' -e 's/(.*)//')
    local db2fenusr_uid=$(id db2fenc1 | awk '{print $1}' | sed -e 's/^.*=//' -e 's/(.*)//')
    local db2adm_gid=$(id db2inst1 | awk '{print $2}' | sed -e 's/^.*=//' -e 's/(.*)//')
        
    local owner_regex="$db2usr_uid|$db2fenusr_uid|db2(inst|fenc)1"
    local cpid lpid lspid lrpid
    # Set defaults in case we hit a lazy update of OPTIONSFILE
    db2usr_uid=${db2usr_uid:-1000}
    db2fenusr_uid=${db2fenusr_uid:-1001}
    db2adm_gid=${db2adm_gid:-1000}
    # IPC resource cleanup commands
    local IPCRM_M="setpriv --reuid=$db2usr_uid --regid=$db2adm_gid --clear-groups ipcrm -m"
    local IPCRM_Q="setpriv --reuid=$db2usr_uid --regid=$db2adm_gid --clear-groups ipcrm -q"
    local IPCRM_S="setpriv --reuid=$db2usr_uid --regid=$db2adm_gid --clear-groups ipcrm -s"
    #
    ### Cleanup IPC shared memory segments ###
    #
    # Cleanup all detached IPC shared memory segments owned by Db2 users
    ipcs -m | grep -E "$owner_regex" | awk '/^0x[0-9a-f]+/ { if ($6 == 0) {print $2;} }' | \
        xargs -t -L 1 -r ${IPCRM_M} &>> $clean_ipc_log
    # IPC resources enumerated from /proc/sysvipc/[msg|sem|shm] is not always
    # refreshed immediately. So trying short wait and do a dummy read of proc fs to see if that helps
    sleep 2; ipcs -a &> /dev/null
    # Cleanup any IPC shared memory segments owned by Db2 users where creator/last-op PID
    # is init (PID 1)
    ipcs -m -p | grep -E "$owner_regex" | awk '/^[0-9]+/ { if ($3 == 1 || $4 == 1) {print $1;} }' | \
        xargs -t -L 1 -r ${IPCRM_M} &>> $clean_ipc_log
    sleep 2; ipcs -a &> /dev/null
    # Cleanup any IPC shared memory segments owned by Db2 users where current
    # state of the creator/last-op process is one of "Z (zombie)", or "X (dead)"
    # or there is no corresponding /proc/<PID>
    ipcs -m -p | grep -E "$owner_regex" | awk '/^[0-9]+/ {print $3 " " $4}' | while read cpid lpid
    do
        # Since UNIX ps tool is not namespace aware and use /proc/<PID>,
        # cat /proc/$cpid/status | awk '/^State:/ {print $2}' and
        # ps --no-headings -o state $cpid should look at the same resource view.
        ps --no-headings -o state $lpid | grep -E "^[ZX]$" && ipcs -m -p | awk "NF == 4 && \$NF == $lpid { print \$1 }" | \
            xargs -t -L 1 -r ${IPCRM_M} &>> $clean_ipc_log
        ps --no-headings -o state $cpid | grep -E "^[ZX]$" && ipcs -m -p | awk "NF == 4 && \$(NF-1) == $cpid { print \$1 }" | \
            xargs -t -L 1 -r ${IPCRM_M} &>> $clean_ipc_log
        # Remove IPC shared memory segments owned by Db2 users but there is no
        # process associated, IE there is no corresponding /proc/<PID>
        ps --no-headings -o state $lpid || ipcs -m -p | awk  "NF == 4 && \$NF == $lpid { print \$1 }" | \
            xargs -t -L 1 -r ${IPCRM_M} &>> $clean_ipc_log
        ps --no-headings -o state $cpid || ipcs -m -p | awk  "NF == 4 && \$(NF-1) == $cpid { print \$1 }" | \
            xargs -t -L 1 -r ${IPCRM_M}  &>> $clean_ipc_log
    done
    sleep 2; ipcs -a &> /dev/null
    #
    ### Cleanup IPC message queues ###
    #
    # Cleanup any IPC message queues owned by Db2 users where current state of
    # the last process to send/receive a message is one of "Z (zombie)", or "X (dead)"
    # or there is no corresponding /proc/<PID>.
    ipcs -q -p | grep -E "$owner_regex" | awk '/^[0-9]+/ { if ($3 != 0 && $4 != 0 ) {print $3 " " $4;} }' | while read lspid lrpid
    do
        ps --no-headings -o state $lrpid | grep -E "^[ZX]$" && ipcs -q -p | awk "NF == 4 && \$NF == $lrpid { print \$1 }" | \
            xargs -t -L 1 -r ${IPCRM_Q}  &>> $clean_ipc_log
        ps --no-headings -o state $lspid | grep -E "^[ZX]$" && ipcs -q -p | awk "NF == 4 && \$(NF-1) == $lspid { print \$1 }" | \
            xargs -t -L 1 -r ${IPCRM_Q}  &>> $clean_ipc_log
        # Remove IPC message queues owned by Db2 users but there is no
        # process associated, IE there is no corresponding /proc/<PID>
        ps --no-headings -o state $lrpid || ipcs -q -p | awk "NF == 4 && \$NF == $lrpid { print \$1 }" | \
            xargs -t -L 1 -r ${IPCRM_Q}  &>> $clean_ipc_log
        ps --no-headings -o state $lspid || ipcs -q -p | awk "NF == 4 && \$(NF-1) == $lspid { print \$1 }" | \
            xargs -t -L 1 -r ${IPCRM_Q}  &>> $clean_ipc_log
    done
    sleep 2; ipcs -a &> /dev/null
    # FIXME -- From current testing the following can potentially yank IPC message
    # queues from another instance. Perhaps can be done if single-tenant.
    # Cleanup any IPC message queues owned by Db2 users where no message has
    # been received or sent (IE. LSPID == LRPID == 0)
    ipcs -q -p | grep -E "$owner_regex" | awk '/^[0-9]+/ { if ($3 == 0 && $4 == 0) {print $1;} }' | \
        xargs -t -L 1 -r ${IPCRM_Q}  &>> $clean_ipc_log
    sleep 2; ipcs -a &> /dev/null
    #
    ### Cleanup IPC semaphores ###
    #
    # Cleanup any IPC semaphores owned by Db2 users where current state of
    # the last process used the semaphore is one of "Z (zombie)", or "X (dead)"
    # or there is no corresponding process.
    local pid semid
    ipcs -s | grep -E "$owner_regex" | cut -d ' ' -f 2 | while read semid
    do
        pid=$(ipcs -s -i $semid | awk '/^semnum/ {getline; print $5}')
        if [[ $pid -ne 0 ]]; then
            ps --no-headings -o state $pid | grep -E "^[ZX]$" && ${IPCRM_S} $semid &>> $clean_ipc_log
        else
            # FIXME -- Remove the semaphore when the last process is not running, IE PID = 0
            # However, there is a risk maybe that semaphore is used by other processes.
            ${IPCRM_S} $semid &>> $clean_ipc_log
        fi
        # Remove IPC semaphores owned by Db2 users but there is no
        # process associated, IE there is no corresponding /proc/<PID>
        ps --no-headings -o state $pid || ${IPCRM_S} $semid &>> $clean_ipc_log
    done
    sleep 2; ipcs -a &> /dev/null
    # TODO -- Will enable if really needed since haven't found a good method to
    # find if a semaphore is not used by another Db2 instance in multi-tenant env.
    # ipcs -s -c | grep -E "$owner_regex" | cut -d' ' -f1 | \
    #   xargs -t -L 1 -r ${IPCRM_S}  &>> $clean_ipc_log
    echo "IPC resources visible to the container namespace after cleanup"  &>> $clean_ipc_log
    ipcs -a  &>> $clean_ipc_log
    echo "IPC summary" &>> $clean_ipc_log
    ipcs -u &>> $clean_ipc_log
}
clean_ipc
