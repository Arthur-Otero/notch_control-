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

    def test_claude_reads_a_lone_left_or_used_piece_of_the_status_line(self):
        pieces = {
            'Opus 5.5 · 63% left · notch_control · git:(feature/x) ✗ · 18:00 42% · 13/10 13%': 37,
            'Opus 5.5 · 63% remaining · notch': 37,
            'notch | (63% left) | Opus 5.5': 37,
            'notch │ 🧠 63% free │ 18:00 42%': 37,
            'notch   63% left   Opus 5.5': 37,
            'Opus 5.5 · 37% used · notch': 37,
            '63% left': 37,
        }
        for text, expected in pieces.items():
            with self.subTest(text):
                self.assertEqual(read_context(CLAUDE + text, 'claude'), expected)

    def test_a_lone_piece_is_not_context_when_it_could_be_something_else(self):
        for text in ['5h 67% left', 'weekly 30% left · 18:00 42%', 'session 63% left', 'battery 63% left',
                     'Opus 5.5 · 63% left · 40% left', '63% left · 37% used', '63% leftover', 'memory 40%',
                     'git:(context-fix) 40%', 'Context window 200k', 'context: unknown 40%', 'cached 40%',
                     'cached 40% · 18:00 42% · 13/10 13%', '40%']:
            with self.subTest(text):
                self.assertIsNone(read_context(CLAUDE + text, 'claude'))

    def test_the_lone_piece_rule_is_only_for_claude_code(self):
        self.assertIsNone(read_context('› Ask Codex to do anything\nGPT-6 · 63% left · 5h 67% left', 'codex'))
        self.assertIsNone(read_context('▄' * 40 + '\n→ Add a follow-up\n' + '▀' * 40 + '\nproject | 63% left', 'cursor'))

    def test_claude_and_codex_read_tokens_over_a_known_window(self):
        for text, expected in {'ctx 120k/200k': 60, 'Opus · 379k / 1M': 37.9, '123,456/200,000 tokens': 61.728,
                               'tokens 45.2k/200k (23%)': 22.6, 'ctx 0/200k': 0, '200k/200k': 100,
                               'notch · 258k/400k · 18:00 42%': 64.5}.items():
            with self.subTest(text):
                self.assertAlmostEqual(read_context(CLAUDE + text, 'claude'), expected, places=2)
        self.assertEqual(read_context('› Ask Codex to do anything\nGPT-6 · 100k/200k · 5h 67% left', 'codex'), 50)

    def test_tokens_that_are_not_a_context_window_are_ignored(self):
        for text in ['13/10 13%', '20k/50k', '12k/3k', '256M/512M', '10/13', '300k/200k', 'in 20k/out 50k',
                     'v1.2/200k.zip', '1/2/200k']:
            with self.subTest(text):
                self.assertIsNone(read_context(CLAUDE + text, 'claude'))

    def test_a_progress_bar_between_the_label_and_the_number_is_skipped(self):
        for text, expected in {'ctx ████░░░░ 40%': 40, 'context [▓▓▓░░] 40%': 40, 'ctx: ▰▰▱▱▱ 63% left': 37,
                               'context left ●●●○○ 63%': 37}.items():
            with self.subTest(text):
                self.assertEqual(read_context(CLAUDE + text, 'claude'), expected)

    def test_text_outside_the_status_bar_and_invalid_values_are_ignored(self):
        self.assertIsNone(read_context('ctx:40%\n' + CLAUDE + 'notch · Opus 5.5', 'claude'))
        self.assertIsNone(read_context('notch · ctx:40%', 'claude'))
        self.assertIsNone(read_context(CLAUDE + 'notch · ctx:140%', 'claude'))
        self.assertIsNone(read_context('▄' * 40 + '\n→ Add a follow-up\n' + '▀' * 40 + '\nproject | ctx 4%', 'cursor'))


if __name__ == '__main__':
    unittest.main()
