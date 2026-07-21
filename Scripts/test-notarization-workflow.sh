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
appcast_script="$root_dir/Scripts/generate-sparkle-appcast.sh"
test -x "$appcast_script"
if grep -Fq 'prerelease=()' "$release_workflow" || grep -Fq 'prerelease[@]' "$release_workflow"; then
  echo 'Release workflow must not expand an empty prerelease array under Bash set -u.' >&2
  exit 1
fi
grep -Fq 'printf '\''%s  %s\n'\'' "$dmg_sha" "$(basename "$dmg")" > "$dmg.sha256"' "$release_workflow"
grep -Fq 'gh release create "$RELEASE_TAG" --verify-tag --generate-notes --draft --prerelease' "$release_workflow"
grep -Fq 'gh release create "$RELEASE_TAG" --verify-tag --generate-notes --draft' "$release_workflow"
grep -Fq 'gh release upload "$RELEASE_TAG" "${assets[@]}"' "$release_workflow"
grep -Fq 'gh release edit "$RELEASE_TAG" --draft=false --prerelease=true' "$release_workflow"
grep -Fq 'gh release edit "$RELEASE_TAG" --draft=false --prerelease=false --latest' "$release_workflow"
grep -Fq 'published_sha=$(gh release download "$RELEASE_TAG" --pattern "$checksum_asset" --output -' "$release_workflow"
grep -Fq 'Published release checksum does not match the verified DMG; refusing to mutate the release.' "$release_workflow"
grep -Fq 'SPARKLE_EDDSA_PRIVATE_KEY_BASE64' "$release_workflow"
grep -Fq 'bash Scripts/generate-sparkle-appcast.sh' "$release_workflow"
grep -Fq 'assets+=("$DIST_PATH/appcast.xml")' "$release_workflow"
grep -Fq 'required_assets+=(appcast.xml)' "$release_workflow"
grep -Fq 'auto_updates true' "$root_dir/packaging/homebrew/yeelightbar.rb.template"

release_create_line=$(grep -nF 'gh release create "$RELEASE_TAG" --verify-tag --generate-notes --draft' "$release_workflow" | tail -n1 | cut -d: -f1)
release_upload_line=$(grep -nF 'gh release upload "$RELEASE_TAG" "${assets[@]}"' "$release_workflow" | tail -n1 | cut -d: -f1)
release_publish_line=$(grep -nF 'gh release edit "$RELEASE_TAG" --draft=false --prerelease=false --latest' "$release_workflow" | cut -d: -f1)
test -n "$release_create_line"
test -n "$release_upload_line"
test -n "$release_publish_line"
test "$release_create_line" -lt "$release_upload_line"
test "$release_upload_line" -lt "$release_publish_line"

homebrew_auth_line=$(grep -nF 'gh auth setup-git' "$release_workflow" | cut -d: -f1)
homebrew_clone_line=$(grep -nF 'gh repo clone bekircem/homebrew-yeelightbar' "$release_workflow" | cut -d: -f1)
test -n "$homebrew_auth_line"
test -n "$homebrew_clone_line"
test "$homebrew_auth_line" -lt "$homebrew_clone_line"

echo 'Notarization workflow shell tests passed.'
