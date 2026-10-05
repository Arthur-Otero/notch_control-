#!/bin/bash
notchcontrol_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$notchcontrol_root"
export CLANG_MODULE_CACHE_PATH="$notchcontrol_root/.build/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$notchcontrol_root/.build/cache/swift"
export PYTHONPYCACHEPREFIX="$notchcontrol_root/.build/cache/python"

prepare_iterm_sdk() {
    local python="$notchcontrol_root/.venv/bin/python3"
    if [[ ! -x "$python" ]]; then
        python3 -m venv "$notchcontrol_root/.venv"
    fi
    if ! "$python" -c 'import iterm2, importlib.metadata; assert importlib.metadata.version("iterm2") == "2.25"' 2>/dev/null; then
        "$python" -m pip --disable-pip-version-check install --cache-dir "$notchcontrol_root/.build/cache/pip" --requirement "$notchcontrol_root/helper/requirements.txt"
    fi
    export NOTCH_CONTROL_PYTHON="$python"
}
