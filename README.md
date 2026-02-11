# cl-statusbar

A custom status line for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows model info, context usage, session duration, and Pro/Max plan rate limits — all in your terminal.

## Example output

**Pro plan:**
```
ctx ━━━━━━╌╌╌╌╌╌ 48%  ·  ⏱ 12m 34s  ·  5h ━━━━━━━━╌╌╌╌ 65% ↻ 18:00 (2h 40m)  ·  7d ━━━╌╌╌╌╌╌╌╌╌ 28% ↻ Feb 18 (3d 5h)
◆ Claude Opus 4.6  ▸ my-project  ⎇ main  ·  Pro
```

**Max plan (per-model 7d limits):**
```
ctx ━━━━━━━━━╌╌╌ 72%  ·  ⏱ 45m 10s  ·  5h ━━━━╌╌╌╌╌╌╌╌ 30% ↻ 14:20 (1h 15m)  ·  opus ━━━━━━╌╌╌╌╌╌ 50% ↻ Feb 15 (2d 8h)  ·  sonnet ━━╌╌╌╌╌╌╌╌╌╌ 18% ↻ Feb 16 (3d 1h)
◆ Claude Opus 4.6  ▸ cl-statusbar  ⎇ feature/docs  ·  Max
```

**API usage (no Pro/Max plan):**
```
ctx ━━╌╌╌╌╌╌╌╌╌╌ 15%  ·  ⏱ 3m 22s  ·  $0.0842
◆ Claude Sonnet 4.5  ▸ my-app  ⎇ main  ·  API
```

## Features

- **Model & project info** — current model, project name, and git branch
- **Context window** — color-coded progress bar (green → yellow → red)
- **Session duration** — total time for the current session
- **Pro plan limits** — 5-hour and 7-day usage bars with reset countdown
- **Max plan limits** — 5-hour bar plus per-model (Opus/Sonnet) 7-day bars
- **API cost** — total USD cost when not on a Pro/Max plan
- **Usage caching** — API responses cached for 2 minutes to stay fast

## Requirements

- `jq`
- `python3`
- `curl`
- macOS (uses `security` keychain for OAuth token)

## Install

```sh
git clone https://github.com/billp/cl-statusbar.git
cd cl-statusbar
bash install.sh
```

This copies `statusline.sh` to `~/.claude/` and configures `settings.json` automatically.

## Uninstall

```sh
bash uninstall.sh
```

Removes `~/.claude/statusline.sh`, cleans the `statusLine` key from `settings.json` (preserving all other settings), and deletes the usage cache.

## How it works

Claude Code pipes a JSON object to the status line command on each render. The script parses it for model name, context window percentage, session duration, and working directory. It then fetches rate-limit data from the Anthropic OAuth usage API (cached to `/tmp/claude-statusline-usage.json`) and renders two lines of color-coded output.
