#!/bin/bash

# Compute IPC kernel parameters as per KC topic
# https://www.ibm.com/support/knowledgecenter/SSEPGG_11.1.0/com.ibm.db2.luw.qb.server.doc/doc/c0057140.html

ram_in_BYTES=$(LANG=C free -b | awk '/^Mem:/ {print $2}')
ram_GB=$(LANG=C free -g |  awk '/^Mem:/ {print $2}')
host_procsys_mnt=/host/proc/sys/kernel
PAGESZ=$(getconf PAGESIZE)


((shmmni=256 * $ram_GB))
shmmax=$ram_in_BYTES
((shmall=2 * (${ram_in_BYTES?} / ${PAGESZ?} )))
((msgmni=1024 * $ram_GB))
msgmax=65536
msgmnb=$msgmax
SEMMSL=250
SEMMNS=256000
SEMOPM=32
SEMMNI=$shmmni

echo "IPC kernel parameters before updating .. "
ipcs -l

for param in shmmni shmmax shmall msgmni msgmax msgmnb; do 
    echo "${!param}" > ${host_procsys_mnt}/${param}
done 

echo "${SEMMSL?} ${SEMMNS?} ${SEMOPM?} ${SEMMNI?}" > ${host_procsys_mnt?}/sem

echo "IPC kernel parameters after updating .. "
ipcs -l
