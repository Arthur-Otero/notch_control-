"""Share of the context window a session uses, read from the same status bar as the account limits."""
import re

from account_usage import footer

_PERCENT = r"(?P<percent>\d+(?:\.\d+)?)%"
_CONTEXT = r"(?:context(?:\s+window)?|ctx)"
_LEFT = r"(?:left|remaining|free)"
# A progress bar some status lines draw between the label and the number: "ctx ████░░░░ 40%".
_GAP = r"(?:\s*[\[(]?[█▓▒░▰▱■□▮▯●○]{2,}[\])]?)?"
# (pattern, the number is what is left); the first match wins, so the explicit forms come before the bare one.
_FORMATS = [
    (_PERCENT + r"\s+(?:of\s+)?" + _CONTEXT + r"\s+" + _LEFT + r"\b", True),
    (r"\b" + _CONTEXT + r"\s+" + _LEFT + r":?" + _GAP + r"\s*" + _PERCENT, True),
    (r"\b" + _CONTEXT + r":?" + _GAP + r"\s*" + _PERCENT + r"\s+" + _LEFT + r"\b", True),
    (_PERCENT + r"\s+(?:of\s+)?" + _CONTEXT + r"\s+used\b", False),
    (r"\b" + _CONTEXT + r"\s+used:?" + _GAP + r"\s*" + _PERCENT, False),
    (r"\b" + _CONTEXT + r":?" + _GAP + r"\s*" + _PERCENT, False),
]
_PATTERNS = {"claude": _FORMATS, "codex": _FORMATS}

# "12k/200k": tokens in context over the window. Only a window an agent really has counts, so a date
# ("13/10") or a pair like input/output tokens ("20k/50k") is never read as context.
_FRACTION = re.compile(r"(?<![\w./])(?P<used>\d[\d.,]*)\s*(?P<used_unit>[kK])?\s*/\s*(?P<window>\d[\d.,]*)\s*(?P<window_unit>[kKmM])?(?![\w/])")
_WINDOWS = (100_000, 128_000, 200_000, 258_000, 272_000, 400_000, 500_000, 1_000_000, 2_000_000)

# A status line piece that is only "63% left" (or remaining, free, used), with no label that says what it is about.
_SEGMENT_BREAK = re.compile(r"\s+[·|│┃•]\s+|\s{2,}|\t")
_STANDALONE = re.compile(r"^\W*" + _PERCENT + r"\s*(?P<kind>left|remaining|free|used)\W*$", re.IGNORECASE)


def _amount(number, unit):
    if unit:
        return float(number.replace(",", ".").rstrip(".")) * (1000 if unit.lower() == "k" else 1_000_000)
    return float(re.sub(r"[.,](?=\d{3}(?!\d))", "", number).rstrip(".,"))


def _from_fraction(chrome):
    for match in _FRACTION.finditer(chrome):
        try:
            used = _amount(match.group("used"), match.group("used_unit") or "")
            window = _amount(match.group("window"), match.group("window_unit") or "")
        except ValueError:
            continue
        if any(abs(window - known) <= known * 0.015 for known in _WINDOWS) and 0 <= used <= window:
            return used / window * 100
    return None


def _from_standalone(lines):
    """Claude Code status lines are the user's own: a lone "63% left" is the context, unless another piece also is one."""
    found = [match for line in lines for piece in _SEGMENT_BREAK.split(line)
             if (match := _STANDALONE.match(piece.strip()))]
    if len(found) != 1:
        return None
    percent = float(found[0].group("percent"))
    if not 0 <= percent <= 100:
        return None
    return percent if found[0].group("kind").lower() == "used" else 100 - percent


def read_context(text, provider):
    """Used percent of the context window, or None when the status bar does not show it."""
    lines = footer(text, provider)
    chrome = " ".join(lines)
    for pattern, remaining in _PATTERNS.get(provider, ()):
        match = re.search(pattern, chrome, re.IGNORECASE)
        if match and 0 <= float(match.group("percent")) <= 100:
            percent = float(match.group("percent"))
            return 100 - percent if remaining else percent
    if provider not in _PATTERNS:
        return None
    reading = _from_fraction(chrome)
    if reading is None and provider == "claude":
        reading = _from_standalone(lines)
    return reading
