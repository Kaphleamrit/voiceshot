#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 2 ]]; then
    echo "Usage: bash scripts/package-dmg.sh VoiceShot.app output.dmg" >&2
    exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app="$1"
output="$2"
work_dir="$(mktemp -d)"
mounted=""
cleanup() {
    if [[ -n "$mounted" ]]; then
        hdiutil detach "$mounted" -quiet || return
    fi
    rm -rf "$work_dir"
}
trap cleanup EXIT

volume_name="Drag VoiceShot to Applications"

codesign --verify --deep --strict "$app"
python3 -m venv "$work_dir/venv"
"$work_dir/venv/bin/python" -m pip install --disable-pip-version-check --quiet 'dmgbuild==1.6.5'
"$work_dir/venv/bin/dmgbuild" -s "$script_dir/dmg-settings.py" -D "app=$app" \
    "$volume_name" "$work_dir/layout.dmg"

mount_path="$work_dir/mounted"
mkdir "$mount_path"
hdiutil attach -readonly -nobrowse -noautoopen -quiet -mountpoint "$mount_path" "$work_dir/layout.dmg"
mounted="$mount_path"
ditto "$mounted" "$work_dir/payload"
hdiutil detach "$mounted" -quiet
mounted=""

# Mark the HFS+ root for Finder to open when the disk image mounts.
hdiutil makehybrid -quiet -hfs -hfs-volume-name "$volume_name" -hfs-openfolder "$work_dir/payload" \
    "$work_dir/payload" -o "$work_dir/installer.dmg"
hdiutil convert -quiet "$work_dir/installer.dmg" -format UDRW -o "$work_dir/writable.dmg"
hdiutil attach -readwrite -nobrowse -noautoopen -quiet -mountpoint "$mount_path" "$work_dir/writable.dmg"
mounted="$mount_path"

# makehybrid adds FinderInfo to some executable files, which invalidates strict code signing.
xattr -dr com.apple.FinderInfo "$mounted/VoiceShot.app"
codesign --verify --deep --strict "$mounted/VoiceShot.app"
hdiutil detach "$mounted" -quiet
mounted=""

hdiutil convert -quiet "$work_dir/writable.dmg" -format UDZO -o "$output"
hdiutil verify "$output"
