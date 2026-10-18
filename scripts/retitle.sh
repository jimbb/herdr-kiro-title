#!/usr/bin/env bash
# Manual action: retitle a Kiro pane on demand.
# Targets $HERDR_PANE_ID when present, else the focused pane. Accepts an
# optional explicit pane id as $1.
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

herdr="$(herdr_bin)"; [ -n "$herdr" ] || { echo "herdr not found" >&2; exit 1; }

PANE="${1:-${HERDR_PANE_ID:-}}"
if [ -z "$PANE" ]; then
  PANE="$("$herdr" pane current 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["pane"]["pane_id"])' 2>/dev/null)"
fi
[ -n "$PANE" ] || { echo "no target pane" >&2; exit 1; }

title_pane "$PANE"
echo "retitled $PANE"
