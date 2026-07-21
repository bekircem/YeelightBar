#!/bin/bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "Usage: $0 SPARKLE_BIN_DIR PRIVATE_KEY_FILE DMG RELEASE_TAG RELEASE_VERSION" >&2
  exit 64
fi

sparkle_bin_dir=$1
private_key_file=$2
dmg=$3
release_tag=$4
release_version=$5

generate_appcast="$sparkle_bin_dir/generate_appcast"
sign_update="$sparkle_bin_dir/sign_update"
dist_dir=$(dirname "$dmg")
appcast="$dist_dir/appcast.xml"
expected_dmg="YeelightBar-${release_version}.dmg"
download_prefix="https://github.com/bekircem/YeelightBar/releases/download/${release_tag}/"
release_url="https://github.com/bekircem/YeelightBar/releases/tag/${release_tag}"

if [[ ! "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ || "v$release_version" != "$release_tag" ]]; then
  echo "Sparkle appcasts are generated only for matching stable release tags." >&2
  exit 64
fi

test -x "$generate_appcast"
test -x "$sign_update"
test -s "$private_key_file"
test -f "$dmg"
test "$(basename "$dmg")" = "$expected_dmg"

"$generate_appcast" \
  --ed-key-file "$private_key_file" \
  --download-url-prefix "$download_prefix" \
  --full-release-notes-url "$release_url" \
  --link "$release_url" \
  --maximum-versions 1 \
  --maximum-deltas 0 \
  -o "$appcast" \
  "$dist_dir"

xmllint --noout "$appcast"
"$sign_update" --verify --ed-key-file "$private_key_file" "$appcast"

grep -Fq "url=\"${download_prefix}${expected_dmg}\"" "$appcast"
grep -Fq "<sparkle:shortVersionString>${release_version}</sparkle:shortVersionString>" "$appcast"
grep -Eq '<sparkle:version>[1-9][0-9]*</sparkle:version>' "$appcast"
grep -Fq '<sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>' "$appcast"
grep -Fq 'sparkle:edSignature=' "$appcast"
grep -Fq '<!-- sparkle-signatures:' "$appcast"

echo "Signed Sparkle appcast generated and verified: $appcast"
