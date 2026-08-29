#!/bin/bash
set -euo pipefail

plutil -lint \
  YeelightBar/Info.plist \
  YeelightBar/YeelightBar.entitlements \
  YeelightBar/PrivacyInfo.xcprivacy

grep -q 'io.github.bekircem.yeelightbar' YeelightBar.xcodeproj/project.pbxproj

marketing_versions=()
while IFS= read -r version; do
  marketing_versions+=("$version")
done < <(
  sed -nE 's/^[[:space:]]*MARKETING_VERSION = ([^;]+);/\1/p' \
    YeelightBar.xcodeproj/project.pbxproj
)
if [[ ${#marketing_versions[@]} -lt 2 ]]; then
  echo 'Expected MARKETING_VERSION in every app build configuration.' >&2
  exit 1
fi
if [[ $(printf '%s\n' "${marketing_versions[@]}" | sort -u | wc -l | tr -d ' ') -ne 1 ]]; then
  echo 'MARKETING_VERSION differs between app build configurations.' >&2
  exit 1
fi
if [[ ! ${marketing_versions[0]} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'MARKETING_VERSION must be a semantic version.' >&2
  exit 1
fi

build_versions=()
while IFS= read -r version; do
  build_versions+=("$version")
done < <(
  sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION = ([^;]+);/\1/p' \
    YeelightBar.xcodeproj/project.pbxproj
)
if [[ ${#build_versions[@]} -lt 2 ]]; then
  echo 'Expected CURRENT_PROJECT_VERSION in every app build configuration.' >&2
  exit 1
fi
if [[ $(printf '%s\n' "${build_versions[@]}" | sort -u | wc -l | tr -d ' ') -ne 1 ]]; then
  echo 'CURRENT_PROJECT_VERSION differs between app build configurations.' >&2
  exit 1
fi
if [[ ! ${build_versions[0]} =~ ^[1-9][0-9]*$ ]]; then
  echo 'CURRENT_PROJECT_VERSION must be a positive integer.' >&2
  exit 1
fi

grep -q 'com.apple.security.files.user-selected.read-write' YeelightBar/YeelightBar.entitlements
grep -q 'com.apple.security.temporary-exception.mach-lookup.global-name' YeelightBar/YeelightBar.entitlements
grep -q 'NSPrivacyAccessedAPICategoryUserDefaults' YeelightBar/PrivacyInfo.xcprivacy

test "$(plutil -extract SUFeedURL raw -o - YeelightBar/Info.plist)" = \
  'https://github.com/bekircem/YeelightBar/releases/latest/download/appcast.xml'
test "$(plutil -extract SUPublicEDKey raw -o - YeelightBar/Info.plist)" = \
  'MCDTn8pk/+gOTXPi2M6tspcaRripBFgbRoLPSEGQAro='
test "$(plutil -extract SUEnableInstallerLauncherService raw -o - YeelightBar/Info.plist)" = true
test "$(plutil -extract SUVerifyUpdateBeforeExtraction raw -o - YeelightBar/Info.plist)" = true
test "$(plutil -extract SURequireSignedFeed raw -o - YeelightBar/Info.plist)" = true

echo "Release metadata validation passed."
