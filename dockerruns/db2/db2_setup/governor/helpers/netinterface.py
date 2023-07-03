import os, re, subprocess, logging
from helpers.utils import *
from config import config

class NetInterface:

    def __init__(self):
        self.public_interface = config["public_interface"]
        self.logger = logging.getLogger(__name__)
        self.logger.setLevel(logging.INFO)
        if config.is_prod() or config.is_stage():
            fh = logging.FileHandler("/var/log/governor/webserver.log")
            fh.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(process)d-%(thread)d: %(message)s'))

    def enable_public_interface(self):
        if config.is_prod():
            if not self.has_ip():
                cmd = "sudo ifup %s" % self.public_interface
                output, rc = run_cmd(cmd)
                if rc == 0:
                    self.logger.info("Enabled floating IP")
                else:
                    self.logger.info("Enable floating IP failed")
                    return False
        return True

    def disable_public_interface(self):
        if config.is_prod():
            if self.has_ip():
                cmd = "sudo ifconfig %s down" % self.public_interface
                output, rc = run_cmd(cmd)
                if rc == 0:
                    self.logger.info("Disabled floating IP")
                else:
                    self.logger.info("Disable floating IP failed")
                    return False
        return True

    def has_ip(self):
        cmd = "ip addr show %s | grep %s" % (self.public_interface, self.public_interface)
        output = run_cmd(cmd, False)[0] # should be None if down (ie. no ip)
        if output:
            return True
        return False
