source /etc/profile

CONTAINER_NAME="Db2wh"

EXAMPLE_CONTAINER_FOOTNOTE="Note: ${CONTAINER_NAME} is an example of a container name. Use the container name that you specified for the docker run command."

#####################################################################
#
# Define the common message texts used by deployment code here.
#
#####################################################################

ERROR_RUNTIME_ENV_NOTSET="
#########################################################################################
Unable to discover the runtime environment.
For managed deployments you need to specify an appropriate RUNTIME_ENV value
that need to be enumerated to:
    docker run -dit .... -e RUNTIME_ENV=[ V2.0 | AP1.0 ]
#########################################################################################
"

KITEMATIC_FAILURE="
#########################################################################################
Unable to determine if the VM booted from boot2docker ISO.
Confirm that Docker Toolbox is set up correctly by issuing this command:
  docker run hello-world
Also confirm that the VirtualBox VM started properly.
#########################################################################################
"

PREREQ_CHECK_FAILED="
#####################################################################
Prerequisite check failed.
Examine the relevant messages printed to the console window when
the prerequisite check was running and take the required corrective
actions before attempting to set up ${IBM_PRODUCT}.
Exiting deployment.
#####################################################################
"

MPP_START_NEXT_STEPS_TEXT="
***********************************************************
**                  You're almost there                  **
***********************************************************

The ${IBM_PRODUCT} software stack will be started soon on the cluster ...

* Next steps:
    1. If you were already monitoring the container startup progress using the
       docker logs --follow ${CONTAINER_NAME} command, you can continue to do so.

    2. (optional) Instead of mointoring the progress of service startup via Docker
       logs console, from the head node you can issue the following command:
        docker exec -it ${CONTAINER_NAME} status --check-startup

    3. You should see the *** Successfully deployed ${IBM_PRODUCT} *** banner
       if the services started successfully.

    ${EXAMPLE_CONTAINER_FOOTNOTE}

* The first time you start services in an MPP configuration, it takes
  longer for them to be configured and for all the nodes to be enabled.
"

MPP_UPDATE_NEXT_STEPS_TEXT="
***********************************************************
**                  You're almost there                  **
***********************************************************

The ${IBM_PRODUCT} software stack will be updated and then started
soon on the cluster ...

* Next steps:
    1. If you were already monitoring the container startup progress using the
       docker logs --follow ${CONTAINER_NAME} command, you can continue to do so.

    2. (optional) Instead of mointoring the progress of service startup via Docker
       logs console, from the head node you can issue the following command:
        docker exec -it ${CONTAINER_NAME} status --check-startup

    3. You should see the *** Successfully started ${IBM_PRODUCT} *** banner
       if the services started successfully.

    ${EXAMPLE_CONTAINER_FOOTNOTE}
"

DASHDB_INSTANCE_CREATION_FAILED="
${IBM_PRODUCT} instance creation failed.
Retry the operation. If the same failure occurs, contact IBM Service.
If a command prompt is not visible on your screen, you need to detach from the container by typing Ctrl-C.
"

DASHDB_UPGRADE_FAILURE_TEXT="
######################################################${HASHES}
## ${IBM_PRODUCT} has not started because at least one of the     ##
## services could not be started.                   ${SPACES}##
######################################################${HASHES}

1. Clean up your failed deployment:
    * Remove the container using the docker rm -f command.
    * Remove the image using the docker rmi command.
    * Delete the contents of the mounted host volume specified in the docker
      run command (e.g. docker run ... -v <host volume>:/mnt/bludata0).
      Note: THIS WILL RESULT IN DATA LOSS

2. Redeploy the image.

######################################################${HASHES}

"

DASHDB_UPDATE_CONTAINER_FAILED_SERVICES_TEXT="

######################################################${HASHES}
## ${IBM_PRODUCT} has not started after the upgrade because at    ##
## least one of the services could not be started.  ${SPACES}##
######################################################${HASHES}

1. Stop and restart the services using the following commands:
   a) docker exec -it ${CONTAINER_NAME} stop
   b) docker exec -it ${CONTAINER_NAME} start

