import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'helper' / (name + '.py'))
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


class ConfigurationAndEventsTests(unittest.TestCase):
    def testInstallationIsIdempotentRemovalPreservesThirdPartyAndConcurrentChangeRefusesWrite(self):
        config = module('hook_configuration')
        existing = {'permissions': {'allow': ['safe']}, 'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'third-party'}]}]}}
        with tempfile.TemporaryDirectory(dir=ROOT / '.build') as folder:
            path = Path(folder) / 'settings.json'
            path.write_text(json.dumps(existing))
            addition = config.fragment('claude', '/Python With Space/python3', '/app/hook.py', '/app/events')
            installed = config.update(path, addition, path.read_bytes())
            repeated = config.update(path, addition, path.read_bytes())
            self.assertEqual(repeated, installed)
            mixed = json.loads(path.read_text())
            mixed['hooks']['Stop'][-1]['hooks'].append({'type': 'command', 'command': 'added-later'})
            path.write_text(json.dumps(mixed))
            with_extra = config.update(path, addition, path.read_bytes(), remove=True)
            self.assertEqual(with_extra['hooks']['Stop'][-1]['hooks'][0]['command'], 'added-later')
            path.write_text(json.dumps(installed))
            restored = config.update(path, addition, path.read_bytes(), remove=True)
            self.assertEqual(restored, existing)
            expected = path.read_bytes()
            path.write_text(json.dumps({'changed': True}))
            with self.assertRaisesRegex(ValueError, 'configuration_changed'):
                config.update(path, addition, expected)
            self.assertEqual(json.loads(path.read_text()), {'changed': True})

    def testDaemonWithoutMatchingPidCannotUpdateEitherTerminalAndSubagentsAreIgnored(self):
        events = module('session_events')
        rows = [{'provider': 'codex', 'pid': '101', 'tty': '/dev/ttys001', 'processStart': 'one', 'local': True, 'identityConfirmed': True},
                {'provider': 'codex', 'pid': '102', 'tty': '/dev/ttys002', 'processStart': 'two', 'local': True, 'identityConfirmed': True}]
        record = {'version': 1, 'provider': 'codex', 'event': 'PermissionRequest', 'ancestors': [{'pid': 999, 'tty': '?', 'process': 'codex', 'processStart': 'shared'}]}
        self.assertIsNone(events.associate(record, rows))
        record['ancestors'] = [{'pid': 102, 'tty': 'ttys002', 'process': 'codex', 'processStart': 'two'}]
        self.assertIs(events.associate(record, rows), rows[1])
        record['ancestors'][0]['processStart'] = 'old-process'
        self.assertIsNone(events.associate(record, rows))
        record['ancestors'][0]['processStart'] = 'two'
        record['agent'] = 'subagent'
        self.assertIsNone(events.associate(record, rows))
        self.assertIsNone(events.transition({'event': 'Notification', 'notification': 'idle_prompt'}))
        self.assertEqual(events.transition({'event': 'PermissionRequest'}), ('waiting', 'approval'))

    def testClaudeCodeBinaryNamedByVersionAndSingleDigitDaysStillAssociate(self):
        # `ps` preenche o dia com espaço ("dom  4 out") e o binário do Claude Code se chama como a versão.
        events = module('session_events')
        rows = [{'provider': 'claude', 'pid': '31324', 'tty': '/dev/ttys003', 'processStart': 'dom  4 out 00:14:18 2026',
                 'local': True, 'identityConfirmed': True}]
        record = {'version': 1, 'provider': 'claude', 'event': 'UserPromptSubmit',
                  'ancestors': [{'pid': 31324, 'tty': 'ttys003', 'process': '2.1.288', 'processStart': 'dom 4 out 00:14:18 2026'}]}
        self.assertIs(events.associate(record, rows), rows[0])
