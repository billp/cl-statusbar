#!/usr/bin/env bash
# Claude Code Status Line — Pro & Max Plan Usage Limits
set -euo pipefail

# ── 1. Parse stdin JSON ──────────────────────────────────────────────
INPUT="$(cat)"
MODEL=$(echo "$INPUT" | jq -r '.model.display_name // empty')
CTX_PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0')
DURATION_MS=$(echo "$INPUT" | jq -r '.cost.total_duration_ms // 0')
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
COST_USD=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // empty')

# ── 2. Git branch ───────────────────────────────────────────────────
BRANCH=""
if git -C "$CWD" rev-parse --git-dir &>/dev/null; then
  BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || true)
fi

# ── 3. Duration formatting ──────────────────────────────────────────
DURATION_S=$(( DURATION_MS / 1000 ))
DUR_H=$(( DURATION_S / 3600 ))
DUR_MIN=$(( (DURATION_S % 3600) / 60 ))
DUR_SEC=$(( DURATION_S % 60 ))
if (( DUR_H > 0 )); then
  DURATION_FMT="${DUR_H}h ${DUR_MIN}m"
else
  DURATION_FMT="${DUR_MIN}m $(printf '%02d' "$DUR_SEC")s"
fi

# ── 4. Project name ─────────────────────────────────────────────────
PROJECT=$(basename "$CWD")

# ── 5. Colors ────────────────────────────────────────────────────────
RST='\033[0m'
BOLD='\033[1m'
GREEN='\033[38;5;114m'
YELLOW='\033[38;5;221m'
RED='\033[38;5;203m'
CYAN='\033[38;5;116m'
WHITE='\033[38;5;250m'
GRAY='\033[38;5;242m'
LABEL='\033[38;5;242m'

color_for_pct() {
  local pct=$1
  if (( pct >= 80 )); then echo -ne "$RED"
  elif (( pct >= 50 )); then echo -ne "$YELLOW"
  else echo -ne "$GREEN"
  fi
}

# ── 6. Progress bar ─────────────────────────────────────────────────
progress_bar() {
  local pct=${1:-0}
  local width=${2:-15}
  local filled=$(( pct * width / 100 ))
  (( filled > width )) && filled=$width
  local empty=$(( width - filled ))
  local bar=""
  for (( i=0; i<filled; i++ )); do bar+="━"; done
  for (( i=0; i<empty; i++ )); do bar+="╌"; done
  echo -n "$bar"
}

SEP="${GRAY} · ${RST}"

# ── 7. Reset-time formatter ───────────────────────────────────────
# fmt_reset_info <iso_timestamp> <strftime_format>
#   e.g. fmt_reset_info "2025-02-15T03:00:00Z" "%H:%M"   → "18:00 (2h 40m)"
#   e.g. fmt_reset_info "2025-02-15T03:00:00Z" "%b %d"   → "Feb 15 (3d 5h)"
fmt_reset_info() {
  local iso_ts="$1" fmt="$2"
  [[ -z "$iso_ts" ]] && return 1
  python3 -c "
from datetime import datetime, timezone
try:
    r = datetime.fromisoformat('$iso_ts'.replace('Z','+00:00'))
    t = r.astimezone().strftime('$fmt')
    s = int((r - datetime.now(timezone.utc)).total_seconds())
    if s < 0: s = 0
    dy, s = s // 86400, s % 86400
    h, m = s // 3600, (s % 3600) // 60
    parts = []
    if dy: parts.append(f'{dy}d')
    if h: parts.append(f'{h}h')
    parts.append(f'{m}m')
    rem = ' '.join(parts)
    print(f'{t} ({rem})')
except: pass
" 2>/dev/null || true
}


# ── 8. Build Line 1 ─────────────────────────────────────────────────
# Col 1: model + project + branch
L1C1="${LABEL}◆${RST} ${GRAY}${MODEL}${RST}  ${LABEL}▸${RST} ${CYAN}${BOLD}${PROJECT}${RST}"
if [[ -n "$BRANCH" ]]; then
  L1C1+="  ${LABEL}⎇${RST} ${WHITE}${BRANCH}${RST}"
fi

# Context bar + session duration (for line 2)
CTX_INT=${CTX_PCT%.*}
CTX_COLOR=$(color_for_pct "$CTX_INT")
CTX_PART="${LABEL}ctx${RST} ${CTX_COLOR}$(progress_bar "$CTX_INT" 12)${RST} ${WHITE}${CTX_INT}%${RST}"
DUR_PART="${LABEL}⏱${RST} ${WHITE}${DURATION_FMT}${RST}"

LINE1="${L1C1}"

