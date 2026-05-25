#!/bin/bash
# Claude Code Statusline — see README.md for details
# https://code.claude.com/docs/en/statusline
set -uo pipefail

# --- Constants ---
readonly RST=$'\033[0m' GRN=$'\033[32m' YLW=$'\033[33m' RED=$'\033[31m'
readonly CTX_OK=$'\033[38;5;82m'
readonly DIM=$'\033[2m'
readonly ANTH=$'\033[38;5;180m' BDCK=$'\033[38;5;72m' VTEX=$'\033[38;5;33m' FNDY=$'\033[38;5;39m'
readonly GIT=$'\033[38;5;202m'
readonly CORAL=$'\033[38;5;209m' TEAL=$'\033[38;5;79m' AMBER=$'\033[38;5;214m' LAVENDER=$'\033[38;5;183m'
readonly AGENT=$'\033[38;5;213m' DIMVER=$'\033[38;5;248m'
readonly EFFORT=$'\033[38;5;105m' THINK=$'\033[38;5;117m'
# vim mode badges: bold + bg color + black fg — louder than CC's footer "-- INSERT --" hint.
# Colors follow gruvbox / vim-airline convention (lime green + gold) for instant recognition.
readonly VIM_INSERT=$'\033[1;30;48;5;148m'  # bold black on lime-green (gruvbox-ish INSERT)
readonly VIM_VISUAL=$'\033[1;30;48;5;214m'  # bold black on gold (gruvbox-ish VISUAL)
readonly CACHE_BASE="/tmp/ist-j-ichikawa-claude-statusline"
readonly GIT_CACHE_DIR="${CACHE_BASE}/git"
readonly GIT_CACHE_MAX_AGE=5
readonly _NOW=$(date +%s)

# --- Helpers ---
has_val() { [[ -n "$1" && "$1" != "null" ]]; }

# osc8 URL TEXT VARNAME — sets VARNAME to OSC 8 hyperlink (no subshell)
osc8() { printf -v "$3" '\033]8;;%s\a%s\033]8;;\a' "$1" "$2"; }

# editor_url PATH VARNAME — sets VARNAME to file:// URL for OSC 8 hyperlink (no subshell)
editor_url() { printf -v "$2" 'file://%s' "$1"; }

# pr_state_color STATE VARNAME — sets VARNAME to ANSI color for PR review state (no subshell)
pr_state_color() {
  case "$1" in
    approved)          printf -v "$2" '%s' "$GRN" ;;
    changes_requested) printf -v "$2" '%s' "$RED" ;;
    pending)           printf -v "$2" '%s' "$YLW" ;;
    *)                 printf -v "$2" '%s' "$DIM" ;;
  esac
}

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

