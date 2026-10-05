#!/bin/bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/environment.sh"
prepare_iterm_sdk
bash "$notchcontrol_root/scripts/build-app.sh" "$(uname -m)"
exec "$notchcontrol_root/build/$(uname -m)/NotchControl.app/Contents/MacOS/NotchControl" --project "$notchcontrol_root"
