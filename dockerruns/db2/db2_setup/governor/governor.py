#!/usr/bin/env python

import sys, os, yaml, time, urllib2, logging, atexit

from logging import handlers
from config import config
from helpers.utils import CriticalDBError
from helpers.truth_manager import TruthManager
from helpers.db2 import Db2
from helpers.ha import Ha
from helpers.startup import *

try:
    config.load_config()
except IOError:
    print("missing db2.yml configuration file")
    sys.exit(1)

fname = "/var/log/governor/governor.log" if config.is_prod() or config.is_stage() else None

if config.is_prod() or config.is_stage():
    handler = logging.handlers.WatchedFileHandler(fname)
    handler.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(process)d-%(thread)d: %(message)s'))
    logger = logging.getLogger()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
else:
    logging.basicConfig(filename=fname, format='%(asctime)s %(levelname)s %(process)d-%(thread)d: %(message)s', level=logging.INFO)

def wait_loop(truth_manager):
    while True:
        if truth_manager.verify_endpoint():
            if truth_manager.current_leader():
                break
        time.sleep(config["loop_wait"])

def run():
    truth_manager = TruthManager()
    db2 = Db2()
    ha = Ha(db2, truth_manager)

    #atexit.register(ha.webserver.shutdown)

    logging.info("Governor Starting up")
    initial_setup(truth_manager, db2, ha)

    while True:
        try:
            ha.monitor_daemon()
            logging.info("Governor Running: %s" % ha.run_cycle())
        except truth_manager.error_types as e:
            logging.error("http error: %s" % e)
            if not truth_manager.verify_endpoint():
                if db2.is_connected():
                    logging.warning("cannot connect to TruthManager, do nothing")
                    logging.critical(e)
                else:
                    if db2.is_primary():
                        db2.stop()
                    else:
                        wait_loop(truth_manager)
            else:
                logging.warning("network blip, TruthManager is up, continue")
                if db2.is_primary():
                    continue
                else:
                    logging.warning("wait for 50 seconds for primary to recover from network blip")
                    time.sleep(50)

        except KeyError as e:
            logging.error("TruthManager key error, cluster might be shutting down or in unstable state")
            continue

        except CriticalDBError as e:
            logging.critical(e)
            sys.exit(1)

        logging.info("sleeping for %s seconds" % str(config["loop_wait"]))
        time.sleep(config["loop_wait"])

if __name__ == "__main__":
    run()
