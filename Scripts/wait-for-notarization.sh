#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "Usage: $0 SUBMISSION_ID KEY_PATH KEY_ID ISSUER_ID RESULT_PATH LOG_PATH" >&2
  exit 64
fi

submission_id=$1
key_path=$2
key_id=$3
issuer_id=$4
result_path=$5
log_path=$6

poll_interval=${NOTARY_POLL_INTERVAL_SECONDS:-120}
wait_timeout=${NOTARY_WAIT_TIMEOUT_SECONDS:-18000}
max_transient_failures=${NOTARY_MAX_TRANSIENT_FAILURES:-5}

if [[ ! "$submission_id" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
  echo "Invalid notarization submission ID." >&2
  exit 64
fi

for numeric_value in "$poll_interval" "$wait_timeout" "$max_transient_failures"; do
  if [[ ! "$numeric_value" =~ ^[1-9][0-9]*$ ]]; then
    echo "Notarization polling values must be positive integers." >&2
    exit 64
  fi
done

if [[ ! -f "$key_path" ]]; then
  echo "Notarization API key is missing." >&2
  exit 66
fi

mkdir -p "$(dirname "$result_path")" "$(dirname "$log_path")"

temporary_result="${result_path}.tmp"
temporary_error="${result_path}.error"
trap 'rm -f "$temporary_result" "$temporary_error"' EXIT

started_at=$(date +%s)
deadline=$((started_at + wait_timeout))
attempt=0
transient_failures=0

while true; do
  attempt=$((attempt + 1))

  if xcrun notarytool info "$submission_id" \
    --key "$key_path" \
    --key-id "$key_id" \
    --issuer "$issuer_id" \
    --output-format json > "$temporary_result" 2> "$temporary_error"; then
    status=$(/usr/bin/plutil -extract status raw -o - "$temporary_result")
    mv "$temporary_result" "$result_path"
    transient_failures=0
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    echo "$timestamp Apple notarization $submission_id: $status (poll $attempt)"

    case "$status" in
      Accepted)
        log_attempt=0
        while true; do
          log_attempt=$((log_attempt + 1))
          if xcrun notarytool log "$submission_id" \
            --key "$key_path" \
            --key-id "$key_id" \
            --issuer "$issuer_id" > "$log_path"; then
            echo "Apple notarization accepted; notary log downloaded."
            exit 0
          fi

          if (( log_attempt >= max_transient_failures )); then
            echo "Notarization was accepted, but its log could not be downloaded after $log_attempt attempts." >&2
            exit 69
          fi
          sleep 10
        done
        ;;
      Invalid|Rejected)
        xcrun notarytool log "$submission_id" \
          --key "$key_path" \
          --key-id "$key_id" \
          --issuer "$issuer_id" > "$log_path" 2>/dev/null || true
        echo "Apple rejected notarization submission $submission_id with status $status." >&2
        exit 65
        ;;
      "In Progress")
        ;;
      *)
        echo "Unexpected Apple notarization status: $status" >&2
        exit 65
        ;;
    esac
  else
    transient_failures=$((transient_failures + 1))
    echo "Transient notarization status check failure $transient_failures/$max_transient_failures; retrying." >&2
    if (( transient_failures >= max_transient_failures )); then
      echo "Apple notarization status could not be queried after repeated attempts." >&2
      exit 69
    fi
  fi

  now=$(date +%s)
  if (( now >= deadline )); then
    echo "Notarization is still in progress after $wait_timeout seconds. The signed DMG and submission metadata remain available as private workflow artifacts; resume this same submission instead of uploading it again." >&2
    exit 75
  fi

  remaining=$((deadline - now))
  sleep_for=$poll_interval
  if (( sleep_for > remaining )); then sleep_for=$remaining; fi
  sleep "$sleep_for"
done
