"""Read Codex account quotas without refreshing credentials or changing CLI files."""
import asyncio
import ctypes
from datetime import datetime
import hashlib
from http.client import HTTPException
import json
import math
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, Request, build_opener

USAGE_URL = 'https://chatgpt.com/backend-api/wham/usage'
CACHE_SECONDS = 120
RATE_LIMIT_RETRY_SECONDS = 300
MAX_BODY = 128 * 1024
WINDOWS = {18000: 'five_hour', 604800: 'seven_day'}


def number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        return None
    try:
        result = float(value)
        return result if math.isfinite(result) else None
    except (ValueError, OverflowError):
        return None


def parse_usage(payload, now=None):
    """Identify windows by duration, since the weekly limit may occupy either slot."""
    now = time.time() if now is None else now
    limits = payload.get('rate_limit') if isinstance(payload, dict) else None
    if not isinstance(limits, dict):
        raise ValueError('invalid_usage')
    found = {}
    for slot in ('primary_window', 'secondary_window'):
        window = limits.get(slot)
        if window is None:
            continue
        if not isinstance(window, dict):
            raise ValueError('invalid_usage')
        key = WINDOWS.get(number(window.get('limit_window_seconds')))
        if key is None:
            continue
        percent = number(window.get('used_percent'))
        if key in found or percent is None or not 0 <= percent <= 100:
            raise ValueError('invalid_usage')
        reset = number(window.get('reset_at'))
        if reset is None:
            after = number(window.get('reset_after_seconds'))
            reset = now + after if after is not None and after >= 0 else None
        hint = None
        if reset is not None and reset > now:
            try:
                hint = datetime.fromtimestamp(reset).astimezone().strftime('%d/%m %H:%M')
            except (ValueError, OverflowError, OSError):
                reset = None
        elif reset is not None:
            continue
        found[key] = ({'id': key, 'usedPercent': percent, 'resetHint': hint}, reset)
    return [found[key] for key in WINDOWS.values() if key in found]


def parse_process_environment(data):
    """Extract only home locations from macOS KERN_PROCARGS2, skipping executable and argv."""
    if len(data) < 4:
        raise ValueError('invalid_process')
    argc = struct.unpack_from('=i', data)[0]
    if not 1 <= argc <= 65536:
        raise ValueError('invalid_process')
    offset = data.index(b'\0', 4) + 1
    while offset < len(data) and data[offset] == 0:
        offset += 1
    for _ in range(argc):
        offset = data.index(b'\0', offset) + 1
    locations = {}
    for item in data[offset:].split(b'\0'):
        key, separator, value = item.partition(b'=')
        if separator and key in (b'HOME', b'CODEX_HOME'):
            name = key.decode('ascii')
            if name in locations:
                raise ValueError('ambiguous_process')
            locations[name] = os.fsdecode(value)
    return locations


def process_environment(pid):
    if sys.platform != 'darwin':
        raise OSError('unsupported_platform')
    libc = ctypes.CDLL(None, use_errno=True)
    mib = (ctypes.c_int * 3)(1, 49, pid)
    size = ctypes.c_size_t(1024 * 1024)
    buffer = ctypes.create_string_buffer(size.value)
    if libc.sysctl(mib, 3, buffer, ctypes.byref(size), None, 0) != 0:
        raise OSError('process_unavailable')
    return parse_process_environment(buffer.raw[:size.value])


def process_start(pid):
    result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'lstart='],
                            capture_output=True, text=True, timeout=0.5)
    return ' '.join(result.stdout.split()) if result.returncode == 0 else None


def read_credentials(row):
    """Bind credentials to the live process home; never assume the helper shares its login."""
    if row.get('provider') != 'codex' or not row.get('local') or not row.get('identityConfirmed'):
        return None
    try:
        pid = int(row['pid'])
        expected = row.get('processStart')
        if pid <= 0 or not expected or process_start(pid) != expected:
            return None
        locations = process_environment(pid)
        home = locations.get('CODEX_HOME')
        if not home:
            user_home = locations.get('HOME')
            if not user_home or not os.path.isabs(user_home):
                return None
            home = str(Path(user_home) / '.codex')
        if not os.path.isabs(home):
            return None
        config = Path(home) / 'config.toml'
        if config.exists():
            with config.open('rb') as source:
                settings = source.read(MAX_BODY + 1)
            if len(settings) > MAX_BODY:
                return None
            stores = re.findall(rb'^\s*cli_auth_credentials_store\s*=\s*[\'"]([^\'"]+)[\'"]',
                                settings, re.MULTILINE)
            if any(store != b'file' for store in stores):
                return None
        path = Path(home) / 'auth.json'
        with path.open('rb') as source:
            raw = source.read(MAX_BODY + 1)
        if len(raw) > MAX_BODY:
            return None
        auth = json.loads(raw)
        if not isinstance(auth, dict) or auth.get('auth_mode') not in (None, 'chatgpt'):
            return None
        tokens = auth.get('tokens')
        if not isinstance(tokens, dict):
            return None
        token, account = tokens.get('access_token'), tokens.get('account_id')
        if any(not isinstance(value, str) or not value or not value.isascii()
               or any(ord(c) < 33 or ord(c) == 127 for c in value) for value in (token, account)):
            return None
        if process_start(pid) != expected:
            return None
        key = hashlib.sha256((str(path.resolve()) + '\0' + account).encode()).hexdigest()
        return key, token, account
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired):
        return None


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class UsageError(Exception):
    def __init__(self, code, retry_after=CACHE_SECONDS):
        super().__init__(code)
        self.code = code
        self.retry_after = retry_after


