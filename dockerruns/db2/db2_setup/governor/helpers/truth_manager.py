import logging
from config import config

try:
    import etcd2interface
except ImportError as e:
    print("Unable to import etcd2interface: {}".format(e))

try:
    import etcd3interface
except ImportError as e:
    print("Unable to import etcd3interface: {}".format(e))

logger = logging.getLogger(__name__)

class TruthManager:

    def __init__(self):
        try:
            self.type = config["truth_manager"]
        except KeyError as e:
            self.type = "etcd" # default
        self.store = None
        self.error_types = (Exception)
        try:
            conf = config[self.type]
            logger.info("using {} as truth_manager".format(self.type))
        except KeyError as e:
            logger.critical("config file does not have truth_manager and/or '%s' configuration is missing" % self.type)
        if self.type == "etcd":
            self.store = etcd2interface.Etcd()
            self.error_types = self.store.error_types
        elif self.type == "etcd3":
            self.store = etcd3interface.Etcd()
            self.error_types = self.store.error_types
        else:
            logger.critical("unknown truth_manager: %s" % self.type)

    # changes current endpoint to one that works
    def verify_endpoint(self, log = True):
        return self.store.verify_endpoint(log)

    # TODO: used by force_etcd.py to set leader key without a TTL - might want to make a proper public method
    def put_client_path(self, path, data):
        return self.store.put_client_path(path, data)

    def current_leader(self):
        return self.store.current_leader() 

    # take_leader with overwite leader key with TTL
    def take_leader(self, value):
        return self.store.take_leader(value)

    def attempt_to_acquire_leader(self, value):
        return self.store.attempt_to_acquire_leader(value)

    def attempt_to_delete_leader(self, value):
        return self.store.attempt_to_delete_leader(value)

    def update_leader(self, value, ttl = 0):
        return self.store.update_leader(value, ttl)

    # leader_unlocked returns true if leader key value is not there
    def leader_unlocked(self):
        return self.store.leader_unlocked()

    # get_prev_leader_timestamp reads timestamp value of prev key
    def get_prev_leader_timestamp(self):
        return self.store.get_prev_leader_timestamp()

    # set_prev_leader_timestamp writes value to prev key
    def set_prev_leader_timestamp(self, value):
        return self.store.set_prev_leader_timestamp(value)

    # am_i_leader returns true if leader key value matchs self
    def am_i_leader(self, value):
        return self.store.am_i_leader(value)
