import sys, os, logging, time
from helpers.utils import *
from helpers.db2 import Db2
from helpers.netinterface import NetInterface
from config import config

class Webserver:

    def __init__(self, db2, check_lock_func):
        self.db2 = db2
        self.logger = logging.getLogger(__name__)
        self.logger.setLevel(logging.INFO)
        self.interface = NetInterface()
        self.check_lock = check_lock_func
        if config.is_prod() or config.is_stage():
            fh = logging.FileHandler("/var/log/governor/webserver.log")
            fh.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(process)d-%(thread)d: %(message)s'))
            self.logger.addHandler(fh)

    def start(self):
        self.logger.warning("webserver starting up")
        run_cmd("/opt/ibm/dsserver/bin/start.sh", timeout=600)

    def stop(self):
        self.logger.warning("webserver stopping")
        run_cmd("/opt/ibm/dsserver/bin/stop.sh", timeout=600)

    def is_up(self):
        out, rc = run_cmd("/opt/ibm/dsserver/bin/status.sh", False)
        if out and out.splitlines()[-1].split()[-1].lower() == "inactive":
            return False
        return True

    def shutdown(self):
        self.interface.disable_public_interface()
        if self.is_up():
            self.stop()

    def run(self):
        while True:
            if self.check_lock():
                self.interface.enable_public_interface()
                if not self.is_up():
                    self.start()
            else:
                if not self.db2.is_primary():
                    self.shutdown()
            time.sleep(10)
