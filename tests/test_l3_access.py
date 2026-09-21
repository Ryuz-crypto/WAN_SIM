"""Exercise generated dashboard code without root or changes to host networking."""
import ast
import ipaddress
import json
import os
from pathlib import Path
import re
import shlex
import unittest
from unittest.mock import Mock, mock_open, patch


SOURCE = (Path(__file__).resolve().parents[1] / 'WANsim2.sh').read_text(encoding='utf-8')
DASHBOARD = SOURCE.split("cat > \"$WANSIM_DASHBOARD\" <<'EOF'\n", 1)[1].split('\nEOF\n', 1)[0]
TREE = ast.parse(DASHBOARD)


def load_functions():
    # Only function definitions are loaded: no Flask startup, workers or host commands.
    functions = [node for node in TREE.body if isinstance(node, ast.FunctionDef)]
    for node in functions:
        node.decorator_list = []
    namespace = dict(ipaddress=ipaddress, json=json, os=os, re=re, shlex=shlex)
    exec(compile(ast.Module(body=functions, type_ignores=[]), '<dashboard>', 'exec'), namespace)
    return namespace


def link(wan='wan1', lan='lan1', mode='access', base=10):
    return dict(wan=wan, lan=lan, lanMode=mode, baseOctet=base,
                vlans=2, startVlan=100, wanMode='dhcp')


def draft(*links):
    return dict(topology='nat', l3=dict(segment='10.254', links=list(links)))