2. If the service stop and restart in step 1 is not successful:
    * Remove the container using the docker rm command.
    * Remove the image using the docker rmi command.
    Note: DO NOT delete the contents from the mounted host volume specified in
    the docker run command (e.g. docker run ... -v <host volume>:/mnt/bludata0).

3. Retry the upgrade process.

If you cannot successfully upgrade, contact the IBM Support team.

 ${EXAMPLE_CONTAINER_FOOTNOTE}



"

DASHDB_CONTAINER_FAILED_SERVICES_TEXT="

######################################################${HASHES}
## ${IBM_PRODUCT} has not started because at least one of the     ##
## services could not be started.                   ${SPACES}##
######################################################${HASHES}

1. Use the following suggestions to help address the service-start failures:
    * Ensure SELinux or AppArmor are not enabled.
    * (MPP deployments) Ensure that the nodes configuration file is formatted
      correctly
    * (MPP deployments) Ensure that the /etc/hosts file on each node specifies
      all the participating nodes, using the following format:
        IP  <Fully Qualified Domain Name>  <short name> [<any other aliases >]
    * (MPP deployments) Ensure all nodes have their dates and times
      synchronized
    * Ensure the ports between the nodes are open:
        * ${IBM_PRODUCTS} ports: 50000, 50001, 60000 - 60024
        * SSH ports: 22 for hosts,  50022 for containers
        * LDAP port: 389
        * Spark ports: 25000 - 25999

2. Stop and restart the services using the following commands:
   a) docker exec -it ${CONTAINER_NAME} stop
   b) docker exec -it ${CONTAINER_NAME} start

3. If the service stop and restart in step 2 is not successful:
  * If this is an initial deployment (Note: THIS WILL RESULT IN DATA LOSS):
    a) Remove the container using the docker rm -f command.
    b) Remove the image using the docker rmi command.
    c) Delete the contents of the mounted host volume specified in the docker
       run command (e.g. docker run ... -v <host volume>:/mnt/bludata0)
       Note: Back up this directory to avoid data loss
    d) Redeploy the image.

  * If this is NOT an initial deployment, call IBM Support.

 ${EXAMPLE_CONTAINER_FOOTNOTE}

######################################################${HASHES}

"

SMP_TO_MPP_CONVERSION_BLOCKED="
* An SMP deployment cannot be converted to an MPP deployment.
* You need to perform a fresh MPP deployment.
"

MISSING_SYSCFGBKPDIR="
Unable to locate the configuration backup directory.
Retry the update process by performing the following steps:
    1. Stop the new container
    2. Start the old container.
    3. Back up the system configuration manually by issuing the following command.
       On an MPP system, you must issue the command on each node:
        docker run -it ${CONTAINER_NAME} backup_systemconfig
    4. If the system backup fails, check the cluster file system that you
       used for the external volume. If you cannot resolve the problem, call IBM Support.
    5. Stop the old container.
    6. Start the new container. The update process automatically resumes.

${EXAMPLE_CONTAINER_FOOTNOTE}
"

INSTALLATION_FAILED_NEXT_STEPS="
* If this is an initial deployment:
  a) Remove the container using the 'docker rm -f ${CONTAINER_NAME}' command.
  b) Remove the image using the 'docker rmi <image>' command.
  c) Delete the contents of the mounted host volume specified in the docker run command
    (e.g. docker run ... -v <host volume>:/mnt/bludata0)
    Note: THIS WILL RESULT IN DATA LOSS
  d) Redeploy the image.

${EXAMPLE_CONTAINER_FOOTNOTE}
"

