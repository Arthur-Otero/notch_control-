from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'helper'))
from context_usage import read_context

CLAUDE = '─' * 40 + '\n❯\n' + '─' * 40 + '\n'


class ContextUsageTests(unittest.TestCase):
    def test_claude_status_line_reports_the_context_share(self):
        self.assertEqual(read_context(CLAUDE + 'notch · Opus 5.5 · ctx:12% · 10:22 42% · 09/10 13%', 'claude'), 12)
        self.assertEqual(read_context(CLAUDE + 'notch · ctx 64.5% · 5h 2%', 'claude'), 64.5)

    def test_codex_footer_reports_used_or_left_context(self):
        self.assertEqual(read_context('› Ask Codex to do anything\nGPT-6 · Context 14% used · 5h 67% left', 'codex'), 14)
        self.assertEqual(read_context('› Ask Codex to do anything\n94% context left · ? for shortcuts', 'codex'), 6)

    def test_text_outside_the_status_bar_and_invalid_values_are_ignored(self):
        self.assertIsNone(read_context('ctx:40%\n' + CLAUDE + 'notch · Opus 5.5', 'claude'))
        self.assertIsNone(read_context('notch · ctx:40%', 'claude'))
        self.assertIsNone(read_context(CLAUDE + 'notch · ctx:140%', 'claude'))
        self.assertIsNone(read_context('▄' * 40 + '\n→ Add a follow-up\n' + '▀' * 40 + '\nproject | ctx 4%', 'cursor'))


if __name__ == '__main__':
    unittest.main()
