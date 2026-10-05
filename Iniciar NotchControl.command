#!/bin/bash
set -euo pipefail
notchcontrol_root="$(cd -- "$(dirname -- "$0")" && pwd)"
exec /bin/bash "$notchcontrol_root/scripts/run-app.sh"
