"""Classify a visible iTerm2 screen as working, waiting or idle.

The decision uses the last lines of the screen, where Claude Code, Codex and Cursor Agent
draw their composer and status. Scrollback above that is ignored. Unrecognized screens return
None so the previous state is kept.

Claude Code is read by structure (see `_classify_claude`): its composer is a `❯` line between
two rules, so a screen with that box is never a pending decision, and a screen without it is a
decision only when a numbered option list with a cursor is drawn. Cursor Agent is read the same
way (see `_classify_cursor`) from its `▄▄▄` / `→` / `▀▀▀` composer. Codex locates its composer
before reading the activity indicator, independently of footer and draft height.
"""
import re

_WAITING = (
    "do you want to proceed",
    "yes, and don't ask again",
    "no, and tell",
    "waiting for your permission",
    "approve this",
    "permission required",
)
_FINISHED = ("worked for", "brewed for", "churned for", "· done")
_WORKING = (
    "esc to interrupt",
    "ctrl+c to stop",
    "ctrl+c to interrupt",
    "orchestrating",
)

_RULE = re.compile(r"[─━]{10,}")
# A named session (`/rename`, `--name`) gets its name drawn into the composer's top rule: "──────── my-session ─".
_TOP_RULE = re.compile(r"[─━]{10,}(?:\s+\S.*?\s+[─━]+)?")
# Claude Code 2.1.x spinner frame. What follows the ellipsis varies: "✻ Deciphering… (33s · ↓ 3.2k tokens)",
# "✢ Flowing… (1s · thinking)", "· Considering… (running PreToolUse hook · 7s)".
_SPINNER = re.compile(r"[✻✽✶✳✢·*]\s*\S+…")
# End-of-turn line, with a different verb per turn: "✻ Worked for 10s · done 2:48", "✻ Baked for 3s".
_TURN_DONE = re.compile(r"[✻✽✶✳✢·*]\s+\S+ for \d+\s*[smh]\b")
# The turn is over but the session stays busy until its background agents finish: "✻ Waiting for 2 background agents to finish".
_BACKGROUND_WAIT = re.compile(r"[✻✽✶✳✢·*]\s+Waiting for \d+ background \w+ to finish")
_OPTION = re.compile(r"(?:❯\s*)?\d+\.\s+(\S.*)")
_ANSWER = re.compile(r"(?:yes|no)\b|tell claude what to change", re.IGNORECASE)
_QUESTION = ("chat about this", "type something", "enter to select")

_CURSOR_TOP = re.compile(r"▄{10,}")
_CURSOR_BOTTOM = re.compile(r"▀{10,}")
# Cursor Agent spinner, drawn with braille frames: "⠠⠜ Working", "⠘⠆ Running  49 tokens".
_CURSOR_SPINNER = re.compile(r"[⠀-⣿]+\s+[A-Z]\w+")
# Approval options end with their key, inside a box when it is a plan: "Run (once) (y)",
# "Yes, build locally (b)", "Skip & tell the agent what to do instead (esc or n)", "No, propose changes (p or Esc)".
_CURSOR_ALLOW = re.compile(r"\((?:y|b)\)[\s│]*$")
_CURSOR_REFUSE = re.compile(r"\((?:esc or n(?: or p)?|n|p(?: or esc)?)\)[\s│]*$", re.IGNORECASE)
_CURSOR_QUESTION = re.compile(r"Question \d+ of \d+")
_CURSOR_QUESTION_HINTS = ("esc to skip", "space select", "enter next/submit")


def _claude_composer(lines):
    """Index of the composer's top rule: a rule (possibly carrying the session name), a `❯` line, then the closing rule among the last lines."""
    for bottom in range(len(lines) - 1, max(len(lines) - 9, 1), -1):
        if not _RULE.fullmatch(lines[bottom]):
            continue
        for top in range(bottom - 2, -1, -1):
            if _TOP_RULE.fullmatch(lines[top]):
                if lines[top + 1].startswith("❯"):
                    return top
                break
    return None


def _claude_decision(lines):
    """Permission, plan and AskUserQuestion dialogs replace the composer with a numbered list and a cursor."""
    tail = lines[-20:]
    options = [_OPTION.fullmatch(line) for line in tail]
    if sum(1 for option in options if option) < 2 or not any(
            option and line.startswith("❯") for option, line in zip(options, tail)):
        return None
    if any(option and _ANSWER.match(option.group(1)) for option in options):
        return "waiting", "approval"
    if any(phrase in line.lower() for line in tail for phrase in _QUESTION):
        return "waiting", "question"
    return None


