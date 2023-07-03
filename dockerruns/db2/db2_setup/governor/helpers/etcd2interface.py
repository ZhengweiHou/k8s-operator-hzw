import urllib2, json, os, time, base64, ssl, httplib
import logging
from urllib import urlencode
from config import config

logger = logging.getLogger(__name__)

# Monkey patch ssl, blame python developer community for this
if hasattr(ssl, '_create_unverified_context'):
    ssl._create_default_https_context = ssl._create_unverified_context

class Etcd:

    def __init__(self):
        conf = config["etcd"]
        self.scope = conf["scope"]
        self.endpoints = conf["endpoint"]
        self.endpoint = self.endpoints[0]
        self.cert = None if not config.is_prod() else conf["cert"]
        if conf.has_key("authentication"):
            self.authentication = conf["authentication"]
        else:
            self.authentication = None
        self.ttl = conf["ttl"]
        self.timeout = conf["timeout"]
        self.error_types = (urllib2.HTTPError, urllib2.URLError, ssl.SSLError, httplib.BadStatusLine)

    # changes current endpoint to one that works
    def verify_endpoint(self, log = True):
        for endpoint in self.endpoints:
            self.endpoint = endpoint
            try:
                self.get_client_path("", 2)
                if log:
                    logger.info("connected to endpoint %s" % self.endpoint)
                return True
            except self.error_types as e:
                logger.warning("caught exception: cannot connect to endpoint %s, error %s" % (self.endpoint, e))
        return False

    def get_client_path(self, path, max_attempts=1):
        attempts = 0
        response = None

        while True:
            try:
                request = urllib2.Request(self.client_url(path))
                if self.authentication is not None:
                    base64string = base64.encodestring('%s:%s' % (self.authentication["username"], self.authentication["password"])).replace('\n', '')
                    request.add_header("Authorization", "Basic %s" % base64string)
                response = urllib2.urlopen(request, timeout=self.timeout, cafile=self.cert).read()
                break
            except self.error_types as e:
                attempts += 1
                if attempts < max_attempts:
                    logger.warning("etcd failed to return %s, trying again. (%s of %s)" % (path, attempts, max_attempts))
                    time.sleep(3)
                else:
                    raise e
        try:
            return json.loads(response)
        except ValueError:
            return response

    def put_client_path(self, path, data):
        request = urllib2.Request(self.client_url(path), data=urlencode(data).replace("false", "False"))
        if self.authentication is not None:
            base64string = base64.encodestring('%s:%s' % (self.authentication["username"], self.authentication["password"])).replace('\n', '')
            request.add_header("Authorization", "Basic %s" % base64string)
        request.get_method = lambda: 'PUT'
        urllib2.urlopen(request, timeout=self.timeout, cafile=self.cert).read()

    def delete_client_path(self, path):
        try:
            request = urllib2.Request(self.client_url(path))
            if self.authentication is not None:
                base64string = base64.encodestring('%s:%s' % (self.authentication["username"], self.authentication["password"])).replace('\n', '')
                request.add_header("Authorization", "Basic %s" % base64string)
            request.get_method = lambda: 'DELETE'
            return urllib2.urlopen(request, timeout=self.timeout, cafile=self.cert).read()
        except self.error_types as e:
            logger.info("Could not delete leader lock: %s" % e)
            return False

    def client_url(self, path):
        return "%s/v2/keys/service/%s%s" % (self.endpoint, self.scope, path)

    def current_leader(self):
        try:
            return self.get_client_path("/leader")["node"]["value"]
        except urllib2.HTTPError as e:
            if e.code == 404:
                return None
        except self.error_types as e:
            logger.warning("etcd error getting leader: %s" % e)
            return None

    def take_leader(self, value):
        return self.put_client_path("/leader", {"value": value, "ttl": self.ttl}) == None

    def attempt_to_acquire_leader(self, value):
        try:
            return self.put_client_path("/leader", {"value": value, "ttl": self.ttl, "prevExist": False}) == None
        except urllib2.HTTPError as e:
            if e.code == 412:
                logger.info("Could not take out TTL lock: %s" % e)
            return False
        except self.error_types as e:
            logger.warning("etcd error putting leader: %s" % e)
            return False

    def attempt_to_delete_leader(self, value):
        try:
            return self.delete_client_path("/leader")
        except self.error_types as e:
            logger.warning("etcd error deleting leader: %s" % e)
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
            self.get_client_path("/leader")
            return False
        except urllib2.HTTPError as e:
            if e.code == 404:
                return True
            logger.warning("etcd unexpected HTTPError getting leader: %s" % e)
        except self.error_types as e:
            logger.warning("etcd error getting leader, be safe assume leader not available: %s" % e)
            return False

    def get_prev_leader_timestamp(self):
        try:
            response = self.get_client_path("/prev")
            return response["node"]["value"]
        except (urllib2.HTTPError, urllib2.URLError) as e:
            logger.error("Error retrieving previous leader key: %s" % e)
            return None
  
    def set_prev_leader_timestamp(self, value):
        try:
            self.put_client_path("/prev", {"value": value})
            logger.info("Etcd: updated /prev with %s" % value)
            return True
        except (urllib2.HTTPError, urllib2.URLError) as e:
            logger.error("Error updating previous leader key: %s" % e)
            return False

    def am_i_leader(self, value):
        try:
            reponse = self.get_client_path("/leader")
            logger.info("Lock owner: %s; I am %s" % (reponse["node"]["value"], value))
            return reponse["node"]["value"] == value
        except urllib2.HTTPError as e:
            if e.code == 404:
                return None
            logger.warning("etcd unexpected HTTPError getting leader: %s" % e)
            return None
        except self.error_types as e:
            logger.warning("etcd error getting leader: %s" % e)
            return None
