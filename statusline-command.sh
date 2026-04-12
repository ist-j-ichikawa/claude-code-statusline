#!/bin/bash
# Claude Code Statusline — see README.md for details
# https://code.claude.com/docs/en/statusline
set -uo pipefail

# --- Constants ---
readonly RST=$'\033[0m' GRN=$'\033[32m' YLW=$'\033[33m' RED=$'\033[31m'
readonly DIM=$'\033[2m'
readonly ANTH=$'\033[38;5;180m' BDCK=$'\033[38;5;72m' VTEX=$'\033[38;5;33m' FNDY=$'\033[38;5;39m'
readonly GIT=$'\033[38;5;202m'
readonly CORAL=$'\033[38;5;209m' TEAL=$'\033[38;5;79m' AMBER=$'\033[38;5;214m' LAVENDER=$'\033[38;5;183m'
readonly AGENT=$'\033[38;5;213m' DIMVER=$'\033[38;5;248m'
readonly CACHE_BASE="/tmp/ist-j-ichikawa-claude-statusline"
readonly GIT_CACHE_DIR="${CACHE_BASE}/git"
readonly GIT_CACHE_MAX_AGE=5
readonly _NOW=$(date +%s)

# --- Terminal width (for adaptive content) ---
_cols=${COLUMNS:-0}
((_cols <= 0)) && { _cols=$(tput cols 2>/dev/null); [[ "${_cols:-}" =~ ^[0-9]+$ ]] || _cols=80; }

# --- Helpers ---
has_val() { [[ -n "$1" && "$1" != "null" ]]; }

# osc8 URL TEXT VARNAME — sets VARNAME to OSC 8 hyperlink (no subshell)
osc8() { printf -v "$3" '\033]8;;%s\a%s\033]8;;\a' "$1" "$2"; }

# editor_url PATH VARNAME — sets VARNAME to file:// URL for OSC 8 hyperlink (no subshell)
editor_url() { printf -v "$2" 'file://%s' "$1"; }

# braille_bar PCT VARNAME — sets VARNAME to 5-char braille bar (no subshell)
# 8 braille levels per char × 5 chars = 40 steps of precision
braille_bar() {
  local pct=$1 width=5
  [[ "$pct" =~ ^[0-9]+$ ]] || { printf -v "$2" '%s' '     '; return; }
  local b0=' ' b1='⣀' b2='⣄' b3='⣤' b4='⣦' b5='⣶' b6='⣷' b7='⣿'
  local _bb="" level=$((pct * width * 7 / 100)) i seg varname
  ((level > width * 7)) && level=$((width * 7))
  ((level < 0)) && level=0
  for ((i = 0; i < width; i++)); do
    seg=$((level - i * 7))
    ((seg < 0)) && seg=0
    ((seg > 7)) && seg=7
    varname="b${seg}"
    _bb+="${!varname}"
  done
  printf -v "$2" '%s' "$_bb"
}

