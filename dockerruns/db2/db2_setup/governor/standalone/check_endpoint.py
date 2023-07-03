#!/usr/bin/env python

import sys, os, yaml, time, urllib2, logging

from config import config
from helpers.truth_manager import TruthManager
from helpers.db2 import Db2
from helpers.utils import *

try:
    config.load_config()
except IOError:
    print("missing db2.yml configuration file")
    sys.exit(1)

logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s', level=logging.INFO)

def check_truth(truth):
    if truth.verify_endpoint(False):
        logging.info("verify endpoint success")
    else:
        logging.info("verify endpoint fail")
        sys.exit(1)

def check_leader(truth, db2):
    leader = truth.current_leader()
    if not leader:
        logging.info("no leader")
        sys.exit(2)
    else:
        if leader == db2.ip:
            out = run_cmd('hostname -s', False)[0]
            logging.info("leader is %s" % out)

def check_tablespaces(db2):
    if not db2.check_tablespaces():
        logging.info("tablespaces not healthy")
    else:
        logging.info("tablespaces healthy")

if __name__ == "__main__":
    truth = TruthManager()
    db2 = Db2()

    if sys.argv[1] == "etcd":
        check_truth(truth)
    if sys.argv[1] == "leader":
        check_leader(truth, db2)
    if sys.argv[1] == "tablespaces":
        check_tablespaces(db2)
