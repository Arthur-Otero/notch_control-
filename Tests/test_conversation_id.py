import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'helper'))
from conversation_id import from_claude_registry, from_command_line

CONVERSATION = '9dcbbad8-1ddc-4214-9724-ad33ca28c3b3'
START = 'Tue Oct  6 09:17:38 2026'


class ClaudeRegistryTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)

    def write(self, name, record):
        path = Path(self.folder.name) / name
        path.write_text(json.dumps(record) if isinstance(record, dict) else record)
        return path

    def test_session_of_the_same_process_is_returned(self):
        self.write('1378.json', {'pid': 1378, 'sessionId': CONVERSATION.upper(), 'procStart': START, 'status': 'idle'})
        # `ps` pads its output, so spaces are normalized before comparing.
        self.assertEqual(from_claude_registry('1378', 'Tue Oct 6 09:17:38 2026    ', self.folder.name), CONVERSATION)

    def test_record_left_by_another_process_with_the_same_pid_is_ignored(self):
        self.write('1378.json', {'pid': 1378, 'sessionId': CONVERSATION, 'procStart': START})
        self.assertIsNone(from_claude_registry(1378, 'Tue Oct  6 10:00:00 2026', self.folder.name))
        self.assertIsNone(from_claude_registry(1378, None, self.folder.name))

    def test_malformed_foreign_or_oversized_records_are_ignored(self):
        self.write('1.json', '{not json')
        self.write('2.json', {'pid': 3, 'sessionId': CONVERSATION, 'procStart': START})
        self.write('4.json', {'pid': 4, 'sessionId': 'not-a-uuid', 'procStart': START})
        self.write('5.json', json.dumps({'pid': 5, 'sessionId': CONVERSATION, 'procStart': START, 'pad': 'x' * 70000}))
        target = self.write('target.json', {'pid': 6, 'sessionId': CONVERSATION, 'procStart': START})
        os.symlink(target, Path(self.folder.name) / '6.json')
        for pid in (1, 2, 4, 5, 6, 7, 0, 'abc'):
            self.assertIsNone(from_claude_registry(pid, START, self.folder.name), pid)


class CommandLineTests(unittest.TestCase):
    def test_resume_arguments_of_each_provider(self):
        self.assertEqual(from_command_line('claude', 'claude -r ' + CONVERSATION), CONVERSATION)
        self.assertEqual(from_command_line('claude', 'claude --model opus --resume ' + CONVERSATION.upper()), CONVERSATION)
        self.assertEqual(from_command_line('claude', 'claude --resume=' + CONVERSATION), CONVERSATION)
        self.assertEqual(from_command_line('claude', 'claude --session-id ' + CONVERSATION), CONVERSATION)
        self.assertEqual(from_command_line('codex', '/opt/homebrew/bin/codex resume ' + CONVERSATION), CONVERSATION)
        self.assertEqual(from_command_line('cursor', 'agent --resume=' + CONVERSATION), CONVERSATION)

    def test_commands_without_a_resumed_id_have_no_conversation(self):
        self.assertIsNone(from_command_line('claude', 'claude'))
        self.assertIsNone(from_command_line('claude', 'claude -r'))
        self.assertIsNone(from_command_line('claude', 'claude --resume'))
        self.assertIsNone(from_command_line('codex', 'codex resume --last'))
        self.assertIsNone(from_command_line('codex', 'codex -r ' + CONVERSATION))
        self.assertIsNone(from_command_line('cursor', 'agent'))
        self.assertIsNone(from_command_line('claude', ''))


if __name__ == '__main__':
    unittest.main()