def fetch_usage(token, account):
    request = Request(USAGE_URL, headers={'Authorization': 'Bearer ' + token,
                      'ChatGPT-Account-Id': account, 'User-Agent': 'codex-cli', 'Accept': 'application/json'})
    try:
        with build_opener(NoRedirect()).open(request, timeout=8) as response:
            raw = response.read(MAX_BODY + 1)
        if len(raw) > MAX_BODY:
            raise ValueError('invalid_usage')
        return parse_usage(json.loads(raw))
    except HTTPError as error:
        retry = number(error.headers.get('Retry-After')) if error.headers else None
        code = 'codex_usage_login_required' if error.code in (401, 403) else 'codex_usage_unavailable'
        if error.code == 429:
            code = 'codex_usage_rate_limited'
        minimum = RATE_LIMIT_RETRY_SECONDS if error.code == 429 else CACHE_SECONDS
        error.close()
        raise UsageError(code, max(minimum, min(retry or minimum, 3600))) from None
    except (OSError, URLError, HTTPException, ValueError):
        raise UsageError('codex_usage_unavailable') from None


class CodexUsage:
    def __init__(self, diagnostic=lambda code: None):
        self.diagnostic = diagnostic
        self.accounts = {}
        self.bindings = {}
        self.locations = {}
        self.tasks = {}

    async def reading(self, row, visible=lambda: True):
        if not visible():
            return None
        identity = (row['identity']['id'], row['identity']['generation'])
        now = time.monotonic()
        cached = self.locations.get(identity)
        if cached is None or now - cached[0] >= 5:
            credentials = await asyncio.to_thread(read_credentials, row)
            self.locations[identity] = (now, credentials)
        else:
            credentials = cached[1]
        if not visible():
            return None
        if credentials is None:
            return {'windows': [], 'refresh': {'loading': False, 'updatedAt': None,
                    'errorCode': 'codex_usage_unavailable'}}
        key, token, account = credentials
        bound = self.bindings.setdefault(identity, key)
        if bound != key:
            return {'windows': [], 'refresh': {'loading': False, 'updatedAt': None,
                    'errorCode': 'codex_usage_unavailable'}}
        entry = self.accounts.setdefault(key, {'windows': [], 'updatedAt': None, 'sampled': 0,
                                               'next': 0, 'token': None, 'error': None})
        fingerprint = hashlib.sha256(token.encode()).hexdigest()
        if entry['token'] != fingerprint and entry['error'] == 'codex_usage_login_required':
            entry['next'] = 0
        if now >= entry['next'] and key not in self.tasks:
            entry['next'] = now + CACHE_SECONDS
            entry['token'] = fingerprint
            self.tasks[key] = asyncio.create_task(self.refresh(key, token, account))
        wall = time.time()
        windows = [window for window, reset in entry['windows'] if reset is None or wall < reset]
        return {'windows': windows, 'refresh': {'loading': key in self.tasks,
                'updatedAt': entry['updatedAt'] if windows else None, 'errorCode': entry['error']}}

    async def refresh(self, key, token, account):
        entry = self.accounts[key]
        try:
            entry['windows'] = await asyncio.to_thread(fetch_usage, token, account)
            entry['sampled'] = time.monotonic()
            entry['updatedAt'] = time.time()
            entry['next'] = entry['sampled'] + CACHE_SECONDS
            entry['error'] = None
        except UsageError as error:
            entry['error'] = error.code
            entry['next'] = time.monotonic() + error.retry_after
            self.diagnostic(error.code)
        finally:
            self.tasks.pop(key, None)

    def retain(self, rows):
        live = {(row['identity']['id'], row['identity']['generation']) for row in rows}
        self.bindings = {key: value for key, value in self.bindings.items() if key in live}
        self.locations = {key: value for key, value in self.locations.items() if key in live}
        active = set(self.bindings.values()) | set(self.tasks)
        self.accounts = {key: value for key, value in self.accounts.items() if key in active}

    async def close(self):
        tasks = list(self.tasks.values())
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
