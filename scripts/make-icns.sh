#!/bin/bash
set -euo pipefail
if [[ $# -ne 2 ]]; then
    printf '%s\n' 'Uso: make-icns.sh <AppIcon.png 1024x1024> <saida.icns>' >&2
    exit 2
fi
notchcontrol_master="$1"
notchcontrol_icns="$2"
notchcontrol_work="$(mktemp -d)"
trap 'rm -rf "$notchcontrol_work"' EXIT
notchcontrol_iconset="$notchcontrol_work/NotchControl.iconset"
mkdir "$notchcontrol_iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$notchcontrol_master" --out "$notchcontrol_iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" "$notchcontrol_master" --out "$notchcontrol_iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns --output "$notchcontrol_icns" "$notchcontrol_iconset"
