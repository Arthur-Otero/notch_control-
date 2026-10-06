"""Read account limits from provider status bars, never from conversation text or context usage."""
import re
from screen_status import _claude_composer, _cursor_composer, _codex_composer

_PERCENT = r"(\d+(?:\.\d+)?)%"


def footer(text, provider):
    """Status bar lines below the provider's composer; empty when the composer is not on screen."""
    lines = [line.strip() for line in str(text).replace('\x00', ' ').splitlines() if line.strip()]
    footer = []
    if provider == 'codex':
        composer = _codex_composer(lines)
        if composer is not None:
            footer = lines[composer + 1:]
    elif provider == 'claude':
        top = _claude_composer(lines)
        if top is not None:
            bottom = next((i for i in range(top + 2, len(lines))
                           if re.fullmatch(r'[─━]{10,}', lines[i])), None)
            if bottom is not None:
                footer = lines[bottom + 1:]
    elif provider == 'cursor':
        composer = _cursor_composer(lines)
        if composer is not None:
            footer = lines[composer[1] + 1:]
    return footer


def read_usage(text, provider):
    chrome = ' '.join(footer(text, provider))
    windows = []

    def append(key, pattern, remaining=False):
        if any(window['id'] == key for window in windows):
            return
        match = re.search(pattern, chrome, re.IGNORECASE)
        if not match:
            return
        percent = float(match.group('percent'))
        if not 0 <= percent <= 100:
            return
        hint = match.groupdict().get('reset')
        windows.append({'id': key, 'usedPercent': 100 - percent if remaining else percent,
                        'resetHint': hint})

    percentage = _PERCENT.replace('(', '(?P<percent>', 1)
    if provider == 'codex':
        append('five_hour', r'\b5h\s+' + percentage + r'\s+left\b', remaining=True)
        append('seven_day', r'\bweekly\s+' + percentage + r'\s+left\b', remaining=True)
    elif provider == 'claude':
        append('five_hour', r'\b5h\s+' + percentage)
        append('seven_day', r'\b7d\s+' + percentage)
        append('five_hour', r'(?:^|[·|]\s*)(?P<reset>(?:[01]\d|2[0-3]):[0-5]\d)\s+' + percentage)
        append('seven_day', r'(?:^|[·|]\s*)(?P<reset>(?:0[1-9]|[12]\d|3[01])/(?:0[1-9]|1[0-2]))\s+' + percentage)
    elif provider == 'cursor':
        append('cursor', r'\bcursor\s+' + percentage)
        append('other_models', r'\bothers\s+' + percentage + r'(?:\s+\(resets\s+(?P<reset>\d+[mhd](?:\s+\d+[mhd])?)\))?')
    return windows


class UsageTracker:
    """Keep limits through transient dialogs; expire hidden readings and isolate process generations."""
    def __init__(self):
        self.readings = {}
        self.published = {}
        self.sent_at = {}

    def update(self, identity, windows, now):
        key = (identity['id'], identity['generation'])
        if windows:
            self.readings[key] = (windows, now)
        previous = self.readings.get(key)
        current = previous[0] if previous and now - previous[1] < 300 else []
        if self.published.get(key) == current and now - self.sent_at.get(key, 0) < 5:
            return None
        self.published[key] = current
        self.sent_at[key] = now
        return current

    def retain(self, identities):
        live = {(value['id'], value['generation']) for value in identities}
        self.readings = {key: value for key, value in self.readings.items() if key in live}
        self.published = {key: value for key, value in self.published.items() if key in live}
        self.sent_at = {key: value for key, value in self.sent_at.items() if key in live}
