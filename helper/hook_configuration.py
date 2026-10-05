import copy
import json
import os
from pathlib import Path
import shlex
import tempfile

EVENTS = ['SessionStart', 'SessionEnd', 'UserPromptSubmit', 'PreToolUse', 'PermissionRequest', 'PostToolUse', 'Stop']


def fragment(provider, python, script, output):
    command = ' '.join(shlex.quote(str(value)) for value in (python, script, '--provider', provider, '--output', output))
    events = EVENTS + (['Notification'] if provider == 'claude' else ['Interrupt'])
    return {'hooks': {event: [{'hooks': [{'type': 'command', 'command': command, 'timeout': 3}]}] for event in events}}


def merge(existing, addition, remove=False):
    result = copy.deepcopy(existing)
    if not isinstance(result, dict) or not isinstance(result.get('hooks', {}), dict):
        raise ValueError('configuration_incompatible')
    hooks = result.setdefault('hooks', {})
    for event, groups in addition['hooks'].items():
        current = hooks.get(event, [])
        if not isinstance(current, list):
            raise ValueError('configuration_incompatible')
        handlers = [handler for group in groups for handler in group['hooks']]
        commands = {handler['command'] for handler in handlers}
        if any(not isinstance(group, dict) or not isinstance(group.get('hooks'), list) for group in current):
            raise ValueError('configuration_incompatible')
        if any(handler.get('command') in commands and handler not in handlers for group in current for handler in group['hooks']):
            raise ValueError('configuration_edited')
        if remove:
            preserved = []
            for group in current:
                values = [handler for handler in group['hooks'] if handler not in handlers]
                if values:
                    item = copy.deepcopy(group)
                    item['hooks'] = values
                    preserved.append(item)
            current = preserved
        else:
            present = [handler for group in current for handler in group['hooks']]
            current = current + [group for group in groups if any(handler not in present for handler in group['hooks'])]
        if current:
            hooks[event] = current
        else:
            hooks.pop(event, None)
    return result


def update(path, addition, expected, remove=False):
    path = Path(path)
    if path.is_symlink():
        raise ValueError('configuration_symlink')
    before = path.read_bytes() if path.exists() else None
    if before != expected:
        raise ValueError('configuration_changed')
    result = merge(json.loads(before) if before else {}, addition, remove)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.notchcontrol-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as handle:
            json.dump(result, handle, indent=2, ensure_ascii=False)
            handle.write('\n')
            handle.flush()
            os.fsync(handle.fileno())
        if (path.read_bytes() if path.exists() else None) != before:
            raise ValueError('configuration_changed')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return result
