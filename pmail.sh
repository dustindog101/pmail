#!/usr/bin/env bash
# pmail — CLI wrapper around protonmail-api-client
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION="${PMAIL_SESSION:-$ROOT/session.pickle}"
LAST_LIST="$ROOT/.last_list.json"
EXPECTED_MAIL="web-mail@5.0.134.7"
EXPECTED_ACCOUNT="web-account@5.0.423.0"

usage() {
  cat <<'HELP'
pmail — Proton Mail CLI (wraps protonmail-api-client)

Usage:
  pmail login -u <email>     Log in (password via getpass; optional 2FA)
  pmail ls [-n N]            List newest N messages (default 20)
  pmail read <index>         Read message by index from last ls
  pmail help                 Show this help

Session file: ./session.pickle (override with PMAIL_SESSION)
HELP
}

ensure_venv() {
  if [[ ! -x "$ROOT/.venv/bin/python" ]]; then
    echo "error: venv missing; run 'uv sync' in $ROOT first" >&2
    exit 1
  fi
}

# Re-apply version header patch if stale (wiped by fresh uv sync).
ensure_patch() {
  ensure_venv
  local mail account
  mail="$("$ROOT/.venv/bin/python" -c "import protonmail.constants as c; print(c.PM_APP_VERSION_MAIL)" 2>/dev/null || echo "")"
  account="$("$ROOT/.venv/bin/python" -c "import protonmail.constants as c; print(getattr(c,'PM_APP_VERSION_ACCOUNT',''))" 2>/dev/null || echo "")"
  if [[ "$mail" != "$EXPECTED_MAIL" || "$account" != "$EXPECTED_ACCOUNT" ]]; then
    echo "pmail: app-version headers stale (mail=$mail account=$account); re-applying patch…" >&2
    "$ROOT/scripts/apply-version-patch.sh"
  fi
}

cmd_login() {
  local email=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u|--user|--username)
        email="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        echo "error: unknown login arg: $1" >&2
        usage >&2
        return 1
        ;;
    esac
  done
  if [[ -z "$email" ]]; then
    echo "error: login requires -u <email>" >&2
    return 1
  fi
  ensure_patch
  SESSION="$SESSION" EMAIL="$email" uv run --directory "$ROOT" python - <<'PY'
import getpass, os, sys
from protonmail import ProtonMail

email = os.environ["EMAIL"]
session_path = os.environ["SESSION"]
password = os.environ.get("PMAIL_PASSWORD") or getpass.getpass("Proton password: ")
if not password:
    print("error: empty password", file=sys.stderr)
    sys.exit(1)

def getter_2fa_code():
    # Prompted by the library only when 2FA is required.
    return input("2FA code: ").strip()

proton = ProtonMail()
print("Logging in…", file=sys.stderr)
proton.login(email, password, getter_2fa_code=getter_2fa_code)
proton.save_session(session_path)
# Enable auto_save for token refresh on later load_session calls.
proton._session_path = session_path
proton._session_auto_save = True
print(f"Session saved to {session_path} (auto_save enabled)", file=sys.stderr)
PY
}

cmd_ls() {
  local n=20
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n)
        n="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        echo "error: unknown ls arg: $1" >&2
        return 1
        ;;
    esac
  done
  if ! [[ "$n" =~ ^[0-9]+$ ]] || [[ "$n" -lt 1 ]]; then
    echo "error: -n must be a positive integer" >&2
    return 1
  fi
  ensure_patch
  if [[ ! -f "$SESSION" ]]; then
    echo "error: no session at $SESSION — run: pmail login -u <email>" >&2
    return 1
  fi
  SESSION="$SESSION" LAST_LIST="$LAST_LIST" N="$n" uv run --directory "$ROOT" python - <<'PY'
import json, os, sys
from datetime import datetime, timezone
from protonmail import ProtonMail

session_path = os.environ["SESSION"]
last_list_path = os.environ["LAST_LIST"]
n = int(os.environ["N"])
page_size = min(n, 150)

