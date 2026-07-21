#!/usr/bin/env bash

set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/yeelightbar-notary-test.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

mkdir -p "$work_dir/bin"
touch "$work_dir/AuthKey_TESTKEY.p8"

cat > "$work_dir/bin/xcrun" <<'FAKE_XCRUN'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} != notarytool ]]; then exit 64; fi
operation=${2:-}
state_file=${FAKE_NOTARY_STATE:?}
mode=${FAKE_NOTARY_MODE:-accepted}

case "$operation" in
  info)
    count=0
    if [[ -f "$state_file" ]]; then count=$(<"$state_file"); fi
    count=$((count + 1))
    echo "$count" > "$state_file"

    if [[ "$mode" == transient && "$count" -eq 1 ]]; then
      exit 1
    elif [[ "$mode" == invalid ]]; then
      printf '%s\n' '{"id":"11111111-2222-3333-4444-555555555555","status":"Invalid"}'
    elif [[ "$count" -eq 1 ]]; then
      printf '%s\n' '{"id":"11111111-2222-3333-4444-555555555555","status":"In Progress"}'
    else
      printf '%s\n' '{"id":"11111111-2222-3333-4444-555555555555","status":"Accepted"}'
    fi
    ;;
  log)
    printf '%s\n' '{"id":"11111111-2222-3333-4444-555555555555","issues":[]}'
    ;;
  *)
    exit 64
    ;;
esac
FAKE_XCRUN
chmod +x "$work_dir/bin/xcrun"

run_wait_test() {
  local mode=$1
  local expected_exit=$2
  local case_dir="$work_dir/$mode"
  mkdir -p "$case_dir"

  set +e
  PATH="$work_dir/bin:$PATH" \
    FAKE_NOTARY_STATE="$case_dir/state" \
    FAKE_NOTARY_MODE="$mode" \
    NOTARY_POLL_INTERVAL_SECONDS=1 \
    NOTARY_WAIT_TIMEOUT_SECONDS=10 \
    NOTARY_MAX_TRANSIENT_FAILURES=3 \
    bash "$root_dir/Scripts/wait-for-notarization.sh" \
      '11111111-2222-3333-4444-555555555555' \
      "$work_dir/AuthKey_TESTKEY.p8" \
      TESTKEY \
      'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' \
      "$case_dir/result.json" \
      "$case_dir/log.json"
  actual_exit=$?
  set -e

  if [[ "$actual_exit" -ne "$expected_exit" ]]; then
    echo "$mode test exited $actual_exit; expected $expected_exit." >&2
    exit 1
  fi
  test -s "$case_dir/result.json"
  test -s "$case_dir/log.json"
}

run_wait_test accepted 0
run_wait_test transient 0
run_wait_test invalid 65

metadata_case="$work_dir/metadata"
mkdir -p "$metadata_case"
printf '%s\n' '{"id":"11111111-2222-3333-4444-555555555555","message":"Successfully uploaded file"}' > "$metadata_case/submission.json"
printf '%s\n' 'signed DMG test fixture' > "$metadata_case/YeelightBar-1.0.0-rc.8.dmg"
metadata_submission_id=$(bash "$root_dir/Scripts/notarization-metadata.sh" create \
  "$metadata_case/release-metadata.plist" \
  "$metadata_case/submission.json" \
  "$metadata_case/YeelightBar-1.0.0-rc.8.dmg" \
  v1.0.0-rc.8 \
  1.0.0-rc.8 \
  0123456789abcdef0123456789abcdef01234567 \
  123456789)
test "$metadata_submission_id" = '11111111-2222-3333-4444-555555555555'
validated_submission_id=$(bash "$root_dir/Scripts/notarization-metadata.sh" validate \
  "$metadata_case/release-metadata.plist" \
  "$metadata_case/submission.json" \
  "$metadata_case/YeelightBar-1.0.0-rc.8.dmg" \
  v1.0.0-rc.8 \
  1.0.0-rc.8 \
  0123456789abcdef0123456789abcdef01234567 \
  123456789)
test "$validated_submission_id" = "$metadata_submission_id"

printf '%s\n' 'tampered artifact' >> "$metadata_case/YeelightBar-1.0.0-rc.8.dmg"
set +e
bash "$root_dir/Scripts/notarization-metadata.sh" validate \
  "$metadata_case/release-metadata.plist" \
  "$metadata_case/submission.json" \
  "$metadata_case/YeelightBar-1.0.0-rc.8.dmg" \
  v1.0.0-rc.8 \
  1.0.0-rc.8 \
  0123456789abcdef0123456789abcdef01234567 \
  123456789 >/dev/null 2>&1
tampered_artifact_exit=$?
set -e
test "$tampered_artifact_exit" -ne 0

set +e
PATH="$work_dir/bin:$PATH" bash "$root_dir/Scripts/wait-for-notarization.sh" \
  invalid-id \
  "$work_dir/AuthKey_TESTKEY.p8" \
  TESTKEY \
  'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' \
  "$work_dir/invalid-result.json" \
  "$work_dir/invalid-log.json" >/dev/null 2>&1
invalid_id_exit=$?
set -e
test "$invalid_id_exit" -eq 64

release_workflow="$root_dir/.github/workflows/release.yml"
if grep -Fq 'prerelease=()' "$release_workflow" || grep -Fq 'prerelease[@]' "$release_workflow"; then
  echo 'Release workflow must not expand an empty prerelease array under Bash set -u.' >&2
  exit 1
fi
grep -Fq 'gh release create "$RELEASE_TAG" "${assets[@]}" --verify-tag --generate-notes --prerelease' "$release_workflow"
grep -Fq 'gh release create "$RELEASE_TAG" "${assets[@]}" --verify-tag --generate-notes' "$release_workflow"

echo 'Notarization workflow shell tests passed.'
