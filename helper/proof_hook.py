import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid

EVENTS = {"SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
          "PostToolUse", "Stop", "Interrupt", "Notification", "SubagentStart", "SubagentStop"}


def identifier(value):
    return value if isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_.:-]{1,160}", value) else None


def ancestors():
    rows = []
    pid = os.getppid()
    deadline = time.monotonic() + 0.6
    while pid > 1 and len(rows) < 12 and time.monotonic() < deadline:
        try:
            result = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "pid=,ppid=,tty=,lstart=,comm="],
                                    capture_output=True, text=True, timeout=0.15, check=False)
            parts = result.stdout.strip().split(maxsplit=8)
            if result.returncode != 0 or len(parts) != 9:
                break
            parent = int(parts[1])
            rows.append({"pid": int(parts[0]), "parent": parent, "tty": parts[2],
                         "processStart": " ".join(parts[3:8]), "process": Path(parts[8]).name})
            if parent == pid:
                break
            pid = parent
        except (OSError, ValueError, subprocess.TimeoutExpired):
            break
    return rows


def main():
    try:
        parser = argparse.ArgumentParser()
        parser.add_argument("--provider", required=True, choices=("claude", "codex"))
        parser.add_argument("--output", required=True)
        args = parser.parse_args()
        raw = sys.stdin.buffer.read(1024 * 1024 + 1)
        if len(raw) > 1024 * 1024:
            return 0
        payload = json.loads(raw)
        if not isinstance(payload, dict) or payload.get("hook_event_name") not in EVENTS:
            return 0
        data = {"version": 1, "sequence": time.time_ns(), "recordedAt": datetime.now(timezone.utc).isoformat(),
                "provider": args.provider, "event": payload["hook_event_name"],
                "conversation": identifier(payload.get("session_id")),
                "turn": identifier(payload.get("turn_id")), "tool": identifier(payload.get("tool_name")),
                "agent": identifier(payload.get("agent_id")),
                "notification": identifier(payload.get("notification_type")),
                "itermSession": identifier(os.environ.get("ITERM_SESSION_ID")),
                "termSession": identifier(os.environ.get("TERM_SESSION_ID")),
                "hookPID": os.getpid(), "hookParentPID": os.getppid(),
                "ancestors": ancestors(), "associationProven": False}
        folder = Path(args.output)
        folder.mkdir(mode=0o700, parents=True, exist_ok=True)
        target = folder / (str(uuid.uuid4()) + ".json")
        descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as handle:
            json.dump(data, handle, ensure_ascii=False)
            handle.write("\n")
    except (Exception, SystemExit):
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
