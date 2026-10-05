from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'helper'))
from agent_detect import detect_provider


class ProviderDetectionTests(unittest.TestCase):
    def test_claude_code_installed_as_a_version_named_binary_is_detected(self):
        # Observado no iTerm2 3.7.3: jobName é a versão, commandLine/ps mostram `claude`.
        self.assertEqual(detect_provider('2.1.288', 'claude', 'claude', 'claude'), 'claude')
        self.assertEqual(detect_provider('2.1.288', 'claude --resume abc', 'claude', ''), 'claude')

    def test_claude_is_detected_from_its_install_path_when_the_title_was_rewritten(self):
        self.assertEqual(detect_provider('2.1.288', '', '', '/Users/me/.local/share/claude/versions/2.1.288'), 'claude')

    def test_cursor_agent_running_under_node_is_detected(self):
        command = '/Users/me/.local/bin/agent --use-system-ca /Users/me/.local/share/cursor-agent/versions/2026.09.10-fd3934a/index.js'
        self.assertEqual(detect_provider('node', command, 'agent', command), 'cursor')
        self.assertEqual(detect_provider('node', '', '', 'node /x/cursor-agent/versions/1/index.js'), 'cursor')
        self.assertEqual(detect_provider('cursor-agent', 'cursor-agent', 'cursor-agent', 'cursor-agent'), 'cursor')

    def test_codex_is_detected_with_flags_and_resume(self):
        self.assertEqual(detect_provider('codex', 'codex', 'codex', 'codex'), 'codex')
        self.assertEqual(detect_provider('codex', '', '', 'codex resume 0000'), 'codex')
        self.assertEqual(detect_provider('codex', '', '', '/opt/homebrew/bin/codex -m gpt-5 "hello"'), 'codex')

    def test_one_shot_invocations_do_not_become_sessions(self):
        for command in ('claude mcp list', 'claude -p "summarise"', 'claude --version', 'codex exec "x"',
                        'codex login', 'codex app-server --listen unix://', 'node /x/cursor-agent/versions/1/index.js status'):
            with self.subTest(command=command):
                self.assertIsNone(detect_provider('x', command, '', command))

    def test_other_programs_and_shells_are_ignored(self):
        for job, command in (('zsh', '-zsh'), ('vim', 'vim claude.md'), ('node', 'node server.js'),
                             ('ls', 'ls codex'), ('python3', 'python3 agent.py'), ('git', 'git log')):
            with self.subTest(command=command):
                self.assertIsNone(detect_provider(job, command, job, command))

    def test_title_is_a_fallback_only_for_non_shell_jobs(self):
        self.assertEqual(detect_provider('2.1.288', '', 'claude', ''), 'claude')
        self.assertIsNone(detect_provider('zsh', '', 'claude', ''))


if __name__ == '__main__':
    unittest.main()
