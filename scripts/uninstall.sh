#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
DEST_FILE="$CLAUDE_DIR/statusline.sh"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
CACHE_FILE="/tmp/claude-statusline-usage.json"

# ── 1. Remove statusline.sh ─────────────────────────────────────────
if [[ -f "$DEST_FILE" ]]; then
  rm "$DEST_FILE"
  echo "Removed $DEST_FILE"
else
  echo "statusline.sh was not installed, skipping."
fi

# ── 2. Remove statusLine key from settings.json ─────────────────────
if [[ -f "$SETTINGS_FILE" ]]; then
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required to update settings.json" >&2
    exit 1
  fi

  if jq -e '.statusLine' "$SETTINGS_FILE" &>/dev/null; then
    new_settings=$(jq 'del(.statusLine)' "$SETTINGS_FILE")
    tmp_file=$(mktemp "$CLAUDE_DIR/settings.json.XXXXXX")
    echo "$new_settings" > "$tmp_file"
    mv "$tmp_file" "$SETTINGS_FILE"
    echo "Removed statusLine from $SETTINGS_FILE"
  else
    echo "No statusLine key in settings.json, skipping."
  fi
fi

# ── 3. Remove usage cache ───────────────────────────────────────────
if [[ -f "$CACHE_FILE" ]]; then
  rm "$CACHE_FILE"
  echo "Removed usage cache $CACHE_FILE"
fi

# ── 4. Done ──────────────────────────────────────────────────────────
echo ""
echo "Done!"
