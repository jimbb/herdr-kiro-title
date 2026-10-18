#!/usr/bin/env bash
# Installs a Kiro `UserPromptSubmit` hook that titles the current Herdr pane
# from the submitted prompt. Idempotent. Runs as the plugin's startup command.
#
# The installed hook calls this plugin's scripts/prompt-title.sh by absolute
# path, so the plugin remains the single source of logic.
set -u

PLUGIN_ROOT="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SCRIPT="$PLUGIN_ROOT/scripts/prompt-title.sh"

HOOKS_DIR="${KIRO_HOOKS_DIR:-$HOME/.kiro/hooks}"
HOOK_FILE="$HOOKS_DIR/kiro-title.json"

mkdir -p "$HOOKS_DIR" 2>/dev/null || { echo "cannot create $HOOKS_DIR" >&2; exit 0; }

cat >"$HOOK_FILE" <<JSON
{
  "version": "v1",
  "hooks": [
    {
      "name": "Herdr pane auto-title (kiro-title plugin)",
      "trigger": "UserPromptSubmit",
      "description": "Managed by the herdr kiro-title plugin. Publishes a short task summary as the Herdr pane title.",
      "action": {
        "type": "command",
        "command": "bash '$SCRIPT'",
        "timeout": 10
      }
    }
  ]
}
JSON

echo "installed Kiro hook -> $HOOK_FILE (calls $SCRIPT)"
