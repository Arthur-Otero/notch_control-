from datetime import datetime, timezone
import os
from pathlib import Path
import stat


def associate(record, rows):
    if record.get('version') != 1 or record.get('agent') or record.get('event') in ('SubagentStart', 'SubagentStop'):
        return None
    ancestors = record.get('ancestors', [])
    if not isinstance(ancestors, list):
        return None
    matches = []
    for row in rows:
        if not row.get('local') or not row.get('identityConfirmed') or row.get('provider') != record.get('provider'):
            continue
        for process in ancestors:
            if not isinstance(process, dict):
                continue
            tty = str(process.get('tty', ''))
            if not tty.startswith('/dev/'):
                tty = '/dev/' + tty
            # PID + TTY + início do processo identificam a instância; o nome do binário não conta, pois o
            # Claude Code é instalado com o nome da versão. `ps` pode preencher o dia com espaço duplo.
            if (str(process.get('pid')) == row.get('pid') and tty == row.get('tty') and row.get('processStart') and
                    ' '.join(str(process.get('processStart', '')).split()) == ' '.join(str(row.get('processStart')).split())):
                matches.append(row)
                break
    return matches[0] if len(matches) == 1 else None


def transition(record):
    event = record.get('event')
    if event == 'UserPromptSubmit':
        return 'working', None
    if event == 'PermissionRequest':
        return 'waiting', 'approval'
    if event == 'PreToolUse':
        if record.get('tool') in ('AskUserQuestion', 'request_user_input'):
            return 'waiting', 'question'
        return 'working', None
    if event == 'PostToolUse':
        return 'working', None
    if event == 'Stop':
        return 'completed', None
    if event == 'Interrupt':
        return 'interrupted', None
    if event == 'Notification' and record.get('notification') in ('permission_prompt', 'elicitation_dialog', 'elicitation_url_dialog'):
        return 'waiting', 'approval' if record['notification'] == 'permission_prompt' else 'question'
    if event == 'SessionStart':
        return 'unavailable', None
    return None


def read_record(path):
    import json
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        info = os.fstat(descriptor)
        if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600 or info.st_size > 65536:
            return None
        with os.fdopen(descriptor, 'r') as handle:
            descriptor = None
            record = json.load(handle)
        return record if isinstance(record, dict) else None
    finally:
        if descriptor is not None:
            os.close(descriptor)
