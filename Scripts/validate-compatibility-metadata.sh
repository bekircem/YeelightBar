#!/bin/bash
set -euo pipefail

deployment_target_count=$(grep -c 'MACOSX_DEPLOYMENT_TARGET = 26.0;' YeelightBar.xcodeproj/project.pbxproj)
test "$deployment_target_count" -eq 6

grep -Fq '<string>$(MACOSX_DEPLOYMENT_TARGET)</string>' YeelightBar/Info.plist
grep -Fq 'macOS-26%2B' README.md
grep -Fq '| macOS | Tahoe 26 or later |' README.md
grep -Fq 'macOS 26 Tahoe' CONTRIBUTING.md
grep -Fq 'macOS 26 Tahoe' RELEASE_CHECKLIST.md
grep -Fq '"operatingSystem": "macOS 26 Tahoe or later"' docs/index.html
grep -Fq '<span>macOS 26+</span>' docs/index.html
grep -Fq '<li>macOS Tahoe 26 or later</li>' docs/index.html
grep -Fq 'depends_on macos: :tahoe' packaging/homebrew/yeelightbar.rb.template
grep -Fq '<sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>' Scripts/generate-sparkle-appcast.sh

if rg -n 'Ventura|macOS 13|13\.0|:ventura|macOS-13' \
  README.md CONTRIBUTING.md RELEASE_CHECKLIST.md docs/index.html \
  packaging/homebrew/yeelightbar.rb.template Scripts/generate-sparkle-appcast.sh; then
  echo 'Legacy macOS compatibility metadata detected.' >&2
  exit 1
fi

echo 'macOS 26 Tahoe compatibility metadata validation passed.'
