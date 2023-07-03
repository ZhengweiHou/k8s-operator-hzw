"""Class Driver for db2pd -hadr options"""
import logging
import datetime as dt
import re
import os
import pickle
import getpass
from util_funcs import run_cmd, is_defined_dr_node, is_defined_ha_node
import fasteners

PICKLE_CACHE_FILE = "/tmp/db2pd_pickle_file" + str(os.getuid())
PICKLE_LOCK_FILE = "/tmp/tmp_lock_file" + str(os.getuid())

SU_DB2INST1 = "sudo su - db2inst1 -c \""
DB2PD = "db2pd"


def is_tablespace_good(db_name, ignore_bad=True, db2pd_cmd_in=None):
    """Returns False if there are any bad tablespaces, True otherwise"""
    if ignore_bad:
        result = True
    else:
        result = False

    if not db2pd_cmd_in:
        if getpass.getuser() == "db2inst1":
            db2pd_cmd = DB2PD + " -db " + db_name + " -tablespaces"
        else:
            db2pd_cmd = SU_DB2INST1 + DB2PD + " -db " + db_name + " -tablespaces\""
    else:
        db2pd_cmd = db2pd_cmd_in


    output, db2pd_rc = run_cmd(db2pd_cmd, 0, 60)
    if db2pd_rc == 0:
        tables = output.splitlines()
        for i in range(0, len(tables) - 1):
            if tables[i] == "Tablespace Statistics:":
                i += 2
                result = True
                while tables[i] != "":
                    if int(tables[i].split()[9], 16) != 0:
                        return False
                    i += 1
    return result


class RawPickle(object):
    """An Object to Serialize the output of db2pd (or something else if needed)"""
    def __init__(self, date=dt.datetime(2000, 1, 1), raw_text="", db_name=""):
        """constructor"""
        self.db_name = db_name
        self.date = date
        self.raw_text = raw_text
    def get_raw_text(self):
        """Returns the raw text from the object"""
        return self.raw_text
    def is_old(self, age=15):
        """Used to determine if this object is old based on seconds passed in"""
        return  (dt.datetime.now() - self.date).total_seconds() > age


