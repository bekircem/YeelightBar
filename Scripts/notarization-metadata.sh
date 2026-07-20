#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage:" >&2
  echo "  $0 create METADATA SUBMISSION_JSON DMG RELEASE_TAG VERSION COMMIT SOURCE_RUN_ID" >&2
  echo "  $0 validate METADATA SUBMISSION_JSON DMG RELEASE_TAG VERSION COMMIT SOURCE_RUN_ID" >&2
  exit 64
}

if [[ $# -ne 8 ]]; then usage; fi

operation=$1
metadata=$2
submission_result=$3
dmg=$4
release_tag=$5
version=$6
release_commit=$7
source_run_id=$8

if [[ "$operation" != create && "$operation" != validate ]]; then usage; fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]]; then
  echo 'Invalid release version in notarization metadata.' >&2
  exit 64
fi
if [[ "$release_tag" != "v$version" ]]; then
  echo 'Release tag and version do not match.' >&2
  exit 64
fi
if [[ ! "$release_commit" =~ ^[0-9A-Fa-f]{40}$ ]]; then
  echo 'Invalid release commit in notarization metadata.' >&2
  exit 64
fi
if [[ ! "$source_run_id" =~ ^[1-9][0-9]*$ ]]; then
  echo 'Invalid source run ID in notarization metadata.' >&2
  exit 64
fi
if [[ ! -f "$submission_result" || ! -f "$dmg" ]]; then
  echo 'Notarization submission result or DMG is missing.' >&2
  exit 66
fi

submission_id=$(/usr/bin/plutil -extract id raw -o - "$submission_result")
if [[ ! "$submission_id" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
  echo 'Apple did not return a valid notarization submission ID.' >&2
  exit 65
fi

actual_sha=$(shasum -a 256 "$dmg" | awk '{print $1}')

if [[ "$operation" == create ]]; then
  mkdir -p "$(dirname "$metadata")"
  rm -f "$metadata"
  /usr/bin/plutil -create xml1 "$metadata"
  /usr/bin/plutil -insert releaseTag -string "$release_tag" "$metadata"
  /usr/bin/plutil -insert version -string "$version" "$metadata"
  /usr/bin/plutil -insert commit -string "$release_commit" "$metadata"
  /usr/bin/plutil -insert sourceRunID -string "$source_run_id" "$metadata"
  /usr/bin/plutil -insert submissionID -string "$submission_id" "$metadata"
  /usr/bin/plutil -insert preNotarizationSHA256 -string "$actual_sha" "$metadata"
else
  if [[ ! -f "$metadata" ]]; then
    echo 'Preserved notarization metadata is missing.' >&2
    exit 66
  fi

  test "$(/usr/bin/plutil -extract releaseTag raw -o - "$metadata")" = "$release_tag"
  test "$(/usr/bin/plutil -extract version raw -o - "$metadata")" = "$version"
  test "$(/usr/bin/plutil -extract commit raw -o - "$metadata")" = "$release_commit"
  test "$(/usr/bin/plutil -extract sourceRunID raw -o - "$metadata")" = "$source_run_id"
  test "$(/usr/bin/plutil -extract submissionID raw -o - "$metadata")" = "$submission_id"
  test "$(/usr/bin/plutil -extract preNotarizationSHA256 raw -o - "$metadata")" = "$actual_sha"
fi

printf '%s\n' "$submission_id"
