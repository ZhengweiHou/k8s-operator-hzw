import unittest, logging, time
from mock import Mock, patch
from nose_parameterized import parameterized
from enum import IntEnum

from helpers.truth_manager import TruthManager
from helpers.db2 import Db2
from helpers.ha import Ha
from config import Config

logging.disable(logging.CRITICAL)

class Action:
    no_action = 0
    promote = 1
    demote = 1 << 1
    start_as_primary = 1 << 2
    start_as_standby = 1 << 3
    update_leader = 1 << 4

def doc(func, num, param):
    arg_map = param[0][0]
    action = param[0][1]

    return "%s: %s with %s, expected action %s" %(num, func.__name__, str(arg_map), action)

class TestHa(unittest.TestCase):

    def setUp(self):
        Config.__getitem__ = Mock(return_value = None)
        Config.is_prod = Mock(return_value = False)
        Config.is_stage = Mock(return_value = False)

    # test all instances assuming disk is not full and db2 is running and leader is locked
    @parameterized.expand([
        ({'has_lock':True, 'is_primary':True}, Action.update_leader),
        ({'has_lock':True, 'is_primary':False}, Action.promote + Action.update_leader),
        ({'has_lock':False, 'is_primary':True}, Action.demote),
        ({'has_lock':False, 'is_primary':False}, Action.no_action)
    ])
    def test_leader_locked(self, arg_map, action):
        arg_map['is_read_only'] = False
        arg_map['is_up'] = True
        arg_map['is_unlocked'] = False
        arg_map['can_connect'] = True
        self.driver(arg_map, action)

    # test all instances assuming disk is not read only and db can be connected and db2 is running and leader is unlocked
    @parameterized.expand([
        ({'can_i_accquire_lock':True, 'is_primary':True}, Action.no_action),
        ({'can_i_aquire_lock':True, 'is_primary':False}, Action.promote),
        ({'acquire_lock':False, 'is_primary':True}, Action.demote),
        ({'acquire_lock':False, 'is_primary':False}, Action.no_action),
    ])
    def test_is_unlocked(self, arg_map, action):
        arg_map['is_read_only'] = False
        arg_map['is_up'] = True
        arg_map['is_unlocked'] = True
        arg_map['can_connect'] = True
        self.driver(arg_map, action)

    # test all instances assuming connection is down
    @parameterized.expand([
        ({'is_primary':True, 'ping':True, 'can_connect':False}, Action.start_as_primary),
        ({'is_primary':True, 'ping':True, 'can_connect':True}, Action.no_action),
        ({'is_primary':True, 'ping':False, 'can_connect':True}, Action.start_as_primary),
    ])
    def test_connection_down(self, arg_map, action):
        arg_map['is_read_only'] = False
        arg_map['is_up'] = True
        arg_map['only_member'] = False
        self.driver(arg_map, action)

    # test all instances assuming disk is not read only and db2 is not running
    @parameterized.expand([
        ({'has_lock':True}, Action.start_as_primary),
        ({'has_lock':False}, Action.start_as_standby),
    ])
    def test_db2_not_running(self, arg_map, action):
        arg_map['is_read_only'] = False
        arg_map['is_up'] = False
        self.driver(arg_map, action)

    def driver(self, arg_map, action):
        mock_db2 = self.setup_db2(arg_map)
        ha = self.setup_ha(mock_db2, arg_map)

        ha.run_cycle()
        self.verify_action(ha, mock_db2, action)

    def verify_action(self, ha, mock_db2, action):
        if action & Action.promote:
            self.assertTrue(mock_db2.promote.called)
        if action & Action.demote:
            self.assertTrue(mock_db2.demote.called)
        if action & Action.start_as_standby:
            self.assertTrue(mock_db2.start_as_standby.called)
        if action & Action.start_as_primary:
            self.assertTrue(mock_db2.start_as_primary.called)
        if action & Action.update_leader:
            self.assertTrue(ha.update_lock.called)

        if not action & Action.promote:
            self.assertFalse(mock_db2.promote.called)
        if not action & Action.demote:
            self.assertFalse(mock_db2.demote.called)
        if not action & Action.start_as_standby:
            self.assertFalse(mock_db2.start_as_standby.called)
        if not action & Action.start_as_primary:
            self.assertFalse(mock_db2.start_as_primary.called)
        if not action & Action.update_leader:
            self.assertFalse(ha.update_lock.called)

    def setup_db2(self, arg_map):
        mock_db2 = Mock(Db2)
        mock_db2.ip = None
        for key in arg_map:
            setattr(mock_db2, key, Mock(return_value = arg_map[key]))

        mock_db2.is_standby = Mock(return_value = not mock_db2.is_primary)
        mock_db2.can_connect = arg_map.get('can_connect')
        mock_db2.init_time = int(time.time())
        mock_db2.last_peer_time = -1
        return mock_db2

    def setup_ha(self, mock_db2, arg_map):
        ha = Ha(mock_db2, Mock())
        ha.update_lock = Mock()
        ha.discard_lock = Mock()
        for key in arg_map:
            setattr(ha, key, Mock(return_value = arg_map[key]))

        return ha
