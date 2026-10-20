import asyncio
from io import BytesIO
import json
from pathlib import Path
import struct
import sys
import tempfile
import time
import unittest
from unittest.mock import AsyncMock, patch
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'helper'))
from codex_usage import (CodexUsage, MAX_BODY, NoRedirect, USAGE_URL, UsageError,
                         fetch_usage, parse_process_environment, parse_usage, read_credentials)


def row(generation='first', terminal='one'):
    return {'identity': {'id': terminal, 'generation': generation}, 'pid': '42',
            'processStart': 'Tue Oct 20 08:00:00 2026', 'provider': 'codex',
            'local': True, 'identityConfirmed': True}


def payload(percent=33, duration=18000, **extra):
    return {'rate_limit': {'primary_window': {'used_percent': percent,
            'limit_window_seconds': duration, **extra}}}


class CodexUsageParserTests(unittest.TestCase):
    def test_windows_follow_duration_even_when_swapped_and_numeric_strings_are_supported(self):
        data = payload('68.5', '604800', reset_at=2000)
        data['rate_limit']['secondary_window'] = {'used_percent': 0, 'limit_window_seconds': 18000}
        result = parse_usage(data, now=1000)
        self.assertEqual([(window['id'], window['usedPercent']) for window, _ in result],
                         [('five_hour', 0), ('seven_day', 68.5)])
        self.assertEqual(result[1][1], 2000)
        self.assertIsNotNone(result[1][0]['resetHint'])

    def test_reset_offset_and_rollover_do_not_invent_new_quota(self):
        self.assertEqual(parse_usage(payload(reset_after_seconds=60), now=1000)[0][1], 1060)
        self.assertEqual(parse_usage(payload(reset_at=1000), now=1000), [])
        self.assertIsNone(parse_usage(payload(), now=1000)[0][1])
        self.assertEqual(parse_usage(payload(duration=900), now=1000), [])

    def test_invalid_percentages_schema_and_duplicate_windows_fail_closed(self):
        for value in (-1, 101, True, None, 'nan', 'inf', 'not a number'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                parse_usage(payload(value))
        for value in (None, [], {}, {'rate_limit': []}, {'rate_limit': {'primary_window': 'wrong'}}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                parse_usage(value)
        data = payload()
        data['rate_limit']['secondary_window'] = dict(data['rate_limit']['primary_window'])
        with self.assertRaises(ValueError):
            parse_usage(data)

    def test_process_environment_skips_argv_and_keeps_only_home_locations(self):
        data = struct.pack('=i', 3) + (b'/bin/codex\0\0\0codex\0--message\0HOME=/wrong\0'
                                     b'HOME=/Users/example\0CODEX_HOME=/Users/example/work login\0SECRET=private\0\0')
        self.assertEqual(parse_process_environment(data),
                         {'HOME': '/Users/example', 'CODEX_HOME': '/Users/example/work login'})
        with self.assertRaises(ValueError):
            parse_process_environment(data + b'CODEX_HOME=/other\0')


class CodexCredentialsTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.home = Path(directory.name)
        self.auth = self.home / 'auth.json'
        self.auth.write_text(json.dumps({'auth_mode': 'chatgpt', 'tokens': {
            'access_token': 'private-token', 'account_id': 'account', 'refresh_token': 'never-use'}}))
        self.before = self.auth.read_bytes(), self.auth.stat().st_mtime_ns
        self.start = patch('codex_usage.process_start', return_value=row()['processStart']).start()
        self.environment = patch('codex_usage.process_environment', return_value={'CODEX_HOME': str(self.home)}).start()
        self.addCleanup(patch.stopall)

    def test_read_only_credentials_use_the_process_home_and_require_no_refresh_token(self):
        result = read_credentials(row())
        self.assertEqual(result[1:], ('private-token', 'account'))
        self.assertEqual((self.auth.read_bytes(), self.auth.stat().st_mtime_ns), self.before)
        self.auth.write_text(json.dumps({'tokens': {'access_token': 'token', 'account_id': 'account'}}))
        self.assertIsNotNone(read_credentials(row()))

    def test_unproven_remote_changed_and_missing_processes_never_use_helper_login(self):
        for override in ({'local': False}, {'identityConfirmed': False}, {'provider': 'claude'},
                         {'processStart': None}, {'pid': 'wrong'}):
            self.assertIsNone(read_credentials({**row(), **override}))
        self.start.side_effect = [row()['processStart'], 'different process']
        self.assertIsNone(read_credentials(row()))
        self.environment.side_effect = OSError('denied')
        self.start.side_effect = None
        self.assertIsNone(read_credentials(row()))

    def test_default_home_is_the_process_home_and_relative_homes_are_refused(self):
        self.environment.return_value = {'HOME': str(self.home)}
        (self.home / '.codex').mkdir()
        self.auth.rename(self.home / '.codex/auth.json')
        self.assertIsNotNone(read_credentials(row()))
        self.environment.return_value = {'CODEX_HOME': 'relative', 'HOME': str(self.home)}
        self.assertIsNone(read_credentials(row()))

    def test_api_key_missing_account_corrupt_and_oversized_credentials_are_unavailable(self):
        for value in ({'auth_mode': 'apikey', 'tokens': {'access_token': 'secret', 'account_id': 'a'}},
                      {'tokens': {'access_token': 'secret'}}, {'tokens': {'access_token': 'secret\nheader', 'account_id': 'a'}}, []):
            self.auth.write_text(json.dumps(value))
            self.assertIsNone(read_credentials(row()))
        for value in ('not-json', 'x' * (MAX_BODY + 1)):
            self.auth.write_text(value)
            self.assertIsNone(read_credentials(row()))

    def test_keychain_configuration_never_reuses_an_old_auth_file(self):
        config = self.home / 'config.toml'
        for store in ('keyring', 'auto', 'ephemeral'):
            config.write_text('cli_auth_credentials_store = "' + store + '"\n')
            self.assertIsNone(read_credentials(row()))
        config.write_text('cli_auth_credentials_store = "file"\n')
        self.assertIsNotNone(read_credentials(row()))


class CodexRequestTests(unittest.TestCase):
    def test_only_fixed_https_endpoint_gets_credentials_and_redirects_are_refused(self):
        with patch('codex_usage.build_opener') as opener:
            response = opener.return_value.open.return_value.__enter__.return_value
            response.read.return_value = json.dumps(payload()).encode()
            self.assertEqual(fetch_usage('private-token', 'account')[0][0]['usedPercent'], 33)
            request = opener.return_value.open.call_args.args[0]
            self.assertEqual(request.full_url, USAGE_URL)
            self.assertEqual(request.get_method(), 'GET')
            self.assertEqual(request.get_header('Authorization'), 'Bearer private-token')
            self.assertEqual(request.get_header('Chatgpt-account-id'), 'account')
            self.assertEqual(opener.return_value.open.call_args.kwargs['timeout'], 8)
        self.assertIsNone(NoRedirect().redirect_request(None, None, 302, '', {}, 'https://elsewhere.example'))

    def test_http_failures_are_sanitized_and_respect_rate_limit_cooldown(self):
        for status, code in ((401, 'codex_usage_login_required'), (429, 'codex_usage_rate_limited'),
                             (500, 'codex_usage_unavailable')):
            with patch('codex_usage.build_opener') as opener:
                opener.return_value.open.side_effect = HTTPError(USAGE_URL, status, 'private body',
                                                                 {'Retry-After': '900'}, BytesIO(b'private'))
                with self.assertRaises(UsageError) as caught:
                    fetch_usage('private-token', 'account')
                self.assertEqual(str(caught.exception), code)
                self.assertEqual(caught.exception.retry_after, 900)


class CodexDemandTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.diagnostics = []
        self.usage = CodexUsage(self.diagnostics.append)
        self.addAsyncCleanup(self.usage.close)
        self.credentials = patch('codex_usage.read_credentials', return_value=('account-key', 'token', 'account')).start()
        self.fetch = patch('codex_usage.fetch_usage', return_value=parse_usage(payload())).start()
        self.time = patch('codex_usage.time', wraps=time).start()
        self.clock = self.time.monotonic
        self.clock.return_value = 1000
        self.addCleanup(patch.stopall)

    async def finish_fetch(self):
        await asyncio.gather(*list(self.usage.tasks.values()))

    async def read_windows(self, session_row):
        return (await self.usage.reading(session_row))['windows'] or None

    async def test_sessions_share_one_request_and_success_is_independent_of_screen(self):
        self.assertIsNone(await self.read_windows(row()))
        await self.read_windows(row(terminal='two'))
        await self.finish_fetch()
        self.assertEqual((await self.read_windows(row()))[0]['usedPercent'], 33)
        self.assertEqual((await self.read_windows(row(terminal='two')))[0]['usedPercent'], 33)
        self.fetch.assert_called_once()
        self.clock.return_value = 1119
        await self.read_windows(row())
        self.fetch.assert_called_once()
        self.clock.return_value = 1120
        reading = await self.usage.reading(row())
        self.assertEqual(reading['windows'][0]['usedPercent'], 33)
        self.assertTrue(reading['refresh']['loading'])
        await self.finish_fetch()
        self.assertEqual(self.fetch.call_count, 2)

    async def test_loading_metadata_and_timestamp_follow_the_actual_request(self):
        self.time.time.return_value = 5000
        first = await self.usage.reading(row())
        self.assertEqual(first['windows'], [])
        self.assertTrue(first['refresh']['loading'])
        self.assertIsNone(first['refresh']['updatedAt'])
        await self.finish_fetch()
        ready = await self.usage.reading(row())
        self.assertFalse(ready['refresh']['loading'])
        self.assertEqual(ready['refresh']['updatedAt'], 5000)

    async def test_failed_refresh_keeps_last_reading_and_its_original_age(self):
        self.time.time.return_value = 5000
        await self.usage.reading(row())
        await self.finish_fetch()
        self.clock.return_value = 1120
        self.time.time.return_value = 5120
        self.fetch.side_effect = UsageError('codex_usage_unavailable')
        updating = await self.usage.reading(row())
        self.assertTrue(updating['refresh']['loading'])
        await self.finish_fetch()
        failed = await self.usage.reading(row())
        self.assertEqual(failed['windows'][0]['usedPercent'], 33)
        self.assertEqual(failed['refresh'], {'loading': False, 'updatedAt': 5000,
                                           'errorCode': 'codex_usage_unavailable'})
        self.fetch.assert_called_with('token', 'account')
        self.assertEqual(self.fetch.call_count, 2)

    async def test_hidden_widget_never_reads_credentials_or_starts_a_request(self):
        self.assertIsNone(await self.usage.reading(row(), visible=lambda: False))
        self.credentials.assert_not_called()
        self.fetch.assert_not_called()

    async def test_closing_during_credential_lookup_does_not_start_the_network_request(self):
        shown = True

        async def resolve(function, *args):
            nonlocal shown
            shown = False
            return 'account-key', 'token', 'account'

        with patch('codex_usage.asyncio.to_thread', side_effect=resolve):
            self.assertIsNone(await self.usage.reading(row(), visible=lambda: shown))
        self.assertFalse(self.usage.tasks)
        self.fetch.assert_not_called()

    async def test_closing_during_network_request_finishes_and_reuses_the_result_on_reopening(self):
        started, release = asyncio.Event(), asyncio.Event()
        shown = True

        async def slow_fetch(function, *args):
            if function is self.credentials:
                return 'account-key', 'token', 'account'
            started.set()
            await release.wait()
            return parse_usage(payload())

        with patch('codex_usage.asyncio.to_thread', side_effect=slow_fetch):
            await self.usage.reading(row(), visible=lambda: shown)
            await started.wait()
            shown = False
            self.assertIsNone(await self.usage.reading(row(), visible=lambda: shown))
            release.set()
            await self.finish_fetch()
            shown = True
            result = await self.usage.reading(row(), visible=lambda: shown)
            self.assertFalse(result['refresh']['loading'])
            self.assertEqual(result['windows'][0]['usedPercent'], 33)

    async def test_account_switch_drops_previous_usage_and_never_relabels_the_live_session(self):
        await self.read_windows(row())
        await self.finish_fetch()
        self.clock.return_value = 1006
        self.credentials.return_value = ('other-account', 'other-token', 'other')
        self.assertIsNone(await self.read_windows(row()))
        self.fetch.assert_called_once()
        self.assertIsNone(await self.read_windows(row(generation='second')))
        await self.finish_fetch()
        self.assertEqual(self.fetch.call_count, 2)

    async def test_missing_credentials_invalidate_cached_usage(self):
        await self.read_windows(row())
        await self.finish_fetch()
        self.clock.return_value = 1006
        self.credentials.return_value = None
        self.assertIsNone(await self.read_windows(row()))

    async def test_rate_limit_blocks_retries_even_when_access_token_rotates(self):
        self.fetch.side_effect = UsageError('codex_usage_rate_limited', 900)
        await self.read_windows(row())
        await self.finish_fetch()
        self.clock.return_value = 1301
        self.credentials.return_value = ('account-key', 'rotated-token', 'account')
        self.assertIsNone(await self.read_windows(row()))
        self.fetch.assert_called_once()
        self.assertEqual(self.diagnostics, ['codex_usage_rate_limited'])

    async def test_cli_token_refresh_recovers_from_unauthorized_without_app_refresh(self):
        self.fetch.side_effect = UsageError('codex_usage_login_required')
        await self.read_windows(row())
        await self.finish_fetch()
        self.fetch.side_effect = None
        self.clock.return_value = 1006
        self.credentials.return_value = ('account-key', 'rotated-token', 'account')
        await self.read_windows(row())
        await self.finish_fetch()
        self.assertIsNotNone(await self.read_windows(row()))
        self.assertEqual(self.fetch.call_count, 2)

    async def test_reset_expiry_hides_window_without_assuming_zero(self):
        self.fetch.return_value = parse_usage(payload(reset_at=2000), now=1000)
        self.time.time.return_value = 1999
        await self.read_windows(row())
        await self.finish_fetch()
        self.assertIsNotNone(await self.read_windows(row()))
        self.time.time.return_value = 2000
        self.assertIsNone(await self.read_windows(row()))

    async def test_inflight_network_request_does_not_block_reads_and_close_cancels_it(self):
        started, release = asyncio.Event(), asyncio.Event()

        async def slow_fetch(function, *args):
            if function is self.credentials:
                return 'account-key', 'token', 'account'
            started.set()
            await release.wait()
            return parse_usage(payload())

        with patch('codex_usage.asyncio.to_thread', side_effect=slow_fetch):
            await self.read_windows(row())
            await started.wait()
            self.assertIsNone(await self.read_windows(row(terminal='two')))
            await self.usage.close()
            self.assertFalse(self.usage.tasks)

    async def test_pruning_removes_closed_sessions_and_account_cache(self):
        await self.read_windows(row())
        await self.finish_fetch()
        self.usage.retain([])
        self.assertFalse(self.usage.accounts)
        self.assertFalse(self.usage.locations)
        self.assertFalse(self.usage.bindings)


class CodexBridgeTests(unittest.IsolatedAsyncioTestCase):
    async def run_status_once(self, api_windows, visible=True):
        from proof_bridge import ProofBridge

        bridge = ProofBridge(None, None)
        self.addAsyncCleanup(bridge.codex_usage.close)
        bridge.inventory_ready.set()
        session_row = row()
        app = type('App', (), {'get_session_by_id': lambda self, identity: object()})()
        bridge.inventory = AsyncMock(return_value=(app, [session_row]))
        bridge.focused_session = lambda app: None
        bridge.screen_text = AsyncMock(return_value='› Ask Codex to do anything\nContext 14% used · 5h 90% left')
        bridge.usage_terminal = session_row['identity'] if visible else None
        bridge.codex_usage.reading = AsyncMock(return_value={'windows': api_windows or [], 'refresh': {'loading': False, 'updatedAt': None, 'errorCode': None}})
        with patch('proof_bridge.emit') as emit, patch('proof_bridge.asyncio.sleep', side_effect=asyncio.CancelledError):
            with self.assertRaises(asyncio.CancelledError):
                await bridge.watch_status()
        return bridge, emit.call_args_list

    async def test_api_usage_reaches_the_exact_terminal_while_context_stays_on_the_screen(self):
        windows = [{'id': 'five_hour', 'usedPercent': 33, 'resetHint': '20/10 18:00'}]
        bridge, calls = await self.run_status_once(windows)
        usage = next(call.kwargs for call in calls if call.args == ('usage',))
        context = next(call.kwargs for call in calls if call.args == ('context',))
        self.assertEqual(usage['terminal'], row()['identity'])
        self.assertEqual(usage['connection'], bridge.connection)
        self.assertEqual(usage['windows'], windows)
        self.assertFalse(usage['refresh']['loading'])
        self.assertEqual(context['usedPercent'], 14)

    async def test_unavailable_api_uses_the_recognized_footer(self):
        _, calls = await self.run_status_once(None)
        usage = next(call.kwargs for call in calls if call.args == ('usage',))
        self.assertEqual(usage['windows'][0]['usedPercent'], 10)

    async def test_hidden_tooltip_does_not_query_usage_while_session_context_keeps_updating(self):
        bridge, calls = await self.run_status_once(None, visible=False)
        bridge.codex_usage.reading.assert_not_called()
        self.assertFalse(any(call.args == ('usage',) for call in calls))
        self.assertTrue(any(call.args == ('context',) for call in calls))

    async def test_visibility_commands_validate_connection_generation_and_provider_without_selecting_terminal(self):
        from proof_bridge import ProofBridge

        bridge = ProofBridge(None, None)
        self.addAsyncCleanup(bridge.codex_usage.close)
        session_row = row()
        bridge.inventory = AsyncMock(return_value=(None, [session_row]))
        base = {'version': 1, 'type': 'usage_visibility', 'requestID': 'demand',
                'connection': bridge.connection, 'terminal': session_row['identity']}
        with patch('proof_bridge.emit') as emit:
            await bridge.handle({**base, 'connection': 'old'})
            self.assertEqual(emit.call_args.kwargs['code'], 'stale_connection')
            await bridge.handle({**base, 'terminal': {**session_row['identity'], 'generation': 'old'}})
            self.assertEqual(emit.call_args.kwargs['code'], 'stale_terminal')
            self.assertIsNone(bridge.usage_terminal)
            for key, value in (('provider', 'claude'), ('local', False), ('identityConfirmed', False)):
                original = session_row[key]
                session_row[key] = value
                await bridge.handle(base)
                self.assertEqual(emit.call_args.kwargs['code'], 'stale_terminal')
                session_row[key] = original
            await bridge.handle(base)
            self.assertEqual(bridge.usage_terminal, session_row['identity'])
            self.assertIsNone(bridge.selected)
            await bridge.handle({**base, 'terminal': None})
            self.assertIsNone(bridge.usage_terminal)
            self.assertEqual(emit.call_args.args, ('ack',))