# color_by_threshold VAL HI MID VARNAME — sets VARNAME to context-bar color (no subshell)
# OK = lime green (CTX_OK), distinct from Bedrock teal and standard ANSI green
color_by_threshold() {
  local val=$1 hi=$2 mid=$3
  [[ "$val" =~ ^[0-9]+$ ]] || { printf -v "$4" '%s' "$DIM"; return; }
  if ((val >= hi)); then printf -v "$4" '%s' "$RED"
  elif ((val >= mid)); then printf -v "$4" '%s' "$YLW"
  else printf -v "$4" '%s' "$CTX_OK"; fi
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
# 5h rate limit 専用: diff は最大5時間なので H:MM 固定
format_reset_remaining() {
  _reset=""
  local epoch=$1
  [[ -z "$epoch" || "$epoch" == "null" ]] && return
  [[ "$epoch" =~ ^[0-9]+$ ]] || return
  local diff=$((epoch - _NOW))
  if ((diff <= 0)); then _reset="now"; return; fi
  local h=$((diff / 3600)) m=$(( (diff % 3600) / 60 ))
  printf -v _reset '%d:%02d' "$h" "$m"
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
ws_repo_host="" ws_repo_owner="" ws_repo_name="" ws_repo_id=""
pr_review_state=""
vim_mode=""
effort_level="" thinking_enabled="false"
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
  @sh "ws_git_worktree=\(.workspace.git_worktree // "")",
  @sh "ws_repo_host=\(.workspace.repo.host // "")",
  @sh "ws_repo_owner=\(.workspace.repo.owner // "")",
  @sh "ws_repo_name=\(.workspace.repo.name // "")",
  @sh "pr_review_state=\(.pr.review_state // "")",
  @sh "vim_mode=\(.vim.mode // "")",
  @sh "effort_level=\(.effort.level // "")",
  @sh "thinking_enabled=\(.thinking.enabled // false)"
' <<< "$input" 2>/dev/null) || _jq_ok=0
if ((_jq_ok)); then eval "$_jq_out" || true; fi

# CC 2.1.145+ workspace.repo: precompute "owner/repo" once, share between build_git and cold-start.
# Empty unless stdin actually provided a GitHub repo identity — both call sites use this as the gate.
if [[ "$ws_repo_host" == "github.com" ]] && has_val "$ws_repo_owner" && has_val "$ws_repo_name"; then
  ws_repo_id="${ws_repo_owner}/${ws_repo_name}"
fi

# worktree sessions: workspace.current_dir points to original repo
if [[ -n "$wt_path" ]]; then
  current_dir="$wt_path"
fi

# --- Git info (5s cached) ---
build_git() {
  local dir=$1 text="" branch

  branch=$(git -C "$dir" branch --show-current 2>/dev/null)

  # Detached HEAD
  if [[ -z "$branch" ]]; then
    local short_sha
    short_sha=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
    [[ -n "$short_sha" ]] && branch="HEAD@${short_sha}"
  fi

  # Not a git repo (or fresh repo with no commits): nothing to show
  [[ -z "$branch" ]] && return

  if [[ "$branch" == HEAD@* ]]; then
    text+="${RED}${branch}${RST}"
  else
    # Repo identity: prefer precomputed $ws_repo_id (CC 2.1.145+) — zero fork, available at cold start.
    # Fallback: parse origin URL (SSH/HTTPS → canonical https://github.com/owner/repo) for older CC.
    local remote repo_id="$ws_repo_id" link_url="" branch_show="$branch"
    if [[ -n "$repo_id" ]]; then
      remote="https://github.com/${repo_id}"
    else
      remote=$(git -C "$dir" remote get-url origin 2>/dev/null)
      case "$remote" in
        git@github.com:*)        remote="https://github.com/${remote#git@github.com:}" ;;
        ssh://git@github.com/*)  remote="https://github.com/${remote#ssh://git@github.com/}" ;;
        https://github.com/*)    ;;
        *)                       remote="" ;;
      esac
      remote="${remote%.git}"
      [[ -n "$remote" ]] && repo_id="${remote#https://github.com/}"
    fi

    # Origin identifier (dim, before branch) — "GitHub に上げたっけ" の即答用
    [[ -n "$repo_id" ]] && text+="${DIM}gh:${repo_id}${RST} "

    # GitHub tree URL — PR は CC 組み込みフッターの PR badge に任せ、ここは tree URL のみ
    [[ -n "$remote" ]] && link_url="${remote}/tree/${branch}"
    [[ -n "$link_url" ]] && osc8 "$link_url" "$branch" branch_show
    text+="${GIT}${branch_show}${RST}"

    # PR review state (CC 2.1.145+ pr.review_state) — text colored by state.
    # CC's built-in footer already shows "PR #<num>" with link, so we only surface the
    # review_state (which the footer omits) to keep the two displays complementary.
    if has_val "$pr_review_state"; then
      local pr_color
      pr_state_color "$pr_review_state" pr_color
      text+=" ${pr_color}${pr_review_state}${RST}"
    fi

    # Branch parent — reflog は ~90 日で GC; 古いブランチや clone 直後は出ない (graceful degradation)
    local last_reflog from_ref=""
    last_reflog=$(git -C "$dir" reflog show "$branch" 2>/dev/null | tail -1)
    if [[ "$last_reflog" == *": branch: Created from "* ]]; then
      from_ref="${last_reflog##*: branch: Created from }"
    fi
    if [[ -n "$from_ref" && "$from_ref" != "HEAD" ]]; then
      text+=" ${DIM}from:${from_ref}${RST}"
    fi
  fi

  # Dirty state: staged(green) / modified(yellow) / untracked(gray) / conflicts(red)
  # NOTE: `grep -c .` は no-match でも "0" を出力してから exit 1 する。`|| echo 0` を付けると
  # pipefail 環境下で stdout が "0\n0" になり ((var > 0)) が syntax error を吐く。grep -c 単体で十分。
  local staged modified untracked conflicts
  staged=$(git -C "$dir" diff --cached --name-only 2>/dev/null | grep -c .)
  modified=$(git -C "$dir" diff --name-only 2>/dev/null | grep -c .)
  untracked=$(git -C "$dir" ls-files --others --exclude-standard 2>/dev/null | grep -c .)
  conflicts=$(git -C "$dir" diff --name-only --diff-filter=U 2>/dev/null | grep -c .)
  ((conflicts > 0)) && text+=" ${RED}U${conflicts}${RST}"
  ((staged > 0))    && text+=" ${GRN}A${staged}${RST}"
  ((modified > 0))  && text+=" ${YLW}M${modified}${RST}"
  ((untracked > 0)) && text+=" ${DIMVER}?${untracked}${RST}"

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

# Vim mode badge (CC 2.1.x vim.mode) — leftmost so it catches the eye while typing.
# CC's footer shows a dim "-- INSERT --" hint; this badge is intentionally louder.
# NORMAL is hidden (it's the default — showing it adds noise).
case "$vim_mode" in
  INSERT)        line1+=("${VIM_INSERT} INSERT ${RST}") ;;
  VISUAL)        line1+=("${VIM_VISUAL} VISUAL ${RST}") ;;
  "VISUAL LINE") line1+=("${VIM_VISUAL} V-LINE ${RST}") ;;
