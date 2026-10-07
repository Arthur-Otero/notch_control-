"""Share of the context window a session uses, read from the same status bar as the account limits."""
import re

from account_usage import footer

_PERCENT = r"(?P<percent>\d+(?:\.\d+)?)%"
_CONTEXT = r"(?:context(?:\s+window)?|ctx)"
_LEFT = r"(?:left|remaining|free)"
# A bare "63% left" is not here on purpose: without the word context it could be any limit.
# (pattern, the number is what is left); the first match wins, so the explicit forms come before the bare one.
_FORMATS = [
    (_PERCENT + r"\s+(?:of\s+)?" + _CONTEXT + r"\s+" + _LEFT + r"\b", True),
    (r"\b" + _CONTEXT + r"\s+" + _LEFT + r":?\s*" + _PERCENT, True),
    (r"\b" + _CONTEXT + r":?\s*" + _PERCENT + r"\s+" + _LEFT + r"\b", True),
    (_PERCENT + r"\s+(?:of\s+)?" + _CONTEXT + r"\s+used\b", False),
    (r"\b" + _CONTEXT + r"\s+used:?\s*" + _PERCENT, False),
    (r"\b" + _CONTEXT + r":?\s*" + _PERCENT, False),
]
_PATTERNS = {"claude": _FORMATS, "codex": _FORMATS}


def read_context(text, provider):
    """Used percent of the context window, or None when the status bar does not show it."""
    chrome = " ".join(footer(text, provider))
    for pattern, remaining in _PATTERNS.get(provider, ()):
        match = re.search(pattern, chrome, re.IGNORECASE)
        if match and 0 <= float(match.group("percent")) <= 100:
            percent = float(match.group("percent"))
            return 100 - percent if remaining else percent
    return None