class Db2pdEntries(object):
    """Class that represents objects of all entries returned by db2pd for logic"""

    def __init__(self, logger=logging.getLogger(), db_name="bludb", db2pd_cmd=None, ignore_cache=False):
        """Initialize with the db_name"""
        self.db_name = db_name
        self.is_primary = False
        self.is_standby = False
        self.is_standard = False
        self.is_active = False
        if not db2pd_cmd:
            if getpass.getuser() == "db2inst1":
                self.db2pd_cmd = DB2PD + " -db " + db_name + " -hadr"
            else:
                self.db2pd_cmd = SU_DB2INST1 + DB2PD + " -db " + db_name + " -hadr\""
        else:
            self.db2pd_cmd = db2pd_cmd
        self.hadr_entries = []
        self.logger = logger
        self.ignore_cache = ignore_cache
        self.__hadr_init()

    def __hadr_init(self):
        """Call to initialize db2pd"""
        # The goal of this code is to reduce calls to db2pd as
        # opposed to eliminate concurrent calls to db2pd.
        # For this reason - we are going to do a race cache
        # which means that if the cache is not current we will not serialize
        # and instead will let the call through.  This will avoid a single indefinite hang
        # from causing all calls to hang.
        @fasteners.interprocess_locked(PICKLE_LOCK_FILE)
        def get_current_cache():
            """Gets the db2pd output from the latest cache"""
            try:
                # access is all serialized here for all db2pds
                with open(PICKLE_CACHE_FILE, "r+b") as cache_file:
                    raw_obj = pickle.load(cache_file)
                    cache_file.close()
            except Exception:
                raw_obj = RawPickle()
            return raw_obj

        @fasteners.interprocess_locked(PICKLE_CACHE_FILE)
        def update_cache(raw_obj):
            """Updates the cache of db2pd -hadr output"""
            # Pickle the 'data' dictionary using the highest protocol available.
            with open(PICKLE_CACHE_FILE, "wb") as cache_file:
                pickle.dump(raw_obj, cache_file, pickle.HIGHEST_PROTOCOL)
                cache_file.close()


        output_raw_pickle = get_current_cache()

        #Old is greater then 15 seconds
        if output_raw_pickle.is_old(15) or self.ignore_cache:
            self.logger.info("Calling db2pd")
            raw_output = run_cmd(self.db2pd_cmd, False, 60)[0]
            self.logger.info("db2pd returned")
            output_raw_pickle = RawPickle(dt.datetime.now(), raw_output, self.db_name)
            update_cache(output_raw_pickle)
        else:
            self.logger.info("Cached Version")
            raw_output = output_raw_pickle.get_raw_text()

        self.logger.info(raw_output)
        self.__build_entries(raw_output)

    def __build_entries(self, raw_output):
        """this function parses the raw output of db2pd and makes it useable for logic"""
        # Split into sections based on new lines
        sections = re.split(r'\n{2,}', raw_output)

        # Discard any sections that don't contain an HADR Role
        for section in sections:
            if "HADR_ROLE" not in section:
                # Ignore any sections that don't have HADR_ROLE in them.
                if "Database Member 0" not in section:
                    # If we think we are in primary but we run into a section whereby 
                    # HADR is not active, we are going to assume that we are standard
                    if len(sections) == 2 and self.is_primary and "HADR is not active" in section:
                        self.is_standard = True
                        self.is_primary = False
                    continue
                else:
                    if "Standby" in section:
                        self.is_standby = True
                    else :
                        self.is_primary = True
                    self.is_active = "-- Active" in section
            else:
                self.hadr_entries.append(Db2pdEntry(section))

    def __len__(self):
        return len(self.hadr_entries)

    # Methods used externally
    def is_current_up(self):
        """Returns true if current node is good"""

        if self.is_standard and self.is_active:
            return True
        if self.is_primary and self.is_primary_good():
            return True
        elif self.is_standby and self.is_standby_good():
            return True
        elif is_defined_dr_node() and self.is_any_dr_node_good():
            return True
        else:
            return False

    def is_all_known_up(self):
        """Returns true if current node is good"""

        if self.is_standard and self.is_active and not is_defined_ha_node():
            ret = True
        else:
            ret = False

        for entry in self.hadr_entries:
            ret = True
            if entry.is_primary_entry and entry.is_primary_entry_good():
                continue
            elif entry.is_standby_entry and entry.is_standby_entry_good():
                continue
            elif entry.is_dr_entry() and entry.is_dr_entry_good():
                continue
            else:
                return False
        return ret

    def is_dr_standby_node(self):
        """Is this the DR Node in the cluster that is running as a standby"""
        return self.is_standby and is_defined_dr_node()

    def is_any_dr_node_good(self):
        """Returns true if any DR nodes are good"""
        for entry in self.hadr_entries:
            if entry.is_dr_entry() and entry.is_dr_entry_good():
                return True
        return False

    def is_any_dr_standby_node_good(self):
        """Returns true if any DR nodes are good"""
        for entry in self.hadr_entries:
            if entry.is_dr_entry_good() or entry.is_standby_entry_good():
                return True
        return False

    def is_all_dr_nodes_good(self):
        """Determines if all DR nodes are in a good and expected state."""
        ret = False
        for entry in self.hadr_entries:
            if entry.is_dr_entry():
                ret = True
                if not entry.is_dr_entry_good():
                    return False
        return ret

    def get_dr_node(self):
        """Helper function that returns the db2pdEntry of the dr Node"""
        # We can get the dr node if the current role is primary whereby
        # the first superasync will be the dr node - otherwise the first node
        # if we are dr_node
        if self.is_primary or is_defined_dr_node():
            for entry in self.hadr_entries:
                if entry.is_dr_entry():
                    return entry
        return None

    def get_log_gap(self):
        """Get the log gap for the first super async node if it exist - otherwise current"""
        for entry in self.hadr_entries:
            if entry.get("HADR_SYNCMODE") == "SUPERASYNC":
                return entry.get("HADR_LOG_GAP(bytes)")
        return self.get_current_node_metric("HADR_LOG_GAP(bytes)")

    def get_standby_node(self):
        """Helper function that returns the db2pdEntry of the Standby Node"""
        for entry in self.hadr_entries:
            if entry.get("HADR_ROLE") == "STANDBY" and \
               (entry.get("HADR_SYNCMODE") == "SYNC" or len(self.hadr_entries)):
                return entry
        return None

    def is_standby_good(self):
        """Determines if the DR node in a good and expected state"""
        entry = self.get_standby_node()
        if entry != None:
            return entry.is_standby_entry_good()
        return False

    def get_primary_node(self):
        """Helper function that returns the db2pdEntry of the Primary Node"""
        for entry in self.hadr_entries:
            if entry.get("HADR_ROLE") == "PRIMARY":
                return entry
        return None

    def is_primary_good(self):
        """Determines if the DR node in a good and expected state"""
        dr_entry = self.get_primary_node()
        if dr_entry != None:
            return dr_entry.is_primary_entry_good()
        return False

    def is_standard_good(self):
        """Determines if we are on a standard node and if it is active"""
        if self.is_standard:
            if self.is_active:
                return True
        return False

    def get_current_node(self):
        """Helper function that returns the db2pdEntry of the Standby Node"""
        if self.is_primary:
            return self.get_primary_node()
        elif is_defined_dr_node():
            return self.get_dr_node()
        elif self.is_standby:
            return self.get_standby_node()
        else:
            return None

    def get_current_node_metric(self, metric):
        """Returns any metric from the current node"""
        entry = self.get_current_node()
        if entry:
            return entry.get(metric)
        else:
            return ""

    def get_dr_metric(self, metric):
        """Returns any metric from a node with superasync configured"""
        for entry in self.hadr_entries:
            if entry.get("HADR_SYNCMODE") == "SUPERASYNC":
                return entry.get(metric)
        return ""



