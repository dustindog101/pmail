#!/usr/bin/env bash
# Patch installed protonmail.constants so Proton API accepts x-pm-appversion
# (error 5003 / "App version bad" when the header is outdated).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -x "$ROOT/.venv/bin/python" ]]; then
  echo "error: venv missing; run 'uv sync' in $ROOT first" >&2
  exit 1
fi

CONSTANTS="$("$ROOT/.venv/bin/python" -c "import protonmail.constants as c; print(c.__file__)")"
if [[ ! -f "$CONSTANTS" ]]; then
  echo "error: could not locate protonmail.constants" >&2
  exit 1
fi

# Replace whatever older versions are present (incl. 5.0.255.0 / 5.0.66.5).
# Portable in-place sed (BSD on macOS needs an empty suffix; GNU does not).
if [[ "$(uname -s)" == "Darwin" ]]; then
  sed -i '' -E "s/web-account@[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/web-account@5.0.423.0/g" "$CONSTANTS"
  sed -i '' -E "s/web-mail@[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/web-mail@5.0.134.7/g" "$CONSTANTS"
else
  sed -i -E "s/web-account@[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/web-account@5.0.423.0/g" "$CONSTANTS"
  sed -i -E "s/web-mail@[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/web-mail@5.0.134.7/g" "$CONSTANTS"
fi

echo "Patched: $CONSTANTS"
grep -n 'PM_APP_VERSION' "$CONSTANTS" || true
