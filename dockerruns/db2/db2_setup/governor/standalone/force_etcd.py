#!/usr/bin/env python

import sys, os, yaml, time, urllib2, logging, argparse
#import socket, fcntl, struct

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

# def get_ip_address(ifname):
#     s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
#     return socket.inet_ntoa(fcntl.ioctl(
#         s.fileno(),
#         0x8915,  # SIOCGIFADDR
#         struct.pack('256s', ifname[:15])
#     )[20:24])

def get_ip_address():
    ip, rc = run_cmd("su - db2inst1 -c \"db2 get db cfg for bludb | grep 'HADR_LOCAL_HOST' | awk -F= '{print \$2}' | sed -e 's/ //g'\"", retry=3)
    if rc != 0 or ip is None:
        logging.error("Failed to get ip address")
        return None
    return ip.strip()
    

def check_truth(truth):
    if truth.verify_endpoint(False):
        logging.info("verify endpoint success")
    else:
        logging.info("verify endpoint fail")
        sys.exit(1)

if __name__ == "__main__":
    truth = TruthManager()

    parser = argparse.ArgumentParser(description='argument parser')
    parser.add_argument('-v', '--value', dest="leader_value", default="", help="replace leader key with this value")
    args = parser.parse_args()

    my_ip = ""
    if args.leader_value:
        my_ip = args.leader_value
    else:
        my_ip = get_ip_address() # get_ip_address("eth0")
    if not my_ip:
            my_ip = "dummy"

    if check_truth(truth):
        logging.info("Using force_etcd ip: {0}".format(my_ip))
        truth.put_client_path("/leader", {"value": my_ip}) # non-expiring value
        truth.put_client_path("/prev", {"value": int(time.time())}) # use when timestamp file is implemented
    else:
        logging.info("Failed check_truth(), will not force TruthManager to {0}".format(my_ip))
