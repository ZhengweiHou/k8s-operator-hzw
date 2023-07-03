import os, re, subprocess, logging, subprocess32, time, threading, random, sys

logfile = "time"
if os.path.exists(logfile):
    os.remove(logfile)
logging.basicConfig(filename=logfile, format='%(asctime)s: %(message)s', level=logging.INFO)

def run_cmd(cmd, op):
    start = time.time()
    proc = subprocess32.Popen(cmd, shell=True)
    output = proc.communicate()[0]
    fin = time.time()

    t = fin - start

    if proc.returncode != 0:
        logging.info("failed operation %s time elapsed %s" % (op, str(t)))

    else:
        logging.info("operation successful, time elapsed on %s is %s" % (op, str(t)))

def start_daemon(func, key):
    worker = threading.Thread(target = func, args=(key,))
    worker.daemon = True
    worker.start()
    return worker

def get(key, stop=False):
    cmd = 'curl -k https://sl-us-dal-9-portal.1.dblayer.com:10479/v2/keys/service/test/%s -u root:YTZRWEKTDNGCPEPL' % key
    put(key, True)
    while True:
        run_cmd(cmd, 'get')
        time.sleep(random.randint(1,5))
        if stop:
            break

def put(key, stop=False):
    cmd = 'curl -k -L -XPUT https://sl-us-dal-9-portal.1.dblayer.com:10479/v2/keys/service/test/%s -d value=test -u root:YTZRWEKTDNGCPEPL' % key
    while True:
        run_cmd(cmd, 'put')
        time.sleep(random.randint(1,5))
        if stop:
            break

def delete():
    cmd = 'curl -k -L -X DELETE https://sl-us-dal-9-portal.1.dblayer.com:10479/v2/keys/service/test?recursive=true -u root:YTZRWEKTDNGCPEPL'
    run_cmd(cmd, 'delete')

def putget(key):
    while True:
        put(key, True)
        get(key, True)

def run():
    func = sys.argv[1]
    num = int(sys.argv[2])
    dict = {"get":get,"put":put,"putget":putget}

    delete()
    for i in range(0, num):
        key = str(random.getrandbits(32))
        start_daemon(dict[func], key)

    while True:
        time.sleep(10)
run()
