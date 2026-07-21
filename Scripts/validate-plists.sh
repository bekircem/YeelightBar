#!/bin/bash
set -euo pipefail

plutil -lint \
  YeelightBar/Info.plist \
  YeelightBar/YeelightBar.entitlements \
  YeelightBar/PrivacyInfo.xcprivacy

grep -q 'io.github.bekircem.yeelightbar' YeelightBar.xcodeproj/project.pbxproj
grep -q 'MARKETING_VERSION = 1.0.0;' YeelightBar.xcodeproj/project.pbxproj
grep -q 'com.apple.security.files.user-selected.read-write' YeelightBar/YeelightBar.entitlements
grep -q 'NSPrivacyAccessedAPICategoryUserDefaults' YeelightBar/PrivacyInfo.xcprivacy

echo "Release metadata validation passed."
