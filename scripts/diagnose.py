import argparse
import importlib.metadata
import json
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', required=True)
    args = parser.parse_args()
    installed = any(path.exists() for path in [Path('/Applications/iTerm.app'), Path('/Applications/iTerm2.app'), Path.home() / 'Applications/iTerm.app', Path.home() / 'Applications/iTerm2.app'])
    try:
        result = subprocess.run(['/usr/bin/defaults', 'read', 'com.googlecode.iterm2', 'EnableAPIServer'], capture_output=True, text=True, timeout=2)
        api = result.returncode == 0 and result.stdout.strip() == '1'
    except (OSError, subprocess.TimeoutExpired):
        api = None
    try:
        sdk = importlib.metadata.version('iterm2')
    except importlib.metadata.PackageNotFoundError:
        sdk = None
    providers = {}
    names = {'claude': ('claude',), 'codex': ('codex',), 'cursor': ('agent', 'cursor-agent')}
    paths = ['/opt/homebrew/bin', '/usr/local/bin', str(Path.home() / '.local/bin'), str(Path.home() / '.npm-global/bin')]
    for provider, candidates in names.items():
        providers[provider] = any(shutil.which(name) or any((Path(path) / name).is_file() for path in paths) for name in candidates)
    print(json.dumps({'version': 1, 'itermInstalled': installed, 'apiEnabled': api, 'sdkVersion': sdk,
                      'pythonAvailable': True, 'providers': providers, 'hookTrust': 'requires_cli_review'}))
    return 0


if __name__ == '__main__':
    sys.exit(main())
