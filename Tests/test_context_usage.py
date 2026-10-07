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

    def test_claude_accepts_any_status_line_that_names_the_context(self):
        used = ['context 37%', 'Context: 37%', 'context window: 37%', '37% context used', 'context used: 37%',
                'ctx:37%', 'CTX 37%', 'Context 37% used']
        for text in used:
            with self.subTest(text):
                self.assertEqual(read_context(CLAUDE + f'Opus 5.5 · {text} · notch · 18:00 42%', 'claude'), 37)

    def test_claude_converts_what_is_left_into_what_is_used(self):
        left = ['63% context left', '63% of context remaining', 'context left: 63%', 'context left 63%',
                'ctx left 63%', 'ctx 63% left', 'Context 63% remaining', 'context window: 63% free']
        for text in left:
            with self.subTest(text):
                self.assertEqual(read_context(CLAUDE + f'Opus 5.5 · {text} · notch · 18:00 42%', 'claude'), 37)

    def test_a_number_without_the_word_context_is_never_taken_for_context(self):
        for text in ['Opus 5.5 · 63% left · notch', '5h 67% left', 'memory 40%', 'git:(context-fix) 40%',
                     'Context window 200k', 'context: unknown 40%', 'cached 40% · 18:00 42% · 13/10 13%']:
            with self.subTest(text):
                self.assertIsNone(read_context(CLAUDE + text, 'claude'))

    def test_text_outside_the_status_bar_and_invalid_values_are_ignored(self):
        self.assertIsNone(read_context('ctx:40%\n' + CLAUDE + 'notch · Opus 5.5', 'claude'))
        self.assertIsNone(read_context('notch · ctx:40%', 'claude'))
        self.assertIsNone(read_context(CLAUDE + 'notch · ctx:140%', 'claude'))
        self.assertIsNone(read_context('▄' * 40 + '\n→ Add a follow-up\n' + '▀' * 40 + '\nproject | ctx 4%', 'cursor'))


if __name__ == '__main__':
    unittest.main()
