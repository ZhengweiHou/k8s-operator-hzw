import os, logging, sys, threading, time

from helpers.utils import *
from config import config
sys.path.append("/opt/ibm/db2oc_infra/py_modules/db2pd_c/db2pd_cache")
from db2pd_entries import Db2pdEntries, is_tablespace_good

logger = logging.getLogger(__name__)

class Db2:

    def __init__(self):
        conf = config["db2"]
        self.db = conf["db"]
        self.auth = conf["authentication"]
        self.timeout = config["op_timeout"]
        self.ip = conf["ip"]
        self.ip_other = conf["ip_other"]
        self.timestamp_file = config['timestamp_file']
        self.force_takeover_window = config["force_takeover_window"]
        self.refresh_lock = threading.RLock()
        self.can_connect = True
        self.is_up = True
        self.init_time = time.time()
        self.last_peer_time = -1
        self.hadr_ret = (0, 4)
        self.start_ret = (0, 1)
        self.ret = {"hadr": (0, 4), "start": (0, 1), "activate": (0, 4)}

    def update_leader_timestamp(self, timestamp):
        logging.info("Writing ({}) to timestamp_file: {}".format(timestamp, self.timestamp_file))
        return run_cmd("echo {} | sudo tee {}".format(timestamp, self.timestamp_file), False)[1]

    def fetch_leader_timestamp(self):
        if os.path.isfile(self.timestamp_file):
            leader_timestamp = run_cmd("sudo cat {}".format(self.timestamp_file), False)[0]
            return leader_timestamp.replace('\n', '') if leader_timestamp != "" else None
        return None

    def is_primary(self):
        return str_cmp(self.get_role(), "primary")

    def is_standby(self):
        return str_cmp(self.get_role(), "standby")

    def is_standard(self):
        return str_cmp(self.get_role(), "standard")

    def is_primary_or_standby(self):
        return self.is_primary() or self.is_standby()

    def get_role(self):
        status = None
        cmd = "db2 get db cfg for %s" % self.db
        out = run_cmd(cmd.split(), False, 1, 20, (0,), False)[0]
        for line in out.splitlines():
            if "role" in line:
                status = line.split()[-1]
                break
        return status

    def load_state(self, log = True):
        state = self.get_hadr_state()
        role = self.get_role()
        connect_status = state['hadr_connect_status']
        state = state['hadr_state']
        if log:
            logging.info("""
                            db2 role is %s,
                            db2 connect status is %s,
                            db2 state is %s
                            """ % (role, connect_status, state))

        if state == None or connect_status == None:
            return False
        return True

    def is_connected(self):
        connect_status = self.get_hadr_state()["hadr_connect_status"]
        return str_cmp(connect_status, "connected")

    def is_disconnected_peer(self):
        state = self.get_hadr_state()["hadr_state"]
        logging.info("db2 state is %s" % state)
        return str_cmp(state, "disconnected_peer")

    def is_peer(self):
        state = self.get_hadr_state()["hadr_state"]
        logging.info("db2 state is %s" % state)
        return str_cmp(state, "peer")

    def is_running(self):
        output, rc = run_cmd("ps -ef | grep -i db2sysc | grep -v grep", False, 1)
        if output is not None and rc == 0:
            logging.info("db2 is running")
            self.is_up = True
            return True
        self.is_up = False
        logging.info("db2 is not running")
        return False

    def ping(self):
        ret = run_cmd("db2 ping %s" % self.db, False, 1)[1] in (0, -1)
        if not ret:
            logging.warning("db2 cannot be pinged")
        else:
            logging.info("db2 can be pinged")
        return ret

    def connect(self, crash_recovery = False):
        timeout = self.timeout["connect"]
        log = False
        if crash_recovery:
            self.refresh_lock.acquire()
            timeout = None
            log = True

        rc = run_cmd("db2 connect to %s user %s using %s" % (self.db, self.auth["username"], self.auth["password"]), log, 1, timeout)[1]

        if crash_recovery:
            self.refresh_lock.release()

        return rc == 0

    def start(self):
        rc = run_cmd("db2start", True, 2, self.timeout["start"], self.ret["start"])[1]
        return rc in self.ret["start"]

    def start_as_standby(self):
        self.start()
        rc = run_cmd("db2 start hadr on db %s as standby" % self.db, True, 3, self.timeout["start_as_standby"], self.ret["hadr"])[1]
        ret = rc in self.ret["hadr"]
        if not ret:
            raise CriticalDBError("cannot start as standby")

        self.is_up = True
        return ret

    def start_as_primary(self):
        self.refresh_lock.acquire()
        self.start()
        rc = run_cmd("db2 start hadr on db %s as primary by force" % self.db, True, 2, None, self.ret["hadr"])[1]
        ret = rc in self.ret["hadr"] and self.connect(True)
        if ret:
            self.is_up = True
        self.refresh_lock.release()
        return ret

    def activate(self):
        rc = run_cmd("db2 activate db %s" % self.db, True, 2, None, self.ret["activate"])[1]
        if rc in self.ret["activate"]:
            if self.is_primary():
                if self.connect(True):
                    return True
                else:
                    self.stop()
                    return self.start_as_primary()
            else:
                return True
        return False

    def start_activate(self):
        self.start()
        return self.activate()

    def kill(self):
        out = run_cmd("db2nps 0 | grep db2sysc")[0]
        if out:
            proc = out.split()[1]
            run_cmd("kill -9 %s" % proc, True)

    def stop(self):
        if run_cmd("db2stop force", True, 0, None)[1] != 0:
            self.kill()

    def takeover(self, force = False, peer_window = False):
        cmd = "db2 takeover hadr on db %s" % self.db
        if force:
            cmd += " by force"
        if peer_window:
            cmd += " peer window only"
        return run_cmd(cmd, True, 0, None)[1] == 0

    def promote(self):
        self.refresh_lock.acquire()
        ret = False
        # for timing issues
        if not self.is_up:
            self.start_activate()

        if not self.is_primary():
            # try regular takeover in peer state
            # then force takeover in peer window on fail
            if (self.is_peer() and self.takeover()) or self.takeover(True, True):
                ret = True
            else:
                # check if we are inside force window
                # before trying to force outside of peer window
                elapsed_time = int(time.time()) - self.last_peer_time
                if self.last_peer_time < 0:
                    # handle startup case
                    elapsed_time = int(time.time() - self.init_time)
                    logging.info("last_peer_time invalid, using init_time: %s (%ds ago)" % (self.init_time, elapsed_time))
                if not self.force_takeover_window or (elapsed_time < self.force_takeover_window):
                    logging.info("we have the mandate to force takeover (window=%s)" % self.force_takeover_window)
                    if self.takeover(True, False):
                        ret = True
                    else:
                        logging.error("failed to force takeover outside of peer window")
                else:
                    logging.error("last peer time %s (%ds ago), exceeded force takeover window of %ss" % (self.last_peer_time, elapsed_time, self.force_takeover_window))

        ret = ret and self.connect(True)
        self.refresh_lock.release()
        return ret

    def demote(self):
        if not self.is_peer():
            self.stop()

    def is_read_only(self):
        path = ['/database/config', '/database/data']
        for p in path:
            if run_cmd("sudo touch %s" % os.path.join(p, ".a"), False)[1] != 0:
                logging.error("%s is read only" % p)
                return False
        return False

    def get_hadr_state(self):
        ret = {'hadr_state':None, 'hadr_connect_status':None}
        try:
            db2pd = Db2pdEntries(db_name=self.db)

            for key in ret:
                if key == 'hadr_state':
                    if db2pd.get_current_node_metric("HADR_STATE").strip():
                        ret[key] = db2pd.get_current_node_metric("HADR_STATE")
                elif key == 'hadr_connect_status':
                    if db2pd.get_current_node_metric("HADR_CONNECT_STATUS").strip():
                        ret[key] = db2pd.get_current_node_metric("HADR_CONNECT_STATUS")

        except Exception:
            pass
        return ret

    def check_tablespaces(self):
        try:
            return is_tablespace_good(self.db)
        except Exception as e:
            logging.error("error checking table spaces on standby, error: %s" % e)
            return False