class L3AccessTests(unittest.TestCase):
    def setUp(self):
        self.ns = load_functions()
        self.ns.update(
            list_interfaces=lambda: [dict(name=x) for x in ('wan1', 'lan1', 'wan2', 'lan2')],
            CONTROL_INTERFACES=[], INTERFACE_META={},
            TELEGRAM_TOKEN='', TELEGRAM_CHAT_ID='',
            TLS_CERT_FILE='', TLS_KEY_FILE='', TLS_ENABLE_FILE='',
            logger=Mock(), remove_netem_state=Mock(),
        )
        self.commands = []

        def step(actions, label, cmd, **kwargs):
            self.commands.append(cmd)
            actions.append(dict(ok=True, label=label, cmd=cmd))
            return True, ''

        self.ns.update(action_step=step, runtime_iface_ip=lambda _: '192.0.2.2',
                       runtime_iface_public_ip=lambda _: '192.0.2.2',
                       runtime_iface_bw=lambda _: 'N/D',
                       configure_runtime_dhcp=Mock(), configure_runtime_nat=Mock())

    def validate(self, data):
        return self.ns['validate_reactui_draft'](data)

    def runtime(self, data):
        with patch.object(os, 'listdir', return_value=[]), patch.object(os.path, 'exists', return_value=False):
            return self.ns['apply_runtime_nat'](data, [])

    def test_access_ignores_hidden_vlan_fields(self):
        item = link()
        item.update(vlans='unused', startVlan='unused')
        self.assertTrue(self.validate(draft(item))['ok'])
        value = self.ns['normalize_l3_link'](1, item, '10.254')
        self.assertEqual((value['lan_mode'], value['vlans'], value['start']), ('access', 1, 0))

    def test_mixed_modes_in_either_pair(self):
        for modes in [('access', 'vlan'), ('vlan', 'access'), ('access', 'access')]:
            with self.subTest(modes=modes):
                result = self.validate(draft(link(mode=modes[0]), link('wan2', 'lan2', modes[1], 20)))
                self.assertTrue(result['ok'], result)

    def test_legacy_drafts_remain_tagged(self):
        item = link(mode='vlan')
        del item['lanMode']
        result = self.runtime(draft(item))
        self.assertEqual(result['control'], ['v1_100', 'v1_101'])
        self.assertEqual(sum('type vlan id' in c for c in self.commands), 2)

    def test_access_uses_physical_lan_for_dhcp_nat_and_control(self):
        result = self.runtime(draft(link()))
        self.assertEqual(result['control'], ['lan1'])
        self.assertEqual(result['meta']['lan1']['subnet'], '10.254.10.0/24')
        self.assertIn('Acceso sin etiqueta', result['meta']['lan1']['label'])
        self.assertIn('sudo ip addr replace 10.254.10.1/24 dev lan1', self.commands)
        self.assertFalse(any('type vlan' in c or 'ip link del lan1' in c for c in self.commands))
        self.assertEqual(self.ns['configure_runtime_dhcp'].call_args.args[0], [('10.254', 10, 'lan1')])
        self.assertEqual(self.ns['configure_runtime_nat'].call_args.args[0], [('wan1', '10.254.10.0/24')])

    def test_mixed_runtime(self):
        result = self.runtime(draft(link(), link('wan2', 'lan2', 'vlan', 20)))
        self.assertEqual(result['control'], ['lan1', 'v2_100', 'v2_101'])
        self.assertEqual(len(self.ns['configure_runtime_dhcp'].call_args.args[0]), 3)

    def test_subnet_overlap_rejected_for_access(self):
        result = self.validate(draft(link(), link('wan2', 'lan2', 'vlan', 10)))
        self.assertFalse(result['ok'])
        self.assertTrue(any('octetos se solapa' in e for e in result['errors']))

    def test_duplicate_vlan_still_rejected(self):
        self.assertFalse(self.validate(draft(link(mode='vlan'), link('wan2', 'lan2', 'vlan', 20)))['ok'])

    def test_interface_reuse_rejected(self):
        self.assertFalse(self.validate(draft(link(), link('wan2', 'lan1', 'access', 20)))['ok'])

    def test_invalid_mode_and_subnet_rejected(self):
        for changes in [dict(lanMode='other'), dict(baseOctet=255), dict(baseOctet=0)]:
            item = link()
            item.update(changes)
            self.assertFalse(self.validate(draft(item))['ok'])

    def test_wan_overlap_rejected(self):
        item = link()
        item.update(wanMode='manual', wanIp='10.254.10.50', wanMask='24', wanGateway='10.254.10.254')
        self.assertFalse(self.validate(draft(item))['ok'])

    def test_access_cleanup_only_removes_managed_address(self):
        self.ns['CONTROL_INTERFACES'] = ['lan1']
        self.ns['INTERFACE_META'] = {'lan1': dict(role='L3/NAT', lan='lan1', subnet='10.254.10.0/24')}
        with patch.object(os, 'listdir', return_value=[]):
            self.ns['cleanup_runtime_topology']([])
        self.assertIn('sudo ip addr del 10.254.10.1/24 dev lan1', self.commands)
        self.assertFalse(any('ip link del' in c or 'addr flush' in c for c in self.commands))

    def test_access_to_tagged_removes_old_address(self):
        before = self.runtime(draft(link()))
        self.ns.update(CONTROL_INTERFACES=before['control'], INTERFACE_META=before['meta'])
        after = self.runtime(draft(link(mode='vlan')))
        self.assertEqual(after['control'], ['v1_100', 'v1_101'])
        self.assertIn('sudo ip addr del 10.254.10.1/24 dev lan1', self.commands)

    def test_tagged_to_access_removes_virtual_interfaces(self):
        before = self.runtime(draft(link(mode='vlan')))
        self.ns.update(CONTROL_INTERFACES=before['control'], INTERFACE_META=before['meta'])
        after = self.runtime(draft(link()))
        self.assertEqual(after['control'], ['lan1'])
        self.assertIn('sudo ip link del v1_100', self.commands)
        self.assertIn('sudo ip link del v1_101', self.commands)

    def test_round_trip_config_preserves_mixed_modes_and_counts(self):
        data = draft(link(), link('wan2', 'lan2', 'vlan', 20))
        runtime = self.runtime(data)
        self.ns['CONFIG_FILE'] = '/test/wansim.conf'
        with patch('builtins.open', mock_open(read_data='')) as writer:
            self.ns['write_runtime_config'](data, runtime)
            content = writer().write.call_args.args[0]
        with patch('builtins.open', mock_open(read_data=content)):
            restored = self.ns['default_prebeta_draft']()
        links = restored['l3']['links']
        self.assertEqual([x['lanMode'] for x in links], ['access', 'vlan'])
        self.assertEqual([int(x['vlans']) for x in links], [1, 2])
        self.assertTrue(self.validate(restored)['ok'])

    def test_legacy_csv_defaults_to_vlan(self):
        for csv in ['1:wan1:lan1:100:10:10.254', '1:wan1:lan1:100:10:10.254:dhcp::']:
            self.ns['read_config_file'] = lambda: dict(L3_LINKS_CSV=csv, NUM_VLANS='2')
            item = self.ns['default_prebeta_draft']()['l3']['links'][0]
            self.assertEqual(item['lanMode'], 'vlan')
            self.assertEqual(item['vlans'], '2')


if __name__ == '__main__':
    unittest.main()
