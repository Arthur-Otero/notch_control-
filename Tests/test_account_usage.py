import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'helper'))
from account_usage import read_usage, UsageTracker


class AccountUsageTests(unittest.TestCase):
    def test_codex_uses_account_remaining_not_context(self):
        result = read_usage('› Ask Codex to do anything\nGPT-6 · Context 14% used · 5h 67% left · weekly 68% left', 'codex')
        self.assertEqual([(x['id'], x['usedPercent']) for x in result], [('five_hour', 33), ('seven_day', 32)])

    def test_quota_quoted_in_conversation_is_not_account_usage(self):
        self.assertEqual(read_usage('5h 90% left\n› Ask Codex to do anything\nContext 14% used', 'codex'), [])

    def test_claude_and_cursor_have_distinct_windows(self):
        claude = read_usage('─' * 40 + '\n❯\n' + '─' * 40 + '\nSonnet · 92% left · 5h 2% · 7d 98%', 'claude')
        self.assertEqual([x['usedPercent'] for x in claude], [2, 98])
        cursor = read_usage('▄' * 40 + '\n→ Add a follow-up\n' + '▀' * 40 + '\nproject | 4% | cursor 31.8% | others 75.6% (resets 15m)', 'cursor')
        self.assertEqual([x['id'] for x in cursor], ['cursor', 'other_models'])
        self.assertEqual(cursor[1]['resetHint'], '15m')

    def test_missing_invalid_and_zero_are_distinct(self):
        self.assertEqual(read_usage('› Ask Codex to do anything\n5h 101% left', 'codex'), [])
        self.assertEqual(read_usage('› Ask Codex to do anything\n5h 100% left', 'codex')[0]['usedPercent'], 0)
        self.assertEqual(read_usage('random output 5h 20% left', 'codex'), [])

    def test_claude_statusline_can_label_windows_with_their_reset_time(self):
        result = read_usage('─' * 40 + '\n❯\n' + '─' * 40 + '\nSonnet · 92% left · 17:30 22% · 06/10 98%', 'claude')
        self.assertEqual([(x['id'], x['usedPercent'], x['resetHint']) for x in result],
                         [('five_hour', 22, '17:30'), ('seven_day', 98, '06/10')])

    def test_reading_repeats_after_inventory_race_without_changing_identity(self):
        tracker = UsageTracker()
        terminal = {'id': 'new', 'generation': 'first'}
        windows = [{'id': 'five_hour', 'usedPercent': 30, 'resetHint': None}]
        self.assertEqual(tracker.update(terminal, windows, 100), windows)
        self.assertIsNone(tracker.update(terminal, windows, 101))
        self.assertEqual(tracker.update(terminal, windows, 105), windows)

    def test_transient_dialog_expiry_generation_and_removal(self):
        tracker = UsageTracker()
        terminal = {'id': 'one', 'generation': 'first'}
        windows = [{'id': 'five_hour', 'usedPercent': 30, 'resetHint': None}]
        self.assertEqual(tracker.update(terminal, windows, 0), windows)
        self.assertIsNone(tracker.update(terminal, [], 2))
        self.assertEqual(tracker.update(terminal, [], 300), [])
        self.assertEqual(tracker.update(terminal, windows, 301), windows)
        self.assertEqual(tracker.update({**terminal, 'generation': 'second'}, [], 302), [])
        tracker.retain([])
        self.assertEqual(tracker.update(terminal, [], 303), [])
