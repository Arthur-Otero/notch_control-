#!/bin/bash
set -euo pipefail
notchcontrol_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec /bin/bash "$notchcontrol_root/scripts/run-proof.sh"
