import os, sys, logging

from config import config
from helpers.truth_manager import TruthManager
from helpers.db2 import Db2
from helpers.utils import *

try:
    config.load_config()
except IOError:
    print("missing db2.yml configuration file")
    sys.exit(1)

fname = "/var/log/governor/governor.log" if config.is_prod() or config.is_stage() else None
logging.basicConfig(filename=fname, format='%(asctime)s %(levelname)s: %(message)s', level=logging.INFO)

if __name__ == "__main__":
    truth = TruthManager()
    db2 = Db2()
    leader = truth.current_leader()

    if not (db2.is_peer() or db2.is_disconnected_peer()):
        logging.info("db2 hadr is not in peer state, fix the db first before switching leader")
        print("db2 hadr is not in peer state, fix the db first before switching leader")
        out = run_cmd('/opt/ibm/dashtxn-hadr-deployment/chkHADRState.sh')
        print(out[0])
        sys.exit(1)

    if leader:
        logging.info("current leader is %s" % leader)
        print("current leader is %s" % leader)
        new_leader = db2.ip if leader != db2.ip else db2.ip_other
        logging.info("new leader is %s" % new_leader)
        print("new leader is %s" % new_leader)
        truth.take_leader(new_leader)
        logging.info("manual switch leader complete")
        sys.exit(0)
    else:
        logging.info("no leader existed")
        print("no leader existed")
        sys.exit(1)

