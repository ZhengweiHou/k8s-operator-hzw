import os, time, random, sys, subprocess
from helpers.utils import *

logfile = "/var/log/governor/crash_test.log"
if os.path.exists(logfile):
    os.remove(logfile)
logging.basicConfig(filename=logfile, format='%(asctime)s: %(message)s', level=logging.INFO)

def run(cmd):
    logging.info(cmd)
    proc = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE)
    out = proc.communicate()[0]
    logging.info(out)
    return out

def kill():
    out = run("db2nps 0 | grep db2sysc")
    if out:
        proc = out.split()[1]
        run("kill -9 %s" % proc)

if __name__ == "__main__":
    op = None if len(sys.argv) == 1 else sys.argv[1]

    while True:
        interval = random.randint(120, 900)
        time.sleep(interval)
        if not op:
            b = random.randint(0,1)
            if b:
                kill()
            else:
                run("db2stop force")
        elif op == "kill":
            kill()
        elif op == "stop":
            run("db2stop force")