class Db2pdEntry(object):
    """Represents a single output set from db2pd -hadr"""

    def __init__(self, raw_text):
        """Constructor"""
        self.pd_entry = {}
        self.parse_raw(raw_text)

    def parse_raw(self, raw_text):
        """Parses the db2pd entry that is passed in"""
        for line in raw_text.splitlines():
            line = line.strip()
            key_value = line.strip().split(' = ')
            if len(key_value) == 1:
                self.pd_entry[key_value[0]] = ""
            else:
                self.pd_entry[key_value[0]] = key_value[1]

    def is_primary_entry(self):
        """Determines if this entry represents a primary node """
        # We only need to check the first entry because role can't be different
        return len(self.pd_entry) > 0 and self.pd_entry.get("HADR_ROLE") == "PRIMARY"

    def is_primary_entry_good(self):
        """Determines if the Primary node in a good and expected state"""
        return self.is_primary_entry() and self.is_peer_entry()

    def is_standby_entry_good(self):
        """Determines if the DR node in a good and expected state"""
        if self.is_standby_entry():
            if self.pd_entry.get('HADR_SYNCMODE') == "SUPERASYNC":
                if self.is_connected_entry():
                    if self.get("HADR_STATE") == "REMOTE_CATCHUP":
                        return True
            elif self.is_peer_entry():
                return True
        return False

    def is_standby_entry(self):
        """Determines if this entry represents a standby node"""
        # We only need to check the first entry because role can't be different
        return len(self.pd_entry) > 0 and self.pd_entry.get('HADR_ROLE') == "STANDBY"

    def is_dr_entry(self):
        """Determines if this entry represents a/the DR Node node"""
        if len(self.pd_entry) > 0 and is_defined_dr_node() or self.pd_entry.get('HADR_ROLE') == "PRIMARY":
            # All nodes on the DR node are DR nodes until we add HA support right now.
            # However when we add HA - one of them will be the principle standby so that is why
            # we check for SUPERASYNC
            if self.pd_entry.get('HADR_SYNCMODE') == "SUPERASYNC":
                return True
        return False

    def is_dr_entry_good(self):
        """Determines if the DR node in a good and expected state"""
        if self.is_dr_entry():
            if self.get("HADR_STATE") == "REMOTE_CATCHUP":
                if self.get("HADR_CONNECT_STATUS") == "CONNECTED":
                    return True
        return False

    def is_standard_entry(self):
        """Determines if database is in standard role"""
        return len(self.pd_entry) > 0 and self.pd_entry.get("HADR_ROLE") == "STANDARD"

    def is_connected_entry(self):
        """Determines if HADR is connected"""
        return len(self.pd_entry) > 0 and self.pd_entry.get("HADR_CONNECT_STATUS") == "CONNECTED"

    def is_disconnected_peer_entry(self):
        """Determines if HADR is disconnected peer"""
        return len(self.pd_entry) > 0 and self.pd_entry.get("HADR_CONNECT_STATUS") == "DISCONNECTED"

    def is_peer_entry(self):
        """Determines if HADR is in peer state"""
        return len(self.pd_entry) > 0 and self.pd_entry.get("HADR_STATE") == "PEER"

    def get_hadr_state(self):
        """Returns the HADR state"""
        return self.pd_entry.get("HADR_STATE")

    def get(self, key):
        """Helper function to return a key for this entry - eg. HADR_STATE"""
        return self.pd_entry.get(key)
