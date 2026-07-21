#!/bin/bash
set -euo pipefail

plutil -lint \
  YeelightBar/Info.plist \
  YeelightBar/YeelightBar.entitlements \
  YeelightBar/PrivacyInfo.xcprivacy

grep -q 'io.github.bekircem.yeelightbar' YeelightBar.xcodeproj/project.pbxproj
grep -q 'MARKETING_VERSION = 1.1.0;' YeelightBar.xcodeproj/project.pbxproj
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