def _classify_claude(lines):
    top = _claude_composer(lines)
    if top is None:
        return _claude_decision(lines)
    # The line nearest the composer decides, so a spinner left in older output above a finished turn is ignored.
    for line in reversed(lines[max(0, top - 6):top]):
        if _SPINNER.match(line) or _BACKGROUND_WAIT.match(line) or "esc to interrupt" in line.lower():
            return "working", None
        if _TURN_DONE.match(line):
            return "idle", "result"
    return "idle", None


def _cursor_composer(lines):
    """(top, bottom) of the composer box: a `▄` rule, a `→` line, then the `▀` rule among the last lines."""
    for bottom in range(len(lines) - 1, max(len(lines) - 9, 1), -1):
        if not _CURSOR_BOTTOM.fullmatch(lines[bottom]):
            continue
        for top in range(bottom - 2, -1, -1):
            if _CURSOR_TOP.fullmatch(lines[top]):
                if lines[top + 1].startswith("→"):
                    return top, bottom
                break
    return None


def _cursor_decision(lines):
    tail = lines[-16:]
    if any("waiting for approval" in line.lower() for line in tail) or (
            any(_CURSOR_ALLOW.search(line) for line in tail) and any(_CURSOR_REFUSE.search(line) for line in tail)):
        return "waiting", "approval"
    if any(_CURSOR_QUESTION.search(line) for line in tail) and any(
            hint in line.lower() for line in tail for hint in _CURSOR_QUESTION_HINTS):
        return "waiting", "question"
    return None


def _classify_cursor(lines):
    composer = _cursor_composer(lines)
    if composer is None:
        return _cursor_decision(lines)
    top, bottom = composer
    # An approval or question box replaces the composer, so with an idle composer a quoted option list is just text.
    # A turn that ends leaves no marker: the idle composer is all there is, and the transition gives the result.
    if "ctrl+c to stop" in " ".join(lines[top + 1:bottom]).lower() or any(
            _CURSOR_SPINNER.match(line) for line in lines[max(0, top - 3):top]):
        return _cursor_decision(lines) or ("working", None)
    return "idle", None


def _codex_composer(lines):
    composer = next((i for i in range(len(lines) - 1, -1, -1)
                     if (lines[i] == "›" or lines[i].startswith("› "))
                     and not re.match(r"›\s+\d+\.", lines[i])), None)
    if composer is not None and (composer >= len(lines) - 5 or any(
            _RULE.fullmatch(line) for line in lines[composer + 1:])):
        return composer
    return None


def _classify_codex(lines):
    """Read activity above the last composer, including wrapped drafts and extended status bars."""
    composer = _codex_composer(lines)
    if composer is None:
        return _classify_tail(lines)
    for line in reversed(lines[:composer]):
        if re.search(r"(?:^|[─•·]\s*)Worked for \d", line, re.IGNORECASE):
            return "idle", "result"
        if line.startswith("•") and "esc to interrupt" in line.lower():
            return "working", None
    return "idle", None


def _classify_tail(lines):
    """Status from the composer only. Words in the transcript above it are not a decision."""
    chrome = " ".join(lines[-4:]).lower()
    context = " ".join(lines[-8:]).lower()
    if any(phrase in chrome for phrase in _WAITING):
        return "waiting", "approval"
    if any(phrase in chrome for phrase in _WORKING) or ("running" in chrome and "tokens" in chrome):
        return "working", None
    recent = lines[-4:]
    if "ask codex to do anything" in chrome or "add a follow-up" in chrome or any(line in ("❯", "›", ">") for line in recent):
        finished = any(phrase in context for phrase in _FINISHED)
        return "idle", "result" if finished else None
    return None


def classify(text, provider=None):
    lines = [line.strip() for line in str(text).replace("\x00", " ").splitlines() if line.strip()]
    if provider == "codex":
        return _classify_codex(lines)
    found = {"claude": _classify_claude, "cursor": _classify_cursor}.get(provider, lambda _: None)(lines)
    return found or _classify_tail(lines)


def present(found, previous, focused):
    """What to publish. A finished turn stays green until that terminal is the open tab."""
    if found is None:
        return None
    kind, reason = found
    if kind == "idle":
        if focused:
            reason = None
        elif previous and previous[0] in ("working", "waiting"):
            reason = "result"
        elif previous:
            # Some CLIs leave no end-of-turn marker, so the green is held here instead of by the screen.
            reason = "result" if previous == ("idle", "result") else None
    if previous == (kind, reason):
        return None
    return kind, reason