# _truncate_bytes VARNAME MAX — byte-level safety-net truncation with ANSI cleanup (no subshell)
_truncate_bytes() {
  local _tb="${!1}" _tm=$2
  if ((${#_tb} > _tm)); then
    _tb="${_tb:0:_tm}"
    local _et="${_tb##*$'\033'}"
    if [[ "$_et" != "$_tb" && "$_et" != *m* ]]; then
      _tb="${_tb%$'\033'*}"
    fi
    printf -v "$1" '%s%s' "$_tb" "$RST"
  fi
}

# color_by_threshold VAL HI MID VARNAME — sets VARNAME to color code (no subshell)
color_by_threshold() {
  local val=$1 hi=$2 mid=$3
  [[ "$val" =~ ^[0-9]+$ ]] || { printf -v "$4" '%s' "$DIM"; return; }
  if ((val >= hi)); then printf -v "$4" '%s' "$RED"
  elif ((val >= mid)); then printf -v "$4" '%s' "$YLW"
  else printf -v "$4" '%s' "$GRN"; fi
}

cache_stale() {
  local cache=$1 max_age=${2:-$GIT_CACHE_MAX_AGE}
  [[ ! -f "$cache" ]] && return 0
  local age=$(( _NOW - $(stat -f %m "$cache" 2>/dev/null) ))
  ((age > max_age))
}

# git_cache_file DIR — sets _gc (no subshell)
git_cache_file() {
  [[ -d "$GIT_CACHE_DIR" ]] || mkdir -p -m 700 "$GIT_CACHE_DIR"
  _gc="${GIT_CACHE_DIR}/$(md5 -q -s "$1")"
}

# format_tokens TOK VARNAME — sets VARNAME (no subshell)
format_tokens() {
  local tok=$1
  [[ "$tok" =~ ^[0-9]+$ ]] || { printf -v "$2" '%s' '?'; return; }
  if ((tok >= 1000000)); then printf -v "$2" '%d.%dM' $((tok / 1000000)) $((tok % 1000000 / 100000))
  elif ((tok >= 1000)); then printf -v "$2" '%d.%dk' $((tok / 1000)) $((tok % 1000 / 100))
  else printf -v "$2" '%d' "$tok"
  fi
}

# --- Credentials blob (Keychain → file fallback) ---
get_credentials_blob() {
  if command -v security &>/dev/null; then
    local blob
    blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
    if [[ -n "$blob" ]]; then echo "$blob"; return 0; fi
  fi
  local creds="${HOME}/.claude/.credentials.json"
  [[ -f "$creds" ]] && cat "$creds" 2>/dev/null
}

# --- Subscription type (cached, background refresh) ---
readonly SUB_CACHE="${CACHE_BASE}/subscription"
readonly SUB_CACHE_MAX_AGE=3600

# fetch_subscription — sets _sub_type (no subshell)
fetch_subscription() {
  [[ -d "$CACHE_BASE" ]] || mkdir -p -m 700 "$CACHE_BASE"
  if cache_stale "$SUB_CACHE" "$SUB_CACHE_MAX_AGE"; then
    (
      local blob sub_type=""
      blob=$(get_credentials_blob)
      if [[ -n "$blob" ]]; then
        sub_type=$(jq -r '.claudeAiOauth.subscriptionType // empty' <<< "$blob" 2>/dev/null)
      fi
      if [[ -n "$sub_type" ]]; then
        echo "$sub_type" > "$SUB_CACHE"
      elif [[ -f "$SUB_CACHE" ]]; then
        touch "$SUB_CACHE"
      fi
    ) & disown
  fi
  [[ -f "$SUB_CACHE" ]] && _sub_type=$(<"$SUB_CACHE") || _sub_type=""
}

# format_reset_remaining EPOCH — sets _reset (no subshell)
format_reset_remaining() {
  _reset=""
  local epoch=$1
  [[ -z "$epoch" || "$epoch" == "null" ]] && return
  [[ "$epoch" =~ ^[0-9]+$ ]] || return
  local diff=$((epoch - _NOW))
  if ((diff <= 0)); then _reset="now"; return; fi
  local d=$((diff / 86400)) h=$(( (diff % 86400) / 3600 )) m=$(( (diff % 3600) / 60 ))
  if ((d > 0)); then printf -v _reset '%dd%dh' "$d" "$h"
  elif ((h > 0)); then printf -v _reset '%d:%02d' "$h" "$m"
  else printf -v _reset '0:%02d' "$m"; fi
}

# format_reset_absolute EPOCH — sets _reset (1 fork: date)
format_reset_absolute() {
  _reset=""
  local epoch=$1
  [[ -z "$epoch" || "$epoch" == "null" ]] && return
  [[ "$epoch" =~ ^[0-9]+$ ]] || return
  _reset=$(date -j -r "$epoch" +"%a %H:%M" 2>/dev/null)
}

# --- JSON extraction (single jq call) ---
IFS= read -r -d '' input || true

# Initialize all jq variables — prevents set -u instant death if eval fails
model="" model_id="" current_dir="." project_dir="" used_pct=""
exceeds_200k="false" cc_version="" session_name=""
agent_name="" ctx_window_size=0
five_pct="" five_reset_epoch="" seven_pct="" seven_reset_epoch=""
wt_name="" wt_path="" wt_orig_branch="" added_dirs_count=0 ws_git_worktree=""
_jq_ok=1
_jq_out=$(jq -r '
  @sh "model=\(.model.display_name // "Unknown")",
  @sh "model_id=\(.model.id // "")",
  @sh "current_dir=\(.workspace.current_dir // ".")",
  @sh "project_dir=\(.workspace.project_dir // "")",
  @sh "used_pct=\(.context_window.used_percentage // "")",
  @sh "exceeds_200k=\(.exceeds_200k_tokens // false)",
  @sh "cc_version=\(.version // "")",
  @sh "session_name=\(.session_name // "")",
  @sh "agent_name=\(.agent.name // "")",
  @sh "ctx_window_size=\(.context_window.context_window_size // 0)",
  @sh "five_pct=\(.rate_limits.five_hour.used_percentage // null | if . == null then "" else round end)",
  @sh "five_reset_epoch=\(.rate_limits.five_hour.resets_at // null | if . == null then "" else floor end)",
  @sh "seven_pct=\(.rate_limits.seven_day.used_percentage // null | if . == null then "" else round end)",
  @sh "seven_reset_epoch=\(.rate_limits.seven_day.resets_at // null | if . == null then "" else floor end)",
  @sh "wt_name=\(.worktree.name // "")",
  @sh "wt_path=\(.worktree.path // "")",
  @sh "wt_orig_branch=\(.worktree.original_branch // "")",
  @sh "added_dirs_count=\(.workspace.added_dirs // [] | length)",
  @sh "ws_git_worktree=\(.workspace.git_worktree // "")"
' <<< "$input" 2>/dev/null) || _jq_ok=0
if ((_jq_ok)); then eval "$_jq_out" || true; fi

# worktree sessions: workspace.current_dir points to original repo
if [[ -n "$wt_path" ]]; then
  current_dir="$wt_path"
fi

# --- Git info (5s cached) ---
build_git() {
  local dir=$1 text="" branch git_dir

  branch=$(git -C "$dir" branch --show-current 2>/dev/null)

  git_dir=$(git -C "$dir" rev-parse --git-dir 2>/dev/null)
  local git_common_dir repo_name=""
  git_common_dir=$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null)
  if [[ -n "$git_dir" && -n "$git_common_dir" && "$git_dir" != "$git_common_dir" ]]; then
    local tmp="${git_common_dir%/.git}"
    repo_name="${tmp##*/}"
  elif [[ -n "$git_dir" ]]; then
    local toplevel
    toplevel=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
    repo_name="${toplevel##*/}"
  fi

  # Detached HEAD
  if [[ -z "$branch" ]]; then
    local short_sha
    short_sha=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
    [[ -n "$short_sha" ]] && branch="HEAD@${short_sha}"
  fi

  # Branch display (detached=red, normal=green)
  if [[ -n "$repo_name" && -n "$branch" ]]; then
    if [[ "$branch" == HEAD@* ]]; then
      text+="${repo_name} ${RED}(${branch})${RST}"
    else
      text+="${repo_name} ${GIT}(${branch})${RST}"
    fi
  elif [[ -n "$repo_name" ]]; then
    text+="${repo_name}"
  fi

  # Dirty state: staged(green) / modified(yellow) / untracked(dim) / conflicts(red)
  local staged modified untracked conflicts
  staged=$(git -C "$dir" diff --cached --name-only 2>/dev/null | grep -c . || echo 0)
  modified=$(git -C "$dir" diff --name-only 2>/dev/null | grep -c . || echo 0)
  untracked=$(git -C "$dir" ls-files --others --exclude-standard 2>/dev/null | grep -c . || echo 0)
  conflicts=$(git -C "$dir" diff --name-only --diff-filter=U 2>/dev/null | grep -c . || echo 0)
  ((conflicts > 0)) && text+=" ${RED}U${conflicts}${RST}"
  ((staged > 0))    && text+=" ${GRN}A${staged}${RST}"
  ((modified > 0))  && text+=" ${YLW}M${modified}${RST}"
  ((untracked > 0)) && text+=" ${DIM}?${untracked}${RST}"

  # Ahead/behind
  if git -C "$dir" rev-parse --abbrev-ref '@{upstream}' &>/dev/null; then
    local ahead behind
    ahead=$(git -C "$dir" rev-list --count '@{upstream}..HEAD' 2>/dev/null)
    behind=$(git -C "$dir" rev-list --count 'HEAD..@{upstream}' 2>/dev/null)
    ((ahead > 0)) && text+=" ${GRN}↑${ahead}${RST}"
    ((behind > 0)) && text+=" ${RED}↓${behind}${RST}"
  fi

  # Last commit age + message (single git log call)
  local last_epoch last_msg log_output
  log_output=$(git -C "$dir" log -1 --pretty=$'%ct\n%s' 2>/dev/null)
  last_epoch="${log_output%%$'\n'*}"
  last_msg="${log_output#*$'\n'}"
  if [[ -n "$last_epoch" ]]; then
    local age=$((_NOW - last_epoch))
    local age_str=""
    if ((age < 3600)); then
      age_str="$((age / 60))m"
    elif ((age < 86400)); then
      age_str="$((age / 3600))h"
    elif ((age < 604800)); then
      age_str="$((age / 86400))d"
    fi
    # Truncate message to 20 chars
    [[ ${#last_msg} -gt 20 ]] && last_msg="${last_msg:0:20}.."
    if [[ -n "$age_str" && -n "$last_msg" ]]; then
      text+=" ${DIM}${age_str} ${last_msg}${RST}"
    elif [[ -n "$age_str" ]]; then
      text+=" ${DIM}${age_str}${RST}"
    fi
  fi

  echo "$text"
}


# ============================================================================
# Line 1: Provider + Model + Agent + [(Branch)] + Version + Vim mode
# ============================================================================
line1=()

if ((_jq_ok == 0)); then
  line1+=("${RED}jq error${RST}")
  line2=() line3=()
  _out="${line1[*]}"$'\n'"${line2[*]}"$'\n'"${line3[*]}"
  printf '%s\n' "$_out"
  exit 0
fi

# Model (colored by tier): prefer display_name, fall back to id
model_show="${model:-$model_id}"
# Narrow terminals: strip version suffix (e.g. "Opus 4.6" → "Opus")
if ((_cols < 35)); then model_show="${model_show%% [0-9]*}"; fi

# Cloud provider detection (check model_id for Bedrock prefix, not display_name)
provider=""
shopt -s nocasematch
if [[ "$model_id" =~ ^(global|jp|us|eu|au|apac)\. ]] || [[ "${CLAUDE_CODE_USE_BEDROCK:-}" == "1" ]] || [[ "${CLAUDE_CODE_USE_MANTLE:-}" == "1" ]]; then
  provider="bedrock"
elif [[ "${CLAUDE_CODE_USE_VERTEX:-}" == "1" ]]; then
  provider="vertex"
elif [[ "${CLAUDE_CODE_USE_FOUNDRY:-}" == "1" ]]; then
  provider="foundry"
fi

# Provider indicator (first in line)
case "$provider" in
  bedrock) line1+=("${BDCK}Bedrock${RST}") ;;
  vertex)  line1+=("${VTEX}Vertex${RST}") ;;
  foundry) line1+=("${FNDY}Foundry${RST}") ;;
  *)
    if ((_cols >= 45)); then
      fetch_subscription
      if has_val "$_sub_type"; then
        line1+=("${ANTH}Anthropic(${_sub_type})${RST}")
      else
        line1+=("${ANTH}Anthropic${RST}")
      fi
    else
      line1+=("${ANTH}Anthropic${RST}")
    fi
    ;;
esac

if [[ "$model_show" == *opus* ]]; then
  line1+=("${CORAL}${model_show}${RST}")
elif [[ "$model_show" == *sonnet*4.5* || "$model_show" == *sonnet*3.5* ]]; then
  line1+=("${AMBER}${model_show}${RST}")
elif [[ "$model_show" == *sonnet* ]]; then
  line1+=("${TEAL}${model_show}${RST}")
elif [[ "$model_show" == *haiku* ]]; then
  line1+=("${LAVENDER}${model_show}${RST}")
else
  line1+=("${model_show}")
fi
shopt -u nocasematch

# Agent name (skip on narrow terminals)
if has_val "$agent_name" && ((_cols >= 45)); then
  line1+=("${AGENT}⚡${agent_name}${RST}")
fi

# Session name (strip XML tags + command noise from /branch, /fork etc.)
is_branch=false
[[ "$session_name" == *"(Branch)"* || "$session_name" == *"(Fork)"* ]] && is_branch=true
session_name="${session_name//(Branch)/}"
session_name="${session_name//(Fork)/}"
while [[ "$session_name" == *"<"*">"* ]]; do
  session_name="${session_name%%<*}${session_name#*>}"
done
session_name="${session_name#"${session_name%%[![:space:]]*}"}"
session_name="${session_name%"${session_name##*[![:space:]]}"}"
# Drop if it looks like command/skill residue (contains colons like "plugin:skill" or starts with "/")
if [[ "$session_name" == *:* || "$session_name" == /* ]]; then
  session_name=""
fi
# Version (skip on narrow terminals)
if has_val "$cc_version" && ((_cols >= 65)); then
  line1+=("${DIMVER}v${cc_version}${RST}")
fi
# Session indicator (skip on narrow terminals)
if ((_cols >= 55)); then
  if $is_branch; then
    line1+=("${YLW}(branch)${RST}")
  fi
fi

# ============================================================================
# Line 2: Dir + Git
# ============================================================================
line2=()

# Git info (background refresh)
git_cache_file "$current_dir"
if cache_stale "$_gc" "$GIT_CACHE_MAX_AGE"; then
  ( [[ -d "$GIT_CACHE_DIR" ]] || mkdir -p -m 700 "$GIT_CACHE_DIR"
    build_git "$current_dir" > "${_gc}.tmp" && mv "${_gc}.tmp" "$_gc" ) & disown
fi
[[ -f "$_gc" ]] && git_cached=$(<"$_gc") || git_cached=""

# Directory path (full display — no truncation; git info is truncated instead)
_display_dir="${project_dir:-$current_dir}"
_short_dir="${_display_dir/#$HOME/~}"
editor_url "$_display_dir" _editor_url
osc8 "$_editor_url" "$_short_dir" _osc_tmp
line2+=("$_osc_tmp")

# added_dirs indicator
if ((added_dirs_count > 0)); then
  line2+=("${DIM}(+${added_dirs_count} dirs)${RST}")
fi

# Narrow terminals: skip git entirely or truncate (byte-level, append RST)
# Path gets full space; git info is truncated based on remaining width
_path_len=${#_short_dir}
if ((_cols < 45)); then
  git_cached=""
elif [[ -n "$git_cached" ]]; then
  _git_max=$((_cols - _path_len - 3))
  ((_git_max < 10)) && _git_max=10
  _truncate_bytes git_cached $((_git_max * 2))
fi

# Git info (strip repo name if same as dir basename to avoid redundancy)
if [[ -n "$git_cached" ]]; then
  dir_basename="${_display_dir##*/}"
  # repo_name is always plain text at start of git_cached (no ANSI prefix)
  repo_name="${git_cached%% *}"
  if [[ "$dir_basename" == "$repo_name" ]]; then
    if [[ "$git_cached" == *" "* ]]; then
      # Remove repo name prefix (keep branch + state)
      git_cached="${git_cached#*" "}"
    else
      # No branch info — repo name only, skip to avoid redundancy
      git_cached=""
    fi
  fi
  [[ -n "$git_cached" ]] && line2+=("$git_cached")
else
  # No cached git info — check if truly non-git using pure bash (no fork)
  if [[ ! -d "${_display_dir}/.git" && ! -f "${_display_dir}/.git" ]]; then
    line2+=("${DIM}(no git)${RST}")
  else
    # Cold start: read branch from .git/HEAD (pure bash, no fork)
    _head_file="${_display_dir}/.git"
    if [[ -f "$_head_file" ]]; then
      # Worktree: .git is a file → follow gitdir pointer
      _gitdir_line=$(<"$_head_file")
      _gitdir="${_gitdir_line#gitdir: }"
      if [[ "$_gitdir" != /* ]]; then
        _head_file="${_display_dir}/${_gitdir}/HEAD"
      else
        _head_file="${_gitdir}/HEAD"
      fi
    else
      _head_file="${_head_file}/HEAD"
    fi
    if [[ -f "$_head_file" ]]; then
      _head=$(<"$_head_file")
      if [[ "$_head" == ref:* ]]; then
        line2+=("${GIT}(${_head#ref: refs/heads/})${RST}")
      else
        line2+=("${RED}(HEAD@${_head:0:7})${RST}")
      fi
    fi
  fi
fi

# Worktree indicator: CC worktree (wt_name) or git linked worktree (ws_git_worktree, CC 2.1.97+)
if (has_val "$wt_name" || has_val "$ws_git_worktree") && ((_cols >= 45)); then
  line2+=("🌲")
  if has_val "$wt_orig_branch"; then
    line2+=("${DIM}from:${wt_orig_branch}${RST}")
  fi
fi


# ============================================================================
# Line 3: Context + Cost & Tokens (all providers) + Rate Limit (Anthropic)
# ============================================================================
line3=()

# 5-hour rate limit (Anthropic only, CC 2.1.80+) — leftmost for quick glance
if [[ -z "$provider" ]] && has_val "$five_pct"; then
  format_reset_remaining "$five_reset_epoch"
  braille_bar "$five_pct" _bbar
  line3+=("${ANTH}${_bbar} ${five_pct}%${RST}")
  [[ -n "$_reset" ]] && line3+=("${ANTH}${_reset}${RST}")
fi

# Context bar
if has_val "$used_pct"; then
  pct_int=${used_pct%.*}
  color_by_threshold "$pct_int" 90 80 ctx_color
  braille_bar "$pct_int" _bbar
  ctx_text="${ctx_color}${_bbar} ${pct_int}%${RST}"
  [[ "$exceeds_200k" == "true" && "$ctx_window_size" -le 200000 ]] && ctx_text+=" ${RED}⚠ 200K超${RST}"
  line3+=("$ctx_text")
else
  line3+=("${DIM}      -%${RST}")
fi

# Weekly rate limit (Anthropic only, rightmost — low priority)
if [[ -z "$provider" ]] && has_val "$seven_pct" && ((seven_pct > 0)) && ((_cols >= 70)); then
  format_reset_absolute "$seven_reset_epoch"
  line3+=("${DIM}week:${seven_pct}%${RST}")
  [[ -n "$_reset" ]] && line3+=("${DIM}${_reset}${RST}")
fi

# ============================================================================
# Output — single write() for atomic pipe delivery
# ============================================================================
_l1="${line1[*]}" _l2="${line2[*]}" _l3="${line3[*]}"
_max_bytes=$((_cols * 3 + 60))
_truncate_bytes _l1 "$_max_bytes"
_truncate_bytes _l2 "$_max_bytes"
_truncate_bytes _l3 "$_max_bytes"
_out="${_l1}"$'\n'"${_l2}"$'\n'"${_l3}"
printf '%s\n' "$_out"

exit 0
