import etcd3, time
from helpers.etcd3interface import Etcd
from config import config

print("Starting")
config.load_config()
print("Config loaded")
conf = config["etcd"]

fname = "/var/log/governor/governor.log" if config.is_prod() or config.is_stage() else None

endpoint = conf["endpoint"][0]
parts = endpoint.split(":")
host = parts[0]
port = parts[1]
cert = conf["ca_cert"]

user = conf["user"]
password = conf["password"]

try:
    print(">>> RAW python-etcd3 test")
    client = etcd3.client(host, port, ca_cert=cert, cert_cert="dummycert.pem", cert_key="dummykey.pem", timeout=10, user=user, password=password)
    print("got client: %s" % client)
    lease = client.lease(ttl=30)
    print("got lease: %s" % lease)
    client.put("/keys/foo", "bar", lease)
    print("PUT done")
    result = client.get('/keys/foo')
    print("GET returned")
    print("GET result: {0}".format(result))
#    status = client.status()
#    print("client status: %s" % status)
except Exception as e:
    print("Error: %s" % e)

print(">>> etcd3interface test")

etcd = Etcd()
ttl = 30

print("===== PUTTING value for test =====")
etcd.put_client_path("/test", {"value": "foo", "ttl": ttl})

print("===== GETTING value of test =====")
result = etcd.get_client_path("/test")
print("result: {0}".format(result))

print("try to wait for lease to expire ({0} secs)".format(ttl))
time.sleep(ttl)
print("===== GETTING value of test =====")
result = etcd.get_client_path("/test")
print("result: {0}".format(result))