esac

# Model (colored by tier): prefer display_name, fall back to id
model_show="${model:-$model_id}"

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

has_val "$effort_level" && line1+=("${EFFORT}${effort_level}${RST}")
[[ "$thinking_enabled" == "true" ]] && line1+=("${THINK}think${RST}")

# Agent name
if has_val "$agent_name"; then
  line1+=("${AGENT}${agent_name}${RST}")
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
# Session indicator
if $is_branch; then
  line1+=("${YLW}branch${RST}")
fi

# ============================================================================
# Line 2: Dir + Worktree
# ============================================================================
line2=()

# Directory path (full display — no truncation)
_display_dir="${project_dir:-$current_dir}"
_short_dir="${_display_dir/#$HOME/~}"
editor_url "$_display_dir" _editor_url
osc8 "$_editor_url" "$_short_dir" _osc_tmp
line2+=("$_osc_tmp")

# Worktree indicator: CC worktree (wt_name) or git linked worktree (ws_git_worktree, CC 2.1.97+)
# Placed adjacent to the path since it qualifies what the path *is*.
if has_val "$wt_name" || has_val "$ws_git_worktree"; then
  line2+=("🌲")
  if has_val "$wt_orig_branch"; then
    line2+=("${DIM}from:${wt_orig_branch}${RST}")
  fi
fi

# Aggregate, not per-basename: per-basename can be truncated at terminal edge,
# hiding which dirs are added. CC 2.1.141 fixed row-drop on overflow but still truncates.
if ((added_dirs_count > 0)); then
  line2+=("${DIM}(+${added_dirs_count} dirs)${RST}")
fi

# ============================================================================
# Line 3: Git info (separated from Line 2 to avoid overflow)
# ============================================================================
line_git=()

# Git info (background refresh)
git_cache_file "$current_dir"
if cache_stale "$_gc" "$GIT_CACHE_MAX_AGE"; then
  ( [[ -d "$GIT_CACHE_DIR" ]] || mkdir -p -m 700 "$GIT_CACHE_DIR"
    build_git "$current_dir" > "${_gc}.tmp" && mv "${_gc}.tmp" "$_gc" ) & disown
fi
[[ -f "$_gc" ]] && git_cached=$(<"$_gc") || git_cached=""

if [[ -n "$git_cached" ]]; then
  line_git+=("$git_cached")
else
  # No cached git info — check if truly non-git using pure bash (no fork)
  if [[ ! -d "${_display_dir}/.git" && ! -f "${_display_dir}/.git" ]]; then
    line_git+=("${DIM}no git${RST}")
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
      # Cold-start emits a stdin-only subset of build_git's layout, in the same left-to-right order
      # (gh: → branch → PR state). build_git wins once the 5s background cache populates.
      [[ -n "$ws_repo_id" ]] && line_git+=("${DIM}gh:${ws_repo_id}${RST}")
      if [[ "$_head" == ref:* ]]; then
        line_git+=("${GIT}${_head#ref: refs/heads/}${RST}")
      else
        line_git+=("${RED}HEAD@${_head:0:7}${RST}")
      fi
      if has_val "$pr_review_state"; then
        pr_state_color "$pr_review_state" _pr_color
        line_git+=("${_pr_color}${pr_review_state}${RST}")
      fi
    fi
  fi
fi


# ============================================================================
# Line 4: Context + Rate Limit (Anthropic)
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
if [[ -z "$provider" ]] && has_val "$seven_pct" && ((seven_pct > 0)); then
  format_reset_absolute "$seven_reset_epoch"
  line3+=("${DIM}week:${seven_pct}%${RST}")
  [[ -n "$_reset" ]] && line3+=("${DIM}${_reset}${RST}")
fi

# ============================================================================
# Output — single write() for atomic pipe delivery
# ============================================================================
_l1="${line1[*]}" _l2="${line2[*]}" _lg="${line_git[*]}" _l3="${line3[*]}"
if [[ -n "$_lg" ]]; then
  _out="${_l1}"$'\n'"${_l2}"$'\n'"${_lg}"$'\n'"${_l3}"
else
  _out="${_l1}"$'\n'"${_l2}"$'\n'"${_l3}"
fi
printf '%s\n' "$_out"

exit 0
