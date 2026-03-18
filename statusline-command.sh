#!/bin/bash
# Claude Code Statusline — see README.md for details
# https://code.claude.com/docs/en/statusline
set -uo pipefail

# --- Constants ---
readonly RST=$'\033[0m' GRN=$'\033[32m' YLW=$'\033[33m' RED=$'\033[31m'
readonly DIM=$'\033[2m'
readonly ANTH=$'\033[38;5;180m' BDCK=$'\033[38;5;72m' VTEX=$'\033[38;5;33m' FNDY=$'\033[38;5;39m'
readonly CORAL=$'\033[38;5;209m' TEAL=$'\033[38;5;79m' AMBER=$'\033[38;5;214m' LAVENDER=$'\033[38;5;183m'
readonly AGENT=$'\033[38;5;213m' DIMVER=$'\033[38;5;248m'
readonly CACHE_BASE="/tmp/ist-j-ichikawa-claude-statusline"
readonly GIT_CACHE_DIR="${CACHE_BASE}/git"
readonly GIT_CACHE_MAX_AGE=5
readonly USAGE_CACHE_DIR="${CACHE_BASE}/usage"
readonly USAGE_CACHE_MAX_AGE=300
readonly _NOW=$(date +%s)

# --- Helpers ---
has_val() { [[ -n "$1" && "$1" != "null" ]]; }

# osc8 URL TEXT VARNAME — sets VARNAME to OSC 8 hyperlink (no subshell)
osc8() { printf -v "$3" '\033]8;;%s\a%s\033]8;;\a' "$1" "$2"; }

# progress_bar PCT VARNAME — sets VARNAME to bar string (no subshell)
progress_bar() {
  local pct=$1 width=10
  local filled=$((pct * width / 100)) _pb=""
  ((filled > width)) && filled=$width
  local empty=$((width - filled))
  for ((i=0; i<filled; i++)); do _pb+="●"; done
  for ((i=0; i<empty; i++)); do _pb+="○"; done
  printf -v "$2" '%s' "$_pb"
}

