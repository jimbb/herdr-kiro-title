# herdr-kiro-title

A [Herdr](https://herdr.dev) plugin that auto-titles **Kiro CLI** panes with a
short, model-written summary of the current task — bringing Kiro to parity with
`codex`, `grok`, and the other agents whose panes show a descriptive title
instead of the raw shell prompt.

| Before | After |
| --- | --- |
| `jimmy@herdr: ~/projects` | `Add pagination to users API \| myrepo` |

## Why

Herdr recognizes Kiro as an agent (state detection works), but Kiro never emits
a per-task terminal title, so its tab/pane label stays at the shell default.
This plugin watches for a Kiro pane entering the `working` state, reads the
latest user prompt from the pane, summarizes it with a cheap model, and sets the
pane title via Herdr's `pane report-metadata` API. No Kiro-side changes and no
patched Kiro binary required.

## Install

```bash
herdr plugin install jimbb/herdr-kiro-title
```

Or develop locally:

```bash
git clone https://github.com/jimbb/herdr-kiro-title
herdr plugin link ./herdr-kiro-title
```

Verify:

```bash
herdr plugin list
```

## How it works

The plugin installs a Kiro **`UserPromptSubmit` hook** (its primary, reliable
signal — the submitted prompt is handed to the hook directly, which is far more
robust than scraping a busy pane). The hook summarizes the prompt and sets the
title via Herdr's metadata API:

```
herdr pane report-metadata <pane> --source kiro-title --title "<summary> | <repo>"
```

Pieces:

- `herdr-plugin.toml` — declares a `startup` installer, a `retitle` action, and
  a `pane.agent_status_changed` fallback event.
- `scripts/install-kiro-hook.sh` — runs on link/enable; writes
  `~/.kiro/hooks/kiro-title.json` pointing at `scripts/prompt-title.sh`.
- `scripts/prompt-title.sh` — the Kiro hook entrypoint: extracts the prompt,
  summarizes, titles the pane.
- `scripts/on-agent-status.sh` — fallback for panes that started before the
  hook existed: on a Kiro pane entering `working` with no title, scrape the
  transcript and title it (best-effort).
- `scripts/lib.sh` — shared summarizer + helpers.

> The installed Kiro hook takes effect on the **next** Kiro session start in a
> pane. Already-running panes are covered by the fallback action/event.

## Uninstall

```bash
herdr plugin uninstall jimbb/herdr-kiro-title
rm -f ~/.kiro/hooks/kiro-title.json
```

## Configuration

Set via environment (e.g. in your shell profile):

| Variable | Default | Meaning |
| --- | --- | --- |
| `KIRO_TITLE_MODEL` | `qwen3-coder-next` | Model used for the summary (cheap/fast recommended). |
| `KIRO_TITLE_TIMEOUT` | `20` | Seconds before the model call is abandoned (falls back to prompt text). |
| `KIRO_TITLE_NO_MODEL` | `0` | Set `1` to skip the model entirely and title from the prompt text (free/instant). |
| `KIRO_TITLE_SOURCE` | `kiro-title` | `report-metadata --source` id used for the title layer. |

To make titling free and instant, set `KIRO_TITLE_NO_MODEL=1`.

## Requirements

- Herdr ≥ 0.9.0 with the plugin system (`herdr plugin ...`).
- `kiro-cli` on `PATH` (for the model-generated summary; optional if
  `KIRO_TITLE_NO_MODEL=1`).
- `python3`, `bash`, `git`.
- Linux or macOS.

## Notes & limitations

- Prompt extraction is heuristic (it scrapes the pane transcript). If Kiro's TUI
  layout changes, the regex in `scripts/lib.sh` may need updating.
- The event handler only sets a title when none exists, to avoid re-summarizing
  on every turn. Remove the `[ -z "$TITLE" ]` guard in `on-agent-status.sh` to
  refresh on each turn.
- Model summaries cost a small amount per titled pane. Use `KIRO_TITLE_NO_MODEL=1`
  to avoid that.

## License

MIT — see [LICENSE](LICENSE).
