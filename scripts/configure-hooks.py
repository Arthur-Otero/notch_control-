import argparse
import base64
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'helper'))
from hook_configuration import fragment, update


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=('prepare', 'apply', 'remove'))
    parser.add_argument('--provider', choices=('claude', 'codex'))
    parser.add_argument('--config')
    parser.add_argument('--plan', required=True)
    args = parser.parse_args()
    plan_path = Path(args.plan)
    if args.operation == 'prepare':
        if not args.provider or not args.config:
            raise ValueError('configuration_required')
        path = Path(args.config).expanduser().absolute()
        if path.is_symlink():
            raise ValueError('configuration_symlink')
        data = path.read_bytes() if path.exists() else None
        if data:
            document = json.loads(data)
            if not isinstance(document, dict):
                raise ValueError('configuration_incompatible')
        addition = fragment(args.provider, ROOT / '.venv/bin/python3', ROOT / 'helper/proof_hook.py', ROOT / '.notchcontrol/events')
        plan = {'version': 1, 'provider': args.provider, 'path': str(path), 'addition': addition,
                'expected': base64.b64encode(data).decode() if data is not None else None}
        plan_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        descriptor = os.open(plan_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
        with os.fdopen(descriptor, 'w') as handle:
            json.dump(plan, handle, indent=2)
        os.chmod(plan_path, 0o600)
        return 0
    with plan_path.open() as handle:
        plan = json.load(handle)
    if plan.get('version') != 1:
        raise ValueError('plan_incompatible')
    expected = base64.b64decode(plan['expected']) if plan['expected'] is not None else None
    update(plan['path'], plan['addition'], expected, remove=args.operation == 'remove')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception:
        print('configuration_not_applied', file=sys.stderr)
        sys.exit(2)