# ── 9. Fetch usage API (cached) ─────────────────────────────────────
CACHE_FILE="/tmp/claude-statusline-usage.json"
CACHE_TTL=120

fetch_usage() {
  local cred_json
  cred_json=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) || return 1
  local token
  token=$(echo "$cred_json" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null) || return 1
  [[ -z "$token" ]] && return 1

  local now
  now=$(date +%s)
  if [[ -f "$CACHE_FILE" ]]; then
    local mtime
    mtime=$(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
    if (( now - mtime < CACHE_TTL )); then
      cat "$CACHE_FILE"
      return 0
    fi
  fi

  local resp
  resp=$(curl -s --max-time 3 \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null) || true

  if echo "$resp" | jq -e '.five_hour' &>/dev/null; then
    echo "$resp" > "$CACHE_FILE"
    echo "$resp"
  elif [[ -f "$CACHE_FILE" ]]; then
    cat "$CACHE_FILE"
  else
    return 1
  fi
}

build_usage_line() {
  local usage_json
  usage_json=$(fetch_usage 2>/dev/null) || return 1

  local five_pct seven_pct resets_at seven_resets_at
  five_pct=$(echo "$usage_json" | jq -r '.five_hour.utilization // empty')
  seven_pct=$(echo "$usage_json" | jq -r '.seven_day.utilization // empty')
  resets_at=$(echo "$usage_json" | jq -r '.five_hour.resets_at // empty')
  seven_resets_at=$(echo "$usage_json" | jq -r '.seven_day.resets_at // empty')

  [[ -z "$five_pct" ]] && return 1

  five_int=${five_pct%.*}
  seven_int=${seven_pct%.*}
  seven_int=${seven_int:-0}

  # Parse extra usage fields
  local extra_enabled extra_limit extra_used extra_util
  extra_enabled=$(echo "$usage_json" | jq -r '.extra_usage.is_enabled // empty')
  extra_limit=$(echo "$usage_json" | jq -r '.extra_usage.monthly_limit // empty')
  extra_used=$(echo "$usage_json" | jq -r '.extra_usage.used_credits // empty')
  extra_util=$(echo "$usage_json" | jq -r '.extra_usage.utilization // empty')

  # Parse Max-specific per-model fields
  local opus_pct opus_resets sonnet_pct sonnet_resets
  opus_pct=$(echo "$usage_json" | jq -r '.seven_day_opus.utilization // empty')
  opus_resets=$(echo "$usage_json" | jq -r '.seven_day_opus.resets_at // empty')
  sonnet_pct=$(echo "$usage_json" | jq -r '.seven_day_sonnet.utilization // empty')
  sonnet_resets=$(echo "$usage_json" | jq -r '.seven_day_sonnet.resets_at // empty')

  # Format reset times
  local five_reset_info=""
  [[ -n "$resets_at" ]] && five_reset_info=$(fmt_reset_info "$resets_at" "%H:%M")

  local five_color
  five_color=$(color_for_pct "$five_int")

  # 5h group: bar + reset info (common to both plans)
  local L2_5H="${LABEL}5h${RST}  ${five_color}$(progress_bar "$five_int" 12)${RST} ${WHITE}${five_int}%${RST}"
  if [[ -n "$five_reset_info" ]]; then
    L2_5H+="  ${LABEL}↻${RST} ${WHITE}${five_reset_info}${RST}"
  fi

  # Extra usage info (shown when enabled)
  local L2_EXTRA=""
  if [[ "$extra_enabled" == "true" && -n "$extra_used" && -n "$extra_limit" ]]; then
    local extra_int=${extra_util%.*}
    extra_int=${extra_int:-0}
    local extra_color=$(color_for_pct "$extra_int")
    local used_dollars remaining_dollars limit_dollars
    used_dollars=$(printf '%.2f' "$(echo "$extra_used / 100" | bc -l)")
    limit_dollars=$(printf '%.2f' "$(echo "$extra_limit / 100" | bc -l)")
    remaining_dollars=$(printf '%.2f' "$(echo "($extra_limit - $extra_used) / 100" | bc -l)")
    L2_EXTRA="${LABEL}extra${RST}  ${extra_color}$(progress_bar "$extra_int" 12)${RST} ${WHITE}\$${used_dollars}/\$${limit_dollars}${RST}"
  fi

  # Detect Max plan: opus or sonnet per-model data present
  if [[ -n "$opus_pct" || -n "$sonnet_pct" ]]; then
    # ── Max plan: 7d aggregate + per-model bars ──
    local result="${L2_5H}"

    if [[ -n "$seven_pct" ]]; then
      local seven_color=$(color_for_pct "$seven_int")
      local seven_reset_info=""
      [[ -n "$seven_resets_at" ]] && seven_reset_info=$(fmt_reset_info "$seven_resets_at" "%b %d")
      local L2_7D="${LABEL}7d${RST}  ${seven_color}$(progress_bar "$seven_int" 12)${RST} ${WHITE}${seven_int}%${RST}"
      if [[ -n "$seven_reset_info" ]]; then
        L2_7D+="  ${LABEL}↻${RST} ${WHITE}${seven_reset_info}${RST}"
      fi
      result+=" ${SEP} ${L2_7D}"
    fi

    if [[ -n "$opus_pct" ]]; then
      local opus_int=${opus_pct%.*}
      local opus_color=$(color_for_pct "$opus_int")
      local opus_reset_info=""
      [[ -n "$opus_resets" ]] && opus_reset_info=$(fmt_reset_info "$opus_resets" "%b %d")
      local L2_OPUS="${LABEL}opus${RST}  ${opus_color}$(progress_bar "$opus_int" 12)${RST} ${WHITE}${opus_int}%${RST}"
      if [[ -n "$opus_reset_info" ]]; then
        L2_OPUS+="  ${LABEL}↻${RST} ${WHITE}${opus_reset_info}${RST}"
      fi
      result+=" ${SEP} ${L2_OPUS}"
    fi

    if [[ -n "$sonnet_pct" ]]; then
      local sonnet_int=${sonnet_pct%.*}
      local sonnet_color=$(color_for_pct "$sonnet_int")
      local sonnet_reset_info=""
      [[ -n "$sonnet_resets" ]] && sonnet_reset_info=$(fmt_reset_info "$sonnet_resets" "%b %d")
      local L2_SONNET="${LABEL}sonnet${RST}  ${sonnet_color}$(progress_bar "$sonnet_int" 12)${RST} ${WHITE}${sonnet_int}%${RST}"
      if [[ -n "$sonnet_reset_info" ]]; then
        L2_SONNET+="  ${LABEL}↻${RST} ${WHITE}${sonnet_reset_info}${RST}"
      fi
      result+=" ${SEP} ${L2_SONNET}"
    fi

    [[ -n "$L2_EXTRA" ]] && result+=" ${SEP} ${L2_EXTRA}"
    echo -ne "$result"
  else
    # ── Pro plan: single 7d bar ──
    local seven_color
    seven_color=$(color_for_pct "$seven_int")

    local seven_reset_info=""
    [[ -n "$seven_resets_at" ]] && seven_reset_info=$(fmt_reset_info "$seven_resets_at" "%b %d %H:%M")

    local L2_7D="${LABEL}7d${RST}  ${seven_color}$(progress_bar "$seven_int" 12)${RST} ${WHITE}${seven_int}%${RST}"
    if [[ -n "$seven_reset_info" ]]; then
      L2_7D+="  ${LABEL}↻${RST} ${WHITE}${seven_reset_info}${RST}"
    fi

    local pro_result="${L2_5H} ${SEP} ${L2_7D}"
    [[ -n "$L2_EXTRA" ]] && pro_result+=" ${SEP} ${L2_EXTRA}"
    echo -ne "$pro_result"
  fi
}

