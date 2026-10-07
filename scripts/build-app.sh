#!/bin/bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/environment.sh"
notchcontrol_arch="${1:-arm64}"
if [[ "$notchcontrol_arch" != arm64 && "$notchcontrol_arch" != x86_64 ]]; then
    printf '%s\n' 'Use arm64 ou x86_64.' >&2
    exit 2
fi
notchcontrol_scratch="$notchcontrol_root/.build/release-$notchcontrol_arch"
swift build --disable-sandbox --scratch-path "$notchcontrol_scratch" --triple "$notchcontrol_arch-apple-macosx15.0" -c release --product NotchControl
notchcontrol_bin="$(swift build --disable-sandbox --scratch-path "$notchcontrol_scratch" --triple "$notchcontrol_arch-apple-macosx15.0" -c release --show-bin-path)"
notchcontrol_app="$notchcontrol_root/build/$notchcontrol_arch/NotchControl.app"
mkdir -p "$notchcontrol_app/Contents/MacOS" "$notchcontrol_app/Contents/Resources"
cp "$notchcontrol_bin/NotchControl" "$notchcontrol_app/Contents/MacOS/NotchControl"
cp -R "$notchcontrol_bin/NotchControl_NotchControl.bundle" "$notchcontrol_app/Contents/Resources/"
bash "$notchcontrol_root/scripts/make-icns.sh" "$notchcontrol_root/assets/AppIcon.png" "$notchcontrol_app/Contents/Resources/NotchControl.icns"
python3 "$notchcontrol_root/scripts/app-plist.py" "$notchcontrol_app/Contents/Info.plist" "$notchcontrol_root"
codesign --force --sign - "$notchcontrol_app"
printf '%s\n' "$notchcontrol_app"
