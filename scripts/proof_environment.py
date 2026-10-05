import importlib.metadata
import json
import os
import platform
import plistlib
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def version(command):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=10, check=False)
        return result.stdout.strip() if result.returncode == 0 else "unavailable"
    except (OSError, subprocess.TimeoutExpired):
        return "unavailable"


def main():
    root = Path(__file__).resolve().parent.parent
    folder = root / ".proof"
    folder.mkdir(mode=0o700, exist_ok=True)
    candidates = [Path("/Applications/iTerm.app"), Path.home() / "Applications/iTerm.app"]
    iterm_version = "unavailable"
    for candidate in candidates:
        info = candidate / "Contents/Info.plist"
        if info.exists():
            with info.open("rb") as handle:
                iterm_version = plistlib.load(handle).get("CFBundleShortVersionString", "unavailable")
            break
    try:
        sdk = importlib.metadata.version("iterm2")
    except importlib.metadata.PackageNotFoundError:
        sdk = "missing"
    data = {
        "recordedAt": datetime.now(timezone.utc).isoformat(),
        "macOS": platform.mac_ver()[0], "architecture": platform.machine(),
        "python": platform.python_version(), "iTerm2": iterm_version, "iTermSDK": sdk,
        "swift": version(["swift", "--version"]), "xcode": version(["xcodebuild", "-version"]),
        "claude": version(["claude", "--version"]), "codex": version(["codex", "--version"]),
        "apiEnabled": version(["defaults", "read", "com.googlecode.iterm2", "EnableAPIServer"]),
        "gates": "pending"
    }
    target = folder / "environment.json"
    descriptor = os.open(target, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print("Ambiente registrado em .proof/environment.json; gates reais continuam pendentes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