# color_by_threshold VAL HI MID VARNAME — sets VARNAME to color code (no subshell)
color_by_threshold() {
  local val=$1 hi=$2 mid=$3
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

# --- OAuth token resolution ---
get_oauth_token() {
  if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
    echo "$CLAUDE_CODE_OAUTH_TOKEN"; return 0
  fi
  local blob
  blob=$(get_credentials_blob)
  if [[ -n "$blob" ]]; then
    local token
    token=$(jq -r '.claudeAiOauth.accessToken // empty' <<< "$blob" 2>/dev/null)
    if has_val "$token"; then echo "$token"; return 0; fi
  fi
  echo ""
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

# --- Usage API (cached, background refresh) ---
# fetch_usage — sets _usage_json (no subshell)
fetch_usage() {
  [[ -d "$USAGE_CACHE_DIR" ]] || mkdir -p -m 700 "$USAGE_CACHE_DIR"
  local cache_file="${USAGE_CACHE_DIR}/usage.json"

  if cache_stale "$cache_file" "$USAGE_CACHE_MAX_AGE"; then
    # Refresh in background — serve stale cache, never block
    (
      token=$(get_oauth_token)
      token="${token//$'\n'/}" token="${token//$'\r'/}"
      if has_val "$token"; then
        resp=$(printf 'header = "Authorization: Bearer %s"\n' "$token" \
          | curl -s --max-time 3 --config - \
          -H "Accept: application/json" \
          -H "Content-Type: application/json" \
          -H "anthropic-beta: oauth-2025-04-20" \
          "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        if [[ -n "$resp" ]] && jq -e '.five_hour' <<< "$resp" &>/dev/null; then
          echo "$resp" > "${cache_file}.tmp" && mv "${cache_file}.tmp" "$cache_file"
        elif [[ -f "$cache_file" ]]; then
          # Touch cache to avoid retry storm on API error
          touch "$cache_file"
        fi
      fi
    ) &
    disown
  fi

  [[ -f "$cache_file" ]] && _usage_json=$(<"$cache_file") || _usage_json=""
}

# iso_to_epoch ISO — sets _epoch (no subshell)
iso_to_epoch() {
  _epoch=""
  local iso=$1
  [[ -z "$iso" || "$iso" == "null" ]] && return 1
  local stripped="${iso%%.*}"
  stripped="${stripped%Z}"
  _epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
  [[ -n "$_epoch" ]]
}

# format_reset_remaining ISO — sets _reset (no subshell)
format_reset_remaining() {
  iso_to_epoch "$1" || { _reset=""; return; }
  local diff=$((_epoch - _NOW))
  if ((diff <= 0)); then _reset="now"; return; fi
  local d=$((diff / 86400)) h=$(( (diff % 86400) / 3600 )) m=$(( (diff % 3600) / 60 ))
  if ((d > 0)); then printf -v _reset '%dd%dh' "$d" "$h"
  elif ((h > 0)); then printf -v _reset '%d:%02d' "$h" "$m"
  else printf -v _reset '0:%02d' "$m"; fi
}

# format_reset_absolute ISO — sets _reset (no subshell)
format_reset_absolute() {
  iso_to_epoch "$1" || { _reset=""; return; }
  _reset=$(date -j -r "$_epoch" +"%a %H:%M" 2>/dev/null)
}

# --- JSON extraction (single jq call) ---
IFS= read -r -d '' input || true
eval "$(jq -r '
  @sh "model=\(.model.display_name // "Unknown")",
  @sh "model_id=\(.model.id // "")",
  @sh "current_dir=\(.workspace.current_dir // ".")",
  @sh "project_dir=\(.workspace.project_dir // "")",
  @sh "used_pct=\(.context_window.used_percentage // "")",
  @sh "exceeds_200k=\(.exceeds_200k_tokens // false)",
  @sh "cc_version=\(.version // "")",
  @sh "session_id=\(.session_id // "")",
  @sh "session_name=\(.session_name // "")",
  @sh "agent_name=\(.agent.name // "")",
  @sh "ctx_window_size=\(.context_window.context_window_size // 0)",
  @sh "cost_usd=\(.cost.total_cost_usd // "")",
  @sh "total_in_tok=\(.context_window.total_input_tokens // "")",
  @sh "total_out_tok=\(.context_window.total_output_tokens // "")"
' <<< "$input")" || true

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
      text+="${repo_name} ${GRN}(${branch})${RST}"
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
  ((conflicts > 0)) && text+=" ${RED}!${conflicts}${RST}"
  ((staged > 0))    && text+=" ${GRN}+${staged}${RST}"
  ((modified > 0))  && text+=" ${YLW}~${modified}${RST}"
  ((untracked > 0)) && text+=" ${DIM}?${untracked}${RST}"

  # Ahead/behind
  if git -C "$dir" rev-parse --abbrev-ref '@{upstream}' &>/dev/null; then
    local ahead behind
    ahead=$(git -C "$dir" rev-list --count '@{upstream}..HEAD' 2>/dev/null)
    behind=$(git -C "$dir" rev-list --count 'HEAD..@{upstream}' 2>/dev/null)
    ((ahead > 0)) && text+=" ${GRN}↑${ahead}${RST}"
    ((behind > 0)) && text+=" ${RED}↓${behind}${RST}"
  fi

  # Stash count
  local stash_count
  stash_count=$(git -C "$dir" stash list 2>/dev/null | grep -c . || echo 0)
  ((stash_count > 0)) && text+=" ${DIM}stash:${stash_count}${RST}"

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

  # Worktree indicator
  [[ -n "$git_dir" && -n "$git_common_dir" && "$git_dir" != "$git_common_dir" ]] && text+=" 🌲"

  echo "$text"
}


# ============================================================================
# Line 1: Provider + Model + Agent + [(Fork)] + Session name + Version
# ============================================================================
line1=()

# Model (colored by tier): prefer display_name, fall back to id
model_show="${model:-$model_id}"

# Cloud provider detection (check model_id for Bedrock prefix, not display_name)
provider=""
shopt -s nocasematch
if [[ "$model_id" =~ ^(global|jp|us|eu|au|apac)\. ]] || [[ "${CLAUDE_CODE_USE_BEDROCK:-}" == "1" ]]; then
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
    fetch_subscription
    if has_val "$_sub_type"; then
      line1+=("${ANTH}Anthropic(${_sub_type})${RST}")
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

# Agent name
if has_val "$agent_name"; then
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
# Version
if has_val "$cc_version"; then
  line1+=("${DIMVER}v${cc_version}${RST}")
fi
# Session indicator (after version)
if $is_branch; then
  line1+=("${YLW}(branch)${RST}")
elif ! has_val "$session_name"; then
  line1+=("${DIM}(no name)${RST}")
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

# Directory path (project_dir → current_dir when different)
if has_val "$project_dir"; then
  short_proj="${project_dir/#$HOME/~}"
  osc8 "vscode://file/${project_dir}" "$short_proj" _osc_tmp
  line2+=("$_osc_tmp")
  if [[ "$current_dir" != "$project_dir" ]]; then
    short_cwd="${current_dir/#$HOME/~}"
    osc8 "vscode://file/${current_dir}" "$short_cwd" _osc_tmp
    line2+=("${DIM}→${RST} $_osc_tmp")
  fi
else
  short_path="${current_dir/#$HOME/~}"
  osc8 "vscode://file/${current_dir}" "$short_path" _osc_tmp
  line2+=("$_osc_tmp")
fi

# Git info (strip repo name if same as dir basename to avoid redundancy)
_git_root="${project_dir:-$current_dir}"
if [[ -n "$git_cached" ]]; then
  dir_basename="${_git_root##*/}"
  # repo_name is always plain text at start of git_cached (no ANSI prefix)
  repo_name="${git_cached%% *}"
  if [[ "$dir_basename" == "$repo_name" ]]; then
    if [[ "$git_cached" == *" "* ]]; then
      # Remove repo name prefix (keep branch + state + trailing 🌲)
      git_cached="${git_cached#*" "}"
    else
      # No branch info — repo name only, skip to avoid redundancy
      git_cached=""
    fi
  fi
  [[ -n "$git_cached" ]] && line2+=("$git_cached")
else
  # No cached git info — check if truly non-git using pure bash (no fork)
  if [[ ! -d "${_git_root}/.git" && ! -f "${_git_root}/.git" ]]; then
    line2+=("${DIM}(no git)${RST}")
  else
    # Cold start: read branch from .git/HEAD (pure bash, no fork)
    _head_file="${_git_root}/.git"
    if [[ -f "$_head_file" ]]; then
      # Worktree: .git is a file → follow gitdir pointer
      _gitdir_line=$(<"$_head_file")
      _gitdir="${_gitdir_line#gitdir: }"
      if [[ "$_gitdir" != /* ]]; then
        _head_file="${_git_root}/${_gitdir}/HEAD"
      else
        _head_file="${_gitdir}/HEAD"
      fi
    else
      _head_file="${_head_file}/HEAD"
    fi
    if [[ -f "$_head_file" ]]; then
      _head=$(<"$_head_file")
      if [[ "$_head" == ref:* ]]; then
        line2+=("${GRN}(${_head#ref: refs/heads/})${RST}")
      else
        line2+=("${RED}(HEAD@${_head:0:7})${RST}")
      fi
    fi
  fi
fi


# ============================================================================
# Line 3: Context bar
# ============================================================================
line3=()

# Context bar
if has_val "$used_pct"; then
  pct_int=${used_pct%.*}
  color_by_threshold "$pct_int" 90 80 ctx_color
  progress_bar "$pct_int" _bar
  ctx_text="${ctx_color}${_bar} ${pct_int}%${RST}"
  # Only warn on 200K models (not 1M)
  [[ "$exceeds_200k" == "true" && "$ctx_window_size" -le 200000 ]] && ctx_text+=" ${RED}⚠ 200K超${RST}"
  line3+=("$ctx_text")
else
  line3+=("${DIM}○○○○○○○○○○ -%${RST}")
fi

# ============================================================================
# Line 4: Rate Limit (Anthropic) / Cost & Tokens (Bedrock/Vertex/Foundry)
# ============================================================================
line4=()
if [[ -n "$provider" ]]; then
  # --- Pay-per-use providers: show session cost & token counts ---
  if has_val "$cost_usd"; then
    printf -v cost_fmt '%.2f' "$cost_usd"
    line4+=("${AMBER}\$${cost_fmt}${RST}")
  fi
  if has_val "$total_in_tok"; then
    format_tokens "$total_in_tok" _ft
    line4+=("${TEAL}↑${_ft}${RST}")
  fi
  if has_val "$total_out_tok"; then
    format_tokens "$total_out_tok" _ft
    line4+=("${CORAL}↓${_ft}${RST}")
  fi
else
  # --- Anthropic: show rate limit from usage API ---
  fetch_usage
  if [[ -n "$_usage_json" ]]; then
    five_pct="" five_reset_iso="" seven_pct="" seven_reset_iso=""
    eval "$(jq -r '
      @sh "five_pct=\((.five_hour.utilization // 0) | round)",
      @sh "five_reset_iso=\(.five_hour.resets_at // "")",
      @sh "seven_pct=\((.seven_day.utilization // 0) | round)",
      @sh "seven_reset_iso=\(.seven_day.resets_at // "")"
    ' <<< "$_usage_json" 2>/dev/null)" || true

    if has_val "$five_pct"; then
      format_reset_remaining "$five_reset_iso"
      progress_bar "$five_pct" _bar
      line4+=("${ANTH}${_bar}${RST} ${ANTH}${five_pct}%${RST}")
      [[ -n "$_reset" ]] && line4+=("${ANTH}${_reset}${RST}")
    fi

    if has_val "$seven_pct" && ((seven_pct > 0)); then
      format_reset_absolute "$seven_reset_iso"
      line4+=("${DIM}week:${seven_pct}%${RST}")
      [[ -n "$_reset" ]] && line4+=("${DIM}${_reset}${RST}")
    fi
  fi
fi

# ============================================================================
# Output
# ============================================================================
printf '%s\n' "${line1[*]}"
printf '%s\n' "${line2[*]}"
printf '%s\n' "${line3[*]}"
[[ ${#line4[@]} -gt 0 ]] && printf '%s\n' "${line4[*]}"

exit 0
