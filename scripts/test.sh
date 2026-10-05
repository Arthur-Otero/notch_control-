#!/bin/bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/environment.sh"
python3 scripts/generate-design.py --check
swift test --disable-sandbox --scratch-path .build
python3 -m unittest discover -s Tests -p 'test_*.py' -v
python3 -m py_compile helper/*.py scripts/*.py
bash -n scripts/*.sh 'Iniciar NotchControl.command' 'Iniciar Prova.command'
