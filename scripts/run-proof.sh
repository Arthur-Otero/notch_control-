#!/bin/bash
set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/environment.sh"
prepare_iterm_sdk
"$NOTCH_CONTROL_PYTHON" "$notchcontrol_root/scripts/proof_environment.py"
swift build --disable-sandbox --scratch-path "$notchcontrol_root/.build" --product NotchControlProof
notchcontrol_bin="$(swift build --disable-sandbox --scratch-path "$notchcontrol_root/.build" --show-bin-path)"
printf '%s\n' 'Abrindo a prova. Autorize NotchControl no diálogo do iTerm2 se solicitado.'
exec "$notchcontrol_bin/NotchControlProof" --project "$notchcontrol_root"
