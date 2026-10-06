"""Share of the context window a session uses, read from the same status bar as the account limits."""
import re

from account_usage import footer

_PERCENT = r"(?P<percent>\d+(?:\.\d+)?)%"
# (pattern, the number is what is left)
_PATTERNS = {
    "claude": [(r"\bctx:?\s*" + _PERCENT, False)],
    "codex": [(r"\bcontext\s+" + _PERCENT + r"\s+used\b", False), (_PERCENT + r"\s+context\s+left\b", True)],
}


def read_context(text, provider):
    """Used percent of the context window, or None when the status bar does not show it."""
    chrome = " ".join(footer(text, provider))
    for pattern, remaining in _PATTERNS.get(provider, ()):
        match = re.search(pattern, chrome, re.IGNORECASE)
        if match and 0 <= float(match.group("percent")) <= 100:
            percent = float(match.group("percent"))
            return 100 - percent if remaining else percent
    return None
