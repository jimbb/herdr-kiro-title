#!/usr/bin/env bash
# Event hook for `pane.agent_status_changed`.
# Herdr delivers the event payload as JSON on stdin. We act only when a Kiro
# pane enters the `working` state and does not already carry a title.
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

# Self-heal: ensure the Kiro UserPromptSubmit hook is installed. The plugin's
# `startup` command may not have run yet (it fires at server start, not link),
# so we idempotently install here on the first event we see.
HOOK_FILE="${KIRO_HOOKS_DIR:-$HOME/.kiro/hooks}/kiro-title.json"
if [ ! -f "$HOOK_FILE" ]; then
  HERDR_PLUGIN_ROOT="${HERDR_PLUGIN_ROOT:-$DIR/..}" bash "$DIR/install-kiro-hook.sh" >/dev/null 2>&1 || true
fi

# Event payload: Herdr provides it via HERDR_PLUGIN_EVENT_JSON (and on stdin).
payload="${HERDR_PLUGIN_EVENT_JSON:-}"
[ -n "$payload" ] || payload="$(cat 2>/dev/null)"
[ -n "$payload" ] || exit 0

read_field() {
  printf '%s' "$payload" | python3 - "$1" <<'PY' 2>/dev/null
import sys, json
key = sys.argv[1]
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
# Payload may be the event object directly or wrapped under a data/event key.
for obj in (d, d.get("data") if isinstance(d, dict) else None,
            d.get("event") if isinstance(d, dict) else None):
    if isinstance(obj, dict) and key in obj and obj[key] is not None:
        print(obj[key]); sys.exit(0)
PY
}

AGENT="$(read_field agent)"
STATUS="$(read_field agent_status)"
PANE="$(read_field pane_id)"
TITLE="$(read_field title)"

[ "$AGENT" = "kiro" ] || exit 0
[ "$STATUS" = "working" ] || exit 0
[ -n "$PANE" ] || exit 0
# If a title is already set by us or the agent, don't thrash on every turn.
# (Remove this guard if you want the title refreshed on every new turn.)
[ -z "$TITLE" ] || exit 0

# Background the slow model call so the event handler returns immediately.
( title_pane "$PANE" ) >/dev/null 2>&1 &
exit 0
