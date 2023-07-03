#!/bin/bash

#copy license files over into new DB2
cp /database/config/licenses/nodelock* /opt/ibm/db2/V*/license/
cp /database/config/licenses/*lic* /opt/ibm/db2/V*/license/

#most recent configuration file available
configuration=`cd /database/config && ls -t cfg_* | head -1`

#import configuration files
su - db2inst1 -c "db2cfimp /database/config/${configuration?}"
