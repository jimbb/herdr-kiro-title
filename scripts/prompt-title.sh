#!/usr/bin/env bash
# Kiro UserPromptSubmit hook entrypoint (installed by this plugin).
# Receives the hook payload JSON on stdin, extracts the prompt, and titles the
# current Herdr pane. Non-blocking: heavy work is backgrounded, always exits 0.
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0

payload="$(cat 2>/dev/null)"

prompt="$(printf '%s' "$payload" | python3 - <<'PY' 2>/dev/null
import sys, json
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
if isinstance(d, str): print(d); sys.exit(0)
if isinstance(d, dict):
    for k in ("prompt","userPrompt","user_prompt","input","message","text","content"):
        v = d.get(k)
        if isinstance(v, str) and v.strip(): print(v); sys.exit(0)
    for v in d.values():
        if isinstance(v, dict):
            for kk in ("prompt","userPrompt","text","message","content"):
                vv = v.get(kk)
                if isinstance(vv, str) and vv.strip(): print(vv); sys.exit(0)
PY
)"
[ -n "$prompt" ] || prompt="$payload"
prompt="$(printf '%s' "$prompt" | tr '\n\t' '  ' | sed 's/  */ /g; s/^ //; s/ $//')"
[ -n "$prompt" ] || exit 0

(
  repo="$(pane_repo "$HERDR_PANE_ID")"
  [ -n "$repo" ] || repo="$(basename "$PWD")"
  title="$(summarize "$prompt" "$repo")"
  herdr="$(herdr_bin)"
  [ -n "$title" ] && [ -n "$herdr" ] && \
    "$herdr" pane report-metadata "$HERDR_PANE_ID" \
      --source "${KIRO_TITLE_SOURCE:-kiro-title}" \
      --title "$title" --ttl-ms 86400000 >/dev/null 2>&1
) >/dev/null 2>&1 &

exit 0
