#!/bin/bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 VERSION SHA256 OUTPUT_FILE" >&2
  exit 64
fi

version=$1
sha256=$2
output_file=$3
mkdir -p "$(dirname "$output_file")"

sed \
  -e "s/__VERSION__/$version/g" \
  -e "s/__SHA256__/$sha256/g" \
  packaging/homebrew/yeelightbar.rb.template > "$output_file"