proton = ProtonMail()
proton.load_session(session_path, auto_save=True)
messages = proton.get_messages_by_page(0, page_size=page_size)[:n]

# Persist ids for `pmail read <index>`
cache = [{"id": m.id, "subject": m.subject} for m in messages]
with open(last_list_path, "w", encoding="utf-8") as f:
    json.dump(cache, f, indent=2)

def fmt_time(ts: int) -> str:
    if not ts:
        return "?"
    return datetime.fromtimestamp(ts, tz=timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M")

def fmt_sender(s) -> str:
    name = (getattr(s, "name", None) or "").strip()
    addr = (getattr(s, "address", None) or "").strip()
    if name and addr:
        return f"{name} <{addr}>"
    return name or addr or "?"

for i, m in enumerate(messages):
    unread = "U" if m.unread else " "
    print(f"{i:3d}  {fmt_time(m.time):16s}  [{unread}]  {fmt_sender(m.sender):40s}  {m.subject}")
PY
}

cmd_read() {
  if [[ $# -lt 1 ]]; then
    echo "error: read requires <index>" >&2
    return 1
  fi
  local index="$1"
  if ! [[ "$index" =~ ^[0-9]+$ ]]; then
    echo "error: index must be a non-negative integer" >&2
    return 1
  fi
  ensure_patch
  if [[ ! -f "$SESSION" ]]; then
    echo "error: no session at $SESSION — run: pmail login -u <email>" >&2
    return 1
  fi
  SESSION="$SESSION" LAST_LIST="$LAST_LIST" INDEX="$index" uv run --directory "$ROOT" python - <<'PY'
import json, os, re, sys
from datetime import datetime, timezone
from protonmail import ProtonMail

session_path = os.environ["SESSION"]
last_list_path = os.environ["LAST_LIST"]
index = int(os.environ["INDEX"])

proton = ProtonMail()
proton.load_session(session_path, auto_save=True)

msg_id = None
if os.path.isfile(last_list_path):
    with open(last_list_path, encoding="utf-8") as f:
        cache = json.load(f)
    if 0 <= index < len(cache):
        msg_id = cache[index]["id"]

if msg_id is None:
    # Fallback: refetch first page (default width 20, or enough to cover index)
    page_size = min(max(index + 1, 20), 150)
    messages = proton.get_messages_by_page(0, page_size=page_size)
    if index >= len(messages):
        print(f"error: index {index} out of range (have {len(messages)})", file=sys.stderr)
        sys.exit(1)
    msg_id = messages[index].id
    cache = [{"id": m.id, "subject": m.subject} for m in messages]
    with open(last_list_path, "w", encoding="utf-8") as f:
        json.dump(cache, f, indent=2)

message = proton.read_message(msg_id, mark_as_read=False)

def fmt_time(ts: int) -> str:
    if not ts:
        return "?"
    return datetime.fromtimestamp(ts, tz=timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M %Z")

def fmt_sender(s) -> str:
    name = (getattr(s, "name", None) or "").strip()
    addr = (getattr(s, "address", None) or "").strip()
    if name and addr:
        return f"{name} <{addr}>"
    return name or addr or "?"

def strip_html(html: str) -> str:
    text = re.sub(r"(?is)<(script|style).*?>.*?</\1>", "", html or "")
    text = re.sub(r"(?i)<br\s*/?>", "\n", text)
    text = re.sub(r"(?i)</p>", "\n\n", text)
    text = re.sub(r"(?i)</div>", "\n", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()

print(f"From:    {fmt_sender(message.sender)}")
print(f"Subject: {message.subject}")
print(f"Date:    {fmt_time(message.time)}")
print(f"Unread:  {message.unread}")
print("-" * 60)
print(strip_html(message.body))
PY
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi
  local cmd="$1"
  shift
  case "$cmd" in
    login) cmd_login "$@" ;;
    ls|list) cmd_ls "$@" ;;
    read) cmd_read "$@" ;;
    help|-h|--help) usage ;;
    *)
      echo "error: unknown command: $cmd" >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
