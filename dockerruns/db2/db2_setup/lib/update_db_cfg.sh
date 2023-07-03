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

# Source profile if the OS env-vars used by DB cfg update is not set
[[ ( -z "$ARCHLOGPATH" ) || ( -z "$LDAP_HOME" ) ]] && source /etc/profile

db_cfg_file=${1:-/tmp/bluemix.medium.bludb.cfg}
database=$2
instance=$3
# Remove leading and trailing whitespace, ignore blank & commented lines
cat ${db_cfg_file} | sed 's/^[ \t]*//;s/[ \t]*$//' | while read value; do
    [[ $value =~ ^#|^$ ]] && continue
    su - ${instance?} -c "db2 -v update db cfg for ${database?} using $value"
done
# db2 -v connect reset
