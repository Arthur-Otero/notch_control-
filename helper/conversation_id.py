"""Conversation ID an agent CLI is running, used to match work file entries to terminals."""
import json
import os
from pathlib import Path
import re
import stat

from agent_detect import CLAUDE, CODEX, CURSOR, _tokens

_UUID = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
_REGISTRY_LIMIT = 64 * 1024
_RESUME_FLAGS = {CLAUDE: ("-r", "--resume", "--session-id"), CURSOR: ("--resume",)}


def _uuid(value):
    return value.lower() if isinstance(value, str) and _UUID.fullmatch(value) else None


def claude_registry():
    """Claude Code keeps one JSON per live process with its current `sessionId`."""
    return Path.home() / ".claude" / "sessions"


def from_claude_registry(pid, proc_start, folder=None):
    """`sessionId` recorded for `pid`, only when `procStart` (C/UTC `ps -o lstart=`) proves it is the same process."""
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return None
    if pid <= 0 or not proc_start:
        return None
    try:
        descriptor = os.open(Path(folder or claude_registry()) / f"{pid}.json", os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        return None
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > _REGISTRY_LIMIT:
            return None
        with os.fdopen(descriptor, "rb") as handle:
            descriptor = None
            record = json.loads(handle.read(_REGISTRY_LIMIT + 1))
    except (OSError, ValueError):
        return None
    finally:
        if descriptor is not None:
            os.close(descriptor)
    if not isinstance(record, dict) or record.get("pid") != pid:
        return None
    if " ".join(str(record.get("procStart", "")).split()) != " ".join(str(proc_start).split()):
        return None
    return _uuid(record.get("sessionId"))


def from_command_line(provider, command):
    """UUID given to a resume: `claude -r <id>`, `claude --resume=<id>`, `codex resume <id>`, `agent --resume <id>`."""
    argv = _tokens(command)
    flags = _RESUME_FLAGS.get(provider, ())
    for index, token in enumerate(argv):
        following = argv[index + 1] if index + 1 < len(argv) else None
        if provider == CODEX:
            if token == "resume":
                return _uuid(following)
        elif token in flags:
            return _uuid(following)
        else:
            for flag in flags:
                if flag.startswith("--") and token.startswith(flag + "="):
                    return _uuid(token[len(flag) + 1:])
    return None