USAGE_LINE=$(build_usage_line 2>/dev/null) || true

# ── 10. Detect plan mode ─────────────────────────────────────────────
PLAN_MODE=""
if [[ -n "$USAGE_LINE" && -f "$CACHE_FILE" ]]; then
  if jq -e '.seven_day_opus // .seven_day_sonnet' "$CACHE_FILE" &>/dev/null; then
    PLAN_MODE="Max"
  else
    PLAN_MODE="Pro"
  fi
elif [[ -n "$COST_USD" ]]; then
  PLAN_MODE="API"
fi

# ── 11. Build API cost info (when not on Pro/Max) ────────────────────
API_PART=""
if [[ -z "$USAGE_LINE" && -n "$COST_USD" ]]; then
  COST_FMT=$(printf '$%.4f' "$COST_USD")
  API_PART="${WHITE}${COST_FMT}${RST}"
fi

# ── 12. Output ───────────────────────────────────────────────────────
LINE2="${CTX_PART} ${SEP} ${DUR_PART}"
if [[ -n "$USAGE_LINE" ]]; then
  LINE2+=" ${SEP} ${USAGE_LINE}"
elif [[ -n "$API_PART" ]]; then
  LINE2+=" ${SEP} ${API_PART}"
fi

if [[ -n "$PLAN_MODE" ]]; then
  LINE1+="${SEP}${WHITE}${PLAN_MODE}${RST}"
fi

echo -ne "$LINE2"
echo ""
echo -ne "$LINE1"
