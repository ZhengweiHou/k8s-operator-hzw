"""Standard standalone utility functions"""
import os
import subprocess
import subprocess32

def run_cmd(cmd, retry=0, timeout=20, success_ret=(0,), use_shell=True):
    """Used to simply run a command"""
    proc = subprocess32.Popen(cmd, stdout=subprocess.PIPE, shell=use_shell)
    try:
        output = proc.communicate(timeout)[0]
        brc = proc.returncode
    except subprocess32.TimeoutExpired:
        output, brc = None, -1

    if not brc in success_ret and retry > 0:
        output, brc = run_cmd(cmd, retry - 1, timeout, success_ret)
    return output, brc

def is_defined_dr_node():
    """Returns true if we are running on the DR node"""
    if os.path.isfile("/tmp/dr.node.override_true"):
        return True
    elif os.path.isfile("/tmp/dr.node.override_false"):
        return False
    else:
        return os.path.isfile("/etc/dr.role")

def is_defined_ha_node():
    """Returns true if we are running on an HA node"""
    if os.path.isfile("/tmp/ha.node.override_true"):
        return True
    elif os.path.isfile("/tmp/ha.node.override_false"):
        return False
    else:
        return os.path.isfile("/etc/hadr.role")
