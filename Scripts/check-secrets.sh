#!/bin/bash
set -euo pipefail

patterns='(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{20,})'

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git grep -IEn "$patterns" -- . ':!Scripts/check-secrets.sh'; then
    echo "Potential committed secret detected." >&2
    exit 1
  fi
else
  if rg -n --hidden --glob '!Scripts/check-secrets.sh' --glob '!.git/**' "$patterns" .; then
    echo "Potential secret detected." >&2
    exit 1
  fi
fi

for extension in p12 p8 mobileprovision; do
  if find . -type f -name "*.$extension" -not -path './.git/*' | grep -q .; then
    echo "Signing credential file (*.$extension) must not be committed." >&2
    exit 1
  fi
done

echo "Secret scan passed."
