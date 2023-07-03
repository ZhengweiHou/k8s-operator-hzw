import etcd3
import json, os, time, base64
import logging
from config import config

logger = logging.getLogger(__name__)
glog = False

class Etcd:

    def __init__(self):
        conf = config["etcd3"]
        self.timeout = conf["timeout"]
        self.ttl = conf["ttl"]

        self.scope = conf["scope"]
        self.endpoints = conf["endpoint"]
        self.host = None
        self.port = None
        self.ca_cert = conf["ca_cert"]
        self.cert_cert = None
        self.cert_key = None

        self.user = conf["user"]
        self.password = conf["password"]
        
        self.error_types = (Exception)
        self.client = None


    # get_client finds a working member to connect to if connection is lost
    def get_client(self, log=None):
        result = None
        print(self.client)
        if self.client is not None:
            try:
                status = self.client.status()
                print("Reuse connection")
                if log:
                    logger.info("Still connected to: %s:%s" % (self.host, self.port))
                result = self.client
                return result
            except self.error_types as e:
                self.client = None
                result = e
        if self.client is None:
            #print("Trying to get a fresh connection from %s" % self.endpoints)
            # fresh connection
            for endpoint in self.endpoints:
                print("endpoint: {0}".format(endpoint))
                end = endpoint.split(":")
                if len(end) == 2:
                    self.host = end[0]
                    self.port = end[1]
                try:
                    print("Attempt connect to: %s:%s" % (self.host, self.port))
                    if log:
                        logger.info("Attempt connect to: %s:%s" % (self.host, self.port))
                    result = etcd3.client(self.host, self.port, ca_cert=self.ca_cert, timeout=10, user=self.user, password=self.password)
                    self.client = result
                    status = self.client.status()
                    print("Established new connection to: {0}:{1}".format(self.host, self.port))
                    if log:
                        logger.info("Established new connection to: {0}:{1}".format(self.host, self.port))
                    return result
                except self.error_types as e:
                    print("exception: %s" % e)
                    self.client = None
                    # try the next one
                    result = e
        print("Unable to establish a working connection")
        if log:
            logger.warning("Unable to establish a working connection")
        raise result

    # changes current endpoint to one that works
    def verify_endpoint(self, log = True):
        if self.get_client(log):
            return True
        return False

    def get_client_path(self, path, max_attempts=1):
        attempts = 0
        max_attempts = 3
        response = None

        while True:
            try:
                etcd = self.get_client()
                print(type(etcd))
                if type(etcd) is not bool:
                    response = etcd.get(self.client_url(path))
                    # do we want to do anything with the metadata?
                    if response[1] is not None:
                        print("etcd3.get response was: {0} \nversion:{1}".format(response, response[1].version))
                        if response[1].lease_id is not None:
                            print("current lease ttl: {0}".format(response[1].lease_id))
                            lease_info = self.get_lease_info(response[1].lease_id)
                            print("time left: {0}".format(lease_info.TTL))
                    response = response[0]
                    break
                else:
                    attempts += 1
                    if attempts > max_attempts:
                        raise ValueError("Unable to get a connection to etcd")
            except self.error_types as e:
                attempts += 1
                if attempts < max_attempts:
                    if glog:
                        logger.warning("etcd failed to return {0}, trying again. ({1} of {2})".format(path, attempts, max_attempts))
                    time.sleep(3)
                else:
                    raise e
        try:
            return json.loads(response)
        except (ValueError, TypeError):
            return response

    def put_client_path(self, path, data):
        key = self.client_url(path)
        status = False
        # make sure value is string
        data["value"] = str(data["value"])
        try:
            etcd = self.get_client()
            lease = None
            if "ttl" in data and data["ttl"] is not None:
                print("Obtain a lease of %s" % data["ttl"])
                lease = etcd.lease(ttl=data["ttl"])

            if "prevExist" in data and data["prevExist"] is False:
                status, _ = etcd.transaction(
                    compare=[
                        etcd.transactions.version(key) == 0
                    ],
                    success=[
                        etcd.transactions.put(key, data["value"], lease)
                    ],
                    failure=[],
                )
                print("Transaction PUT {0}={1}".format(key, data["value"]))
            if "prevValue" in data:
                status, _ = etcd.transaction(
                    compare=[
                        etcd.transactions.value(key)  == data["prevValue"]
                    ],
                    success=[
                        etcd.transactions.put(key, data["value"], lease)
                    ],
                    failure=[],
                )
                print("Transaction PUT {0}={1}".format(key, data["value"]))
            else:
                etcd.put(key, data["value"], lease)
                print("PUT {0}={1}".format(key, data["value"]))
                status = True
        except self.error_types as e:
            print("Could not put key({0}): {1}".format(key,e))
            logger.info("Could not put to key({0}): {1}".format(key,e))
        return status

    def replace_client_path(self, path, data):
        etcd = self.get_client()
        if data["ttl"] is not None:
            lease = etcd.lease(ttl=data["ttl"])            
        etcd.replace(self.client_url(path), initial_value=data["prevValue"], new_value=data["value"], lease=lease)
        
    def delete_client_path(self, path):
        try:
            etcd = self.get_client()
            response = etcd.delete(self.client_url(path))
            return response
        except self.error_types as e:
            logger.info("Could not delete leader lock: %s" % e)
            return False

    def get_lease_info(self, lease_id):
        etcd = self.get_client()
        info = etcd.get_lease_info(lease_id)
        print("lease info: {0}".format(info))
        return info


    def client_url(self, path):
        return "/keys/service/%s%s" % (self.scope, path)

    def current_leader(self):
        try:
            return self.get_client_path("/leader")
        except self.error_types as e:
            return None

    def take_leader(self, value):
        self.put_client_path("/leader", value)
        return True

    def attempt_to_acquire_leader(self, value):
        try:
            self.put_client_path("/leader", {"value": value, "ttl": self.ttl, "prevExist": False})
            return True
        except self.error_types as e:
            return False

    def attempt_to_delete_leader(self, value):
        try:
            return self.delete_client_path("/leader")
        except Error as e:
            return False

    def update_leader(self, value, ttl = 0):
        ttl = self.ttl if ttl == 0 else ttl
        try:
            self.put_client_path("/leader", {"value": value, "ttl": ttl, "prevValue": value})
            return True
        except self.error_types as e:
            logger.error("Error updating leader lock and optime on ETCD for primary: %s" % e)
            return False

    def leader_unlocked(self):
        try:
            value = self.get_client_path("/leader")
            if value is None or value == "":
                return True
            return False
        except self.error_types as e:
            if type(e) is None:
                return True

    def get_prev_leader_timestamp(self):
        try:
            response = self.get_client_path("/prev")
            return int(response)
        except self.error_types as e:
            logger.error("Error retrieving previous leader key: %s" % e)
            return None

    def set_prev_leader_timestamp(self, value):
        try:
            self.put_client_path("/prev", {"value": value})
            return True
        except self.error_types as e:
            logger.error("Error updating previous leader key: %s" % e)
            return False

    def am_i_leader(self, value):
        try:
            reponse = self.get_client_path("/leader")
            logger.info("Lock owner: %s; I am %s" % (reponse, value))
            return reponse == value
        except self.error_types as e:
            print("am_i_leader exception: {0}".format(e))
            if type(e) is None:
                return None
