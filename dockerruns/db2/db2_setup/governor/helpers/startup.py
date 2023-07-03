import logging, atexit, subprocess, time, sys, datetime

from helpers.utils import CriticalDBError
from helpers.truth_manager import TruthManager
from helpers.db2 import Db2
from helpers.ha import Ha
from config import config

def init_standby(truth_manager, db2, ha):
    if not db2.start_as_standby():
        raise CriticalDBError("startup: cannot start as standby")
    while not truth_manager.current_leader():
        logging.info("startup: waiting on leader")
        time.sleep(5)

def init(truth_manager, db2, ha):
    db2.start()

    for i in range(1, 6):
        role = db2.get_role()
        if role:
            logging.info("startup: db2 previous role is %s" % role)
            break
        time.sleep(5)
    leader_timestamp = db2.fetch_leader_timestamp()
    truth_timestamp = truth_manager.get_prev_leader_timestamp()
    # this code can be improved to check the update timestamp and who the prev was in etcd3
    if leader_timestamp is not None:
        logging.info("leader_timestamp: {0} ({1})\n".format(leader_timestamp, datetime.datetime.fromtimestamp(int(leader_timestamp))))
    if truth_timestamp is not None:
        logging.info("truth_timestamp: {0} ({1})\n".format(truth_timestamp, datetime.datetime.fromtimestamp(int(truth_timestamp))))
    if truth_timestamp is None or leader_timestamp is None \
            or truth_timestamp <= leader_timestamp:
        if db2.is_primary():
            if db2.start_as_primary():
                ha.declare_leader()
                return
            else:
                raise CriticalDBError("startup: cannot start as primary")
    else:
        logging.info("TruthManager knows of a more recent leader as of {0}".format(datetime.datetime.fromtimestamp(int(truth_timestamp))))

    logging.info("startup: starting as standby")
    init_standby(truth_manager, db2, ha)

def initial_setup(truth_manager, db2, ha):
    while True:
        try:
            ha.lock_updater()
            init(truth_manager, db2, ha)
            ha.start_daemon_pool()
            break
        except CriticalDBError as e:
            logging.critical(e)
            sys.exit(1)
        except truth_manager.error_types as e:
            logging.warning(e)
            if not truth_manager.verify_endpoint():
                logging.critical("cannot connect to TruthManager")
                time.sleep(5)
