import sys, time, re, urllib2, json, logging, time
from base64 import b64decode
from helpers.utils import *
#from helpers.webserver import Webserver
from config import config
from helpers.netinterface import NetInterface

logger = logging.getLogger(__name__)

class Ha:

    def __init__(self, state_handler, truth):
        self.state_handler = state_handler
        self.truth_manager = truth
        self.status = None
        self.daemon_pool = {}
        #self.webserver = Webserver(state_handler, self.has_lock)

    def acquire_lock(self):
        if not self.state_handler.is_primary():
            if not self.state_handler.check_tablespaces():
                return False
        return self.truth_manager.attempt_to_acquire_leader(self.state_handler.ip)

    def discard_lock(self):
        return self.truth_manager.attempt_to_delete_leader(self.state_handler.ip)

    def update_lock(self):
        return self.truth_manager.update_leader(self.state_handler.ip)

    def is_unlocked(self):
        return self.truth_manager.leader_unlocked()

    def has_lock(self):
        return self.truth_manager.am_i_leader(self.state_handler.ip)

    def declare_leader(self):
        timestamp = int(time.time())
        self.truth_manager.set_prev_leader_timestamp(timestamp)
        self.state_handler.update_leader_timestamp(timestamp)

    def lock_updater(self):
        self.daemon_pool["lock_updater"] = start_daemon(self.keep_updating_lock)

    def health_checker(self):
        self.daemon_pool["health_checker"] = start_daemon(self.check_health)

    def webserver_watchdog(self):
        self.daemon_pool["webserver"] = start_daemon(self.webserver.run)

    def db_watchdog(self):
        self.daemon_pool["db"] = start_daemon(self.check_db)

    def start_daemon_pool(self):
        self.health_checker()
        #self.webserver_watchdog()
        self.lock_updater()
        self.db_watchdog()

    def monitor_daemon(self):
        for key, thd in self.daemon_pool.iteritems():
            if thd is None or not thd.isAlive():
                if thd:
                    logging.warning("%s daemon died %s" % (key, thd))
                else:
                    logging.info("did not find thread for key %s" % key)
                if key == "lock_updater":
                    self.daemon_pool[key] = self.lock_updater()
                elif key == "health_checker":
                    self.daemon_pool[key] = self.health_checker()
                elif key == "webserver":
                    self.daemon_pool[key] = self.webserver_watchdog()
                elif key == "db":
                    self.daemon_pool[key] = self.check_db()

    def check_db(self):
        while True:
            self.state_handler.is_running()
            time.sleep(config["loop_wait"])

    def keep_updating_lock(self):
        try:
            while True:
                if self.state_handler.refresh_lock._RLock__count:
                    logging.info("lock_updater: refreshing lock for prolonged operation")
                    self.update_lock()
                time.sleep(config["loop_wait"])
        except truth_manager.error_types as e:
            logging.error("lock_updater thread: http error: %s, cannot update lock" % e)

    def check_connect(self):
        if not self.state_handler.connect() and self.state_handler.is_primary():
            logging.warning("health_checker: cannot connect, should die")
            self.state_handler.can_connect = False
        else:
            logging.info("health_checker: passed db connection check")

    def check_health(self):
        while True:
            if self.state_handler.is_primary():
                self.check_connect()
            else:
                self.state_handler.can_connect = True
            time.sleep(config["loop_wait"])

    def check_run(self, ret):
        if not ret:
            logging.warning("operation failed, releasing lock")
            self.discard_lock()
        return ret

    def db_active(self):
        loaded = self.state_handler.load_state()
        if self.state_handler.is_primary():
            if self.state_handler.ping() and self.state_handler.can_connect:
                logging.info("db can be pinged or connected")
                return True
            else:
                logging.warning("db2 cannot be pinged or connected")
                return False
        else:
            if self.state_handler.is_peer():
                self.state_handler.last_peer_time = int(time.time())
            return loaded

    def db_state_ok(self):
        if not self.state_handler.is_read_only():
            logging.info("disk is writable")
            if self.state_handler.is_up and self.db_active():
                return True
            else:
                logging.warning("i am dead")
                if self.has_lock():
                    logging.warning("restart as primary")
                    self.check_run(self.state_handler.start_as_primary())
                    self.status = "database software was stopped on primary.  starting again."
                else:
                    logging.warning("stop and restart as standby")
                    self.state_handler.stop()
                    self.state_handler.start_as_standby()
                    self.status = "database software was stopped on standby.  starting again."
        else:
            logging.warning("disk is readonly, die")
            self.state_handler.demote()
            self.status = "suicide, waiting for takeover"

        logging.warning("db2 was in bad state")
        return False

    def run_cycle(self):
        # if db is in good state, go into TruthManager logic
        if self.db_state_ok():
            if self.is_unlocked():
                # note time.sleep returns None
                if self.state_handler.is_primary() or not time.sleep(10):
                    logging.info("Leader is unlocked - race to grab leader key")
                    if self.acquire_lock():
                        logging.info("Acquired leader_lock.")
                        if not self.state_handler.is_primary():
                            logger.warning("Acquired lock, promote")
                            if self.check_run(self.state_handler.promote()):
                                self.declare_leader()
                                self.status = "promoted self to leader by acquiring session lock"
                            else :
                                self.status = "failed to promote self to leader"
                        else:
                            self.status = "acquired session lock as a leader"
                    else:
                        logging.info("Failed to acquire leader_lock.")
                        if self.state_handler.is_primary():
                            # split brain
                            logger.warning("Potential split brain. Failed to acquire leader_lock. Demoting myself")
                            self.state_handler.demote()
                            self.status = "demoted self due after trying and failing to obtain lock"
                        else:
                            self.status = "no action. im standby without lock"
                else:
                    self.status = "SHOULD NOT BE ABLE TO GET HERE"
            else:
                if self.has_lock():
                    if self.update_lock() or self.acquire_lock():
                        if not self.state_handler.is_primary():
                            logger.warning("I have lock, promote")
                            if self.check_run(self.state_handler.promote()):
                                self.declare_leader()
                                self.status = "promoted self to leader because i had the session lock"
                            else :
                                self.status = "failed to promote self to leader"
                        else:
                            self.status = "no action. i am the leader with the lock"
                    else:
                        self.status = "i had the lock but i lost it"
                else:
                    logger.info("I do not have lock")
                    if self.state_handler.is_primary():
                        # split brain
                        logger.warning("Potential split brain. Someone else has leader_lock. Demoting myself")
                        self.state_handler.demote()
                        self.status = "demoting self because i do not have the lock and i was a leader"
                    else:
                        self.status = "no action. im standby without lock"
        return self.status
