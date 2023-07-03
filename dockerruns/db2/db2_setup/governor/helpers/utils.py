import os, re, subprocess, logging, subprocess32, time, threading, signal

logger = logging.getLogger(__name__)

def run_cmd(cmd, log = True, retry = 0, timeout = 20, success_ret = (0,), use_shell=True):
    proc = subprocess32.Popen(cmd, stdout=subprocess.PIPE, shell=use_shell, preexec_fn=os.setsid)
    if log:
        logging.info("child(%d) executing %s" % (proc.pid, cmd))
    try:
        output, err = proc.communicate(timeout = timeout)
        rc = proc.returncode
        if not rc in success_ret:
            logging.info(output)
            if err:
                logging.info(err)

    except subprocess32.TimeoutExpired:
        logging.info("child(%d) pgid(%d) timeout on command %s" % (proc.pid, os.getpgid(proc.pid), cmd))
        os.killpg(os.getpgid(proc.pid), signal.SIGINT) # send signal to the process group
        output, rc = None, -1

    if not rc in success_ret and retry > 0:
        output, rc = run_cmd(cmd, log, retry - 1, timeout, success_ret, use_shell)
    return output, rc

def str_cmp(st1, st2):
    if st1 and st2 and st1.lower() == st2.lower():
        return True
    return False

def start_daemon(func):
    worker = threading.Thread(target = func)
    worker.daemon = True
    worker.start()
    return worker

class CriticalDBError(Exception):
    def __init__(self, value):
        self.value = value

    def __str__(self):
        return repr(self.value)
