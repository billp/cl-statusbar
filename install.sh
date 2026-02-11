#!/usr/bin/env bash
set -euo pipefail

# ── 1. Check dependencies ────────────────────────────────────────────
missing=()
for cmd in jq python3 curl; do
  if ! command -v "$cmd" &>/dev/null; then
    missing+=("$cmd")
  fi
done
if (( ${#missing[@]} > 0 )); then
  echo "Error: missing required dependencies: ${missing[*]}" >&2
  echo "Please install them and re-run this script." >&2
  exit 1
fi

# ── 2. Resolve source ────────────────────────────────────────────────
REPO_URL="https://raw.githubusercontent.com/billp/cl-statusbar/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || true
SOURCE_FILE="${SCRIPT_DIR:+$SCRIPT_DIR/statusline.sh}"

# ── 3. Create ~/.claude/ if needed ───────────────────────────────────
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR"

# ── 4. Install statusline.sh ─────────────────────────────────────────
DEST_FILE="$CLAUDE_DIR/statusline.sh"

if [[ -n "$SOURCE_FILE" && -f "$SOURCE_FILE" ]]; then
  # Local install
  if [[ -f "$DEST_FILE" ]] && diff -q "$SOURCE_FILE" "$DEST_FILE" &>/dev/null; then
    echo "statusline.sh is already up to date."
  else
    cp "$SOURCE_FILE" "$DEST_FILE"
    chmod +x "$DEST_FILE"
    echo "Installed statusline.sh → $DEST_FILE"
  fi
else
  # Remote install
  echo "Downloading statusline.sh from GitHub..."
  tmp_dl=$(mktemp "$CLAUDE_DIR/statusline.sh.XXXXXX")
  if ! curl -fsSL "$REPO_URL/statusline.sh" -o "$tmp_dl"; then
    rm -f "$tmp_dl"
    echo "Error: failed to download statusline.sh" >&2
    exit 1
  fi
  if [[ -f "$DEST_FILE" ]] && diff -q "$tmp_dl" "$DEST_FILE" &>/dev/null; then
    rm -f "$tmp_dl"
    echo "statusline.sh is already up to date."
  else
    chmod +x "$tmp_dl"
    mv "$tmp_dl" "$DEST_FILE"
    echo "Installed statusline.sh → $DEST_FILE"
  fi
fi

# ── 5. Configure settings.json ───────────────────────────────────────
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

if [[ -f "$SETTINGS_FILE" ]]; then
  existing=$(cat "$SETTINGS_FILE")
else
  existing='{}'
fi

new_settings=$(echo "$existing" | jq '.statusLine = {"type":"command","command":"~/.claude/statusline.sh","padding":0}')

tmp_file=$(mktemp "$CLAUDE_DIR/settings.json.XXXXXX")
echo "$new_settings" > "$tmp_file"
mv "$tmp_file" "$SETTINGS_FILE"
echo "Configured statusLine in $SETTINGS_FILE"

# ── 6. Done ──────────────────────────────────────────────────────────
echo ""
echo "Done!"
