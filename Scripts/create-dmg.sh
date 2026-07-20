#!/bin/bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 /path/YeelightBar.app /path/output.dmg VolumeName" >&2
  exit 64
fi

app_path=$1
output_path=$2
volume_name=$3
if [[ ! "$volume_name" =~ ^[A-Za-z0-9._\ -]+$ ]]; then
  echo "Volume name contains unsupported characters." >&2
  exit 65
fi
work_dir=$(mktemp -d)
mount_point=
read_write_dmg="$work_dir/read-write.dmg"

cleanup() {
  if [[ -n "$mount_point" ]]; then
    hdiutil detach "$mount_point" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT

hdiutil create -quiet -size 80m -fs HFS+ -volname "$volume_name" "$read_write_dmg"
attach_output=$(hdiutil attach -nobrowse -readwrite "$read_write_dmg")
mount_point=$(printf '%s\n' "$attach_output" | awk -F '\t' '$2 ~ /Apple_(HFS|APFS)/ { print $NF; exit }')
if [[ -z "$mount_point" || ! -d "$mount_point" ]]; then
  echo "Could not determine the mounted disk image path." >&2
  exit 66
fi
ditto "$app_path" "$mount_point/YeelightBar.app"
ln -s /Applications "$mount_point/Applications"

# Finder writes the native icon layout into .DS_Store. A release fails if the
# styled layout cannot be created, avoiding an unreviewed fallback artifact.
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$volume_name"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 200, 760, 600}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set position of item "YeelightBar.app" of container window to {160, 190}
    set position of item "Applications" of container window to {400, 190}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach -quiet "$mount_point"
mkdir -p "$(dirname "$output_path")"
hdiutil convert -quiet "$read_write_dmg" -format UDZO -imagekey zlib-level=9 -o "$output_path"