INSTALLATION_FAILED_NEXT_STEPS_KM="
* If this is an initial deployment, use the Kitematic GUI to:
  a) Delete this container.
  b) Open the Docker CLI (bottom-left) and clear /mnt/sda1/clusterfs on the boot2docker VM by
     issuing the following commands (Note: THIS WILL RESULT IN DATA LOSS):
        docker-machine ssh default
        sudo rm -fr /mnt/sda1/clusterfs/*
  b) Back in the Kitematic GUI, click on the '+ NEW' button and search for the latest Kitematic image under the
     ibmdashdb repository.
  c) Redeploy the Kitematic image.
"

STARTING_DASHDB_SERVICES="
######################################################${HASHES}
###   Starting all the services in the ${IBM_PRODUCT} stack      ###
######################################################${HASHES}

  * If this is a new deployment, the stack is initialized, which might
    take a while.
  * If this is a container update, it might take a while to start the services,
    depending on whether an engine or database update is required.
"

DASHDB_TRIAL_LICENSE_EXPIRED="
######################################################${HASHES}
###     The ${IBM_PRODUCT} trial license has expired             ###
######################################################${HASHES}
* If you want to continue using ${IBM_PRODUCT}, obtain a production license from
  Passport Advantage (PA). To view or purchase new entitlements, you must log in by
  using your IBM ID into PA.
* To apply a production license, execute the following procedure from the head
  node:
  1. Save the license key in the root directory of the cluster file system.
  2. Issue the following command:
      docker exec -it ${CONTAINER_NAME} dashlicm -a /mnt/blumeta0/<license file name>
  3. Issue the start command:
      docker exec -it ${CONTAINER_NAME} start

${EXAMPLE_CONTAINER_FOOTNOTE}
######################################################${HASHES}
"

EXTERNAL_IP_LOOKUP_FAILED="
* Unable to discover the external IP address to access the Web Console URL ...
* Please list the IP interfaces using 'ip a s' command and consult with your
* site's Network administrator to identify the external network interface/IP
"

IGNORE_HCHK_DB_STATUS_IF_HADR="

################################################################################
###      The status for a deployment that uses HADR might be FAILED          ###
################################################################################
  * If you issued the manage_hadr command with the '-takeover force' parameter,
    you must reintegrate the old primary node as the standby node by issuing
    the 'manage_hadr' command with the -start_as standby parameter.

"

HADR_SETUP_HEADER="

######################################################${HASHES}
###           ${IBM_PRODUCT} high availability and               ###
###                disaster recovery (HADR) setup  ${SPACES}###
######################################################${HASHES}

* Usage notes:
  * Confirm that the system clock skew between HADR nodes is no more than 5
    seconds. On each node issue the 'date +%s' command to get the elapsed
    seconds since UNIX time (epoch time), and then compare the difference.
    Configuring both HADR nodes to use Network Time Protocol (NTP) ensures that
    the system clocks are always synchronized.

  * If you chose the database backup method (-use_backup) to initialize HADR,
    place the backup image and the keystore tar file that you created by
    running the setup_hadr command on the primary node, into the
    $<root of the external file system>/scratch directory of the standby node
    before running the setup_hadr command on the standby node.

  * If you chose the snapshot backup method (-use_snapshot) to initialize HADR,
    make the snapshot device and the file system available to the standby node
    before running the setup_hadr command on the standby node.

"

HADR_SETUP_NEXT_STEPS_P_BACKUP="

######################################################${HASHES}
###               ${IBM_PRODUCT} HADR setup - next steps         ###
###                       for -use_backup method   ${SPACES}###
######################################################${HASHES}

  1) Transfer the database backup image and the keystore tar file from the
     $<root of the external file system>/scratch directory of the primary node
     into the same path on the standby node.

  2) On the standby node, issue the following command:
      docker exec -it ${CONTAINER_NAME} setup_hadr -standby \
        -remote <hostname>:<IP address> -use_backup

  ${EXAMPLE_CONTAINER_FOOTNOTE}
"

HADR_SETUP_DO_P_SNAP="

* The database was placed into the write-suspend state. That is,
  all writes (IUD operations) to the database are blocked.

* Take your snapshot backup by using the flashcopy or snapshot technology
  of your choice now.

* The database is automatically taken out of write-suspend state, if you do
  not respond to the prompt.

"

HADR_SETUP_NEXT_STEPS_P_SNAP="

######################################################${HASHES}
###               ${IBM_PRODUCT} HADR setup - next steps         ###
###                       for -use_snapshot method ${SPACES}###
######################################################${HASHES}

  1) After you make the snapshot copy available to the standby node, deploy
     ${IBM_PRODUCT} the HADR standby node. You must specify the -e HADR_ENABLED
     parameter for the docker run command.

  2) Issue the following command to setup HADR:
      docker exec -it ${CONTAINER_NAME} setup_hadr -standby \
        -remote <hostname>:<IP address> -use_snapshot

  ${EXAMPLE_CONTAINER_FOOTNOTE}
"

HADR_SETUP_TRAILER_P="

################################################################################
###        The HADR setup command completed the primary node setup.          ###
################################################################################

"

HADR_SETUP_TRAILER_S="

################################################################################
###        The HADR setup command completed the standby node setup.          ###
################################################################################

* Next steps:
  1) On the current (standby) node, issue the following command:
      docker exec -it ${CONTAINER_NAME} manage_hadr -start_as standby

  2) On the primary node, issue the following command:
      docker exec -it ${CONTAINER_NAME} manage_hadr -start_as primary

  3) Monitor HADR status by issuing the following command on any node:
      docker exec -it ${CONTAINER_NAME} manage_hadr -status

  ${EXAMPLE_CONTAINER_FOOTNOTE}

"

HADR_SETUP_USAGE="

################################################################################

* Usage: docker exec -it ${CONTAINER_NAME} setup_hadr [ -primary | -standby ]
    -remote <hostname>:<IP address> [ -use_backup | -use_snapshot ] -reinit

  where:
    * -primary | -standby specifies whether you are setting up HADR on the
      primary or standby node.
    * -remote <hostname>:<IP address> specifies the remote host. If you are
      running the command on the primary node, specify the hostname and IP
      address of the standby node. If you are running the command on the
      standby node, specify the hostname and IP address of the primary node.
    * -use_backup | -use_snapshot specifies whether to use a database backup or
      snapshot copy to initialize the HADR standby node.
    * -reinit will reinitializes HADR. If you reinitialize HADR on the primary
      node, you must reinitialize HADR on the standby node too.

  ${EXAMPLE_CONTAINER_FOOTNOTE}

################################################################################

"

HADR_ENABLED_DETECTED="

********************************************************************************
###        High availability and disaster recovery (HADR) is enabled.        ###
********************************************************************************
* Next steps:
    * If you already set up HADR, use the manage_hadr command for various HADR
      operational tasks.
    * To set up HADR use the setup_hadr command.
    * The web console runs only on the HADR primary node.
    * If you add users through the web console after a failover to the standby
      node, you must add those same users after failback to the original
      primary node.

"

HADR_SETUP_BACKUP_DB="
* ${IBM_PRODUCT} completed the following tasks:
  * Backed up the database (BLUDB) on the primary node into the
    <root of the external volume>/scratch directory.
  * Backed up the encryption keystore that is used by the database
    on the primary node into the <root of the external volume>/scratch
    directory.
"

HADR_SETUP_RESTORE_DB="
* ${IBM_PRODUCT} completed the following tasks:
  * Verified the integrity of the backup image that was saved into the
    <root of the external volume>/scratch directory.
  * Restored the encryption keystore that is used by the database
    onto the standby node.
  * Restored the database (BLUDB) backup image onto the standby node.
"

HADR_SETUP_ERROR_P_OR_S="
* You can setup only one node at a time: either the primary or the standby.
"

HADR_SETUP_ERROR_BKP_OR_SNAP="
* You can use only one of the standby node initialization methods: specify
  either the -use_backup parameter or the -use_snapshot parameter, not both.
"

HADR_SETUP_ERROR_GENERAL="

################################################################################
* HADR setup could not proceed.
* Correct the errors and run the hadr_setup command.
################################################################################

"

HADR_MISSING_ARGS="
* You must supply the following options to configure HADR:
    - The remote host
    - The local HADR service port
    - The remote HADR service port
"

HADR_MISSING_SVCE_NAMES="
* The HADR service ports db2_hadrp and db2_hadrs are not defined in the
  /etc/services file.
"

HADR_CLOCK_DRIFT_OVER_LIMIT="
* The clock drift between the primary and standby nodes is greater than
  5 seconds.
* Use NTP to synchronize clocks on both systems, and retry the HADR setup.
"

HADR_IS_SMP_ONLY="
* The high availability and disaster recovery (HADR) feature is supported for
  SMP (single-node) deployments only.
"

HADR_MANAGE_USAGE="

################################################################################

* Usage: docker exec -it ${CONTAINER_NAME} manage_hadr -start_as [ primary | standby ]
    | -stop | -status | -takeover [ force ] | -update_db | -enable_acr [ ssl ]

  where:
    * -start_as [ -primary | -standby ] specifies whether to attempt to start
      HADR on the primary or standby node.

    * -stop stops HADR on the primary node. On the standby node, this parameter
      will also deactivate the database.

    * -status shows key HADR metrics. An example follows:
        Database Member 0 -- Database BLUDB -- Active -- Up 1 days 23:30:27 --
                                    HADR_ROLE = PRIMARY
                                   HADR_STATE = PEER
                          PRIMARY_MEMBER_HOST = bluhelix19
                          STANDBY_MEMBER_HOST = bluhelix20
                          HADR_CONNECT_STATUS = CONNECTED
                     HADR_CONNECT_STATUS_TIME = 03/25/2017 15:59:43.095232 (...)
                    PRIMARY_LOG_FILE,PAGE,POS = S0000011.LOG, 31863, 2453487119
                    STANDBY_LOG_FILE,PAGE,POS = S0000011.LOG, 31863, 2453487119
             STANDBY_REPLAY_LOG_FILE,PAGE,POS = S0000011.LOG, 31863, 2453487119
                              PEER_WINDOW_END = 03/27/2017 15:31:57.000000 (...)

    * -takeover gracefully switches the roles between the current primary and
      standby node. If you specify the force option after the -takeover
      parameter, an attempt is made to takeover HADR by force peer window first.
      If that fails, a takeover HADR by force instruction is issued.

    * -update_db updated database objects. Run the managed_hadr command with
      this parameter on the HADR primary node as the final step when updating
      and SMP deplpoyment that uses HADR. This parameter is not supported on
      the standby node.

    * -enable_acr specifies that automatic client reroute (ACR) is used to
      transfer client application requests from a failed primary node to the
      standby node. The database system directory is updated with the
      alternative node information, as well the LDAP directory is updated with
      the same information.
      If you specify the ssl option after the -enable_acr parameter, ACR uses
      the SSL port that is defined for ${IBM_PRODUCT} (50001).

  ${EXAMPLE_CONTAINER_FOOTNOTE}
################################################################################

"

HADR_MANAGE_HEADER="

######################################################${HASHES}
###           ${IBM_PRODUCT} high availability and               ###
###             disaster recovery (HADR) management${SPACES}###
######################################################${HASHES}

"

HADR_MANAGE_ERROR_GENERAL="

################################################################################
* The requested HADR operation failed.
* Correct the errors and rerun the manage_hadr command.
################################################################################

"

HADR_MANAGE_TAKEOVER_SUCCESS="

################################################################################
###            The manage_hadr command completed an HADR takeover.           ###
################################################################################

"

HADR_MANAGE_START_SUCCESS="

################################################################################
###                 The manage_hadr command started HADR.                    ###
################################################################################

"

HADR_MANAGE_STOP_SUCCESS="

################################################################################
###                   The manage_hadr command stopped HADR.                  ###
################################################################################

"

HADR_MANAGE_UPDATE_SUCCESS="

################################################################################
###     The manage_hadr command updated database on the the primary node.    ###
################################################################################

"

HADR_MANAGE_ENABLE_ACR_SUCCESS="

################################################################################
###        The manage_hadr command configured ACR on the HADR database.      ###
################################################################################

"

HADR_FAILED_TO_DISABLE_REDUCED_REDO_LOGGING="

* Unabled to disable reduced redo logging on this node.
* Using HADR is not supported when reduce redo logging is enabled.
* Please contact IBM support for help.

"
