#!/usr/bin/env bash
# lib.sh — shared logic for the herdr-kiro-title plugin.
#
# Given a Herdr pane id that currently hosts a Kiro agent, read the pane's
# recent output, extract the latest user prompt, summarize it (model-written,
# with a deterministic fallback), and publish it as the pane title via
# `herdr pane report-metadata`.
#
# All functions are defensive: any failure degrades to the fallback or a no-op.
# Nothing here should ever return non-zero in a way that fails a Herdr event.

set -u

# Config via env (override in your shell or plugin config):
#   KIRO_TITLE_MODEL     model for the summarizer (default: qwen3-coder-next)
#   KIRO_TITLE_TIMEOUT   seconds for the model call (default: 20)
#   KIRO_TITLE_SOURCE    report-metadata source id (default: kiro-title)
#   KIRO_TITLE_NO_MODEL  if set to 1, skip the model and use the prompt verbatim
KIRO_TITLE_MODEL="${KIRO_TITLE_MODEL:-qwen3-coder-next}"
KIRO_TITLE_TIMEOUT="${KIRO_TITLE_TIMEOUT:-20}"
KIRO_TITLE_SOURCE="${KIRO_TITLE_SOURCE:-kiro-title}"
KIRO_TITLE_NO_MODEL="${KIRO_TITLE_NO_MODEL:-0}"

herdr_bin() {
  if [ -n "${HERDR_BIN_PATH:-}" ] && command -v "$HERDR_BIN_PATH" >/dev/null 2>&1; then
    printf '%s' "$HERDR_BIN_PATH"
  else
    command -v herdr 2>/dev/null
  fi
}

kiro_bin() {
  if [ -n "${KIRO_CHAT_CLI_BIN:-}" ] && { [ -x "$KIRO_CHAT_CLI_BIN" ] || command -v "$KIRO_CHAT_CLI_BIN" >/dev/null 2>&1; }; then
    printf '%s' "$KIRO_CHAT_CLI_BIN"
  else
    command -v kiro-cli 2>/dev/null
  fi
}

# Read the latest user prompt out of a pane's recent transcript.
# Heuristic: Kiro renders user input after a prompt marker ("> " / "› ").
# We take the last non-empty, non-UI line following such a marker, falling
# back to the last substantial line in the buffer.
extract_latest_prompt() {
  local pane_id="$1" herdr buf
  herdr="$(herdr_bin)"; [ -n "$herdr" ] || return 0
  buf="$("$herdr" agent read "$pane_id" --source recent-unwrapped --lines 200 2>/dev/null)"
  [ -n "$buf" ] || buf="$("$herdr" pane read "$pane_id" --source recent-unwrapped --lines 200 2>/dev/null)"
  [ -n "$buf" ] || return 0
  printf '%s' "$buf" | python3 - <<'PY' 2>/dev/null
import sys, re
lines = sys.stdin.read().splitlines()
# Strip ANSI and box-drawing noise.
ansi = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]')
def clean(s): return ansi.sub('', s).rstrip()
cleaned = [clean(l) for l in lines]
cand = None
prompt_marker = re.compile(r'^\s*[>›❯]\s+(.*\S.*)$')
ui_noise = re.compile(r'(ask a question|describe a task|to scroll|shortcuts|esc to|enter ↵|^[-─=│┌┐└┘╭╮╰╯ ]+$)', re.I)
for l in cleaned:
    m = prompt_marker.match(l)
    if m:
        t = m.group(1).strip()
        if t and not ui_noise.search(t):
            cand = t
# Fallback: last substantial non-noise line.
if not cand:
    for l in reversed(cleaned):
        t = l.strip()
        if len(t) >= 8 and not ui_noise.search(t):
            cand = t; break
if cand:
    print(cand[:400])
PY
}

# Produce a short title from a prompt string.
summarize() {
  local prompt="$1" repo="$2" kiro summary fallback raw
  prompt="$(printf '%s' "$prompt" | tr '\n\t' '  ' | sed 's/  */ /g; s/^ //; s/ $//')"
  [ -n "$prompt" ] || return 0
  fallback="$(printf '%s' "$prompt" | cut -c1-48)"
  [ "${#prompt}" -gt 48 ] && fallback="${fallback%% *}…"

  summary=""
  if [ "$KIRO_TITLE_NO_MODEL" != "1" ]; then
    kiro="$(kiro_bin)"
    if [ -n "$kiro" ]; then
      local instr="Summarize this coding request as a terminal tab title: 5 words max, imperative, no quotes, no trailing punctuation, plain text only. Request: ${prompt}"
      raw="$(timeout "$KIRO_TITLE_TIMEOUT" "$kiro" chat --no-interactive --trust-tools= --model "$KIRO_TITLE_MODEL" "$instr" 2>/dev/null)"
      summary="$(printf '%s' "$raw" | tr -d '\r' | grep -v '^[[:space:]]*$' | tail -n 1 \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^["'\''`]*//; s/["'\''`.]*$//')"
    fi
  fi
  case "$summary" in ""|*[![:print:]]*) summary="$fallback" ;; esac
  if [ "${#summary}" -gt 60 ] || [ "${#summary}" -lt 2 ]; then summary="$fallback"; fi

  if [ -n "$repo" ]; then printf '%s | %s' "$summary" "$repo"; else printf '%s' "$summary"; fi
}

# Resolve the repo/dir name for a pane from its cwd (best effort).
pane_repo() {
  local pane_id="$1" herdr cwd
  herdr="$(herdr_bin)"; [ -n "$herdr" ] || return 0
  cwd="$("$herdr" pane list 2>/dev/null | python3 - "$pane_id" <<'PY' 2>/dev/null
import sys, json
pid = sys.argv[1]
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
for p in d.get("result", {}).get("panes", []):
    if p.get("pane_id") == pid:
        print(p.get("cwd") or ""); break
PY
)"
  [ -n "$cwd" ] || return 0
  if command -v git >/dev/null 2>&1; then
    local top
    top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
    [ -n "$top" ] && { basename "$top"; return 0; }
  fi
  basename "$cwd"
}

# Full pipeline: title a pane from its latest prompt.
title_pane() {
  local pane_id="$1" herdr prompt repo title
  herdr="$(herdr_bin)"; [ -n "$herdr" ] || return 0
  prompt="$(extract_latest_prompt "$pane_id")"
  [ -n "$prompt" ] || return 0
  repo="$(pane_repo "$pane_id")"
  title="$(summarize "$prompt" "$repo")"
  [ -n "$title" ] || return 0
  "$herdr" pane report-metadata "$pane_id" \
    --source "$KIRO_TITLE_SOURCE" \
    --title "$title" \
    --ttl-ms 86400000 >/dev/null 2>&1 || true
}
