#!/bin/bash
# Claude Code Statusline — see README.md for details
# https://code.claude.com/docs/en/statusline
set -uo pipefail

# Shared colors + presentation helpers (also used by subagent-statusline-command.sh)
# 相対起動 (bash statusline-command.sh) では BASH_SOURCE にスラッシュが無く %/* が縮まないため "." に fallback
_selfdir="${BASH_SOURCE%/*}"; [[ "$_selfdir" == "$BASH_SOURCE" ]] && _selfdir="."
source "$_selfdir/lib.sh"

# --- Main-only constants ---
readonly CACHE_BASE="/tmp/ist-j-ichikawa-claude-statusline"
readonly GIT_CACHE_DIR="${CACHE_BASE}/git"
readonly GIT_CACHE_MAX_AGE=5
readonly _NOW=$(date +%s)

# --- Main-only helpers (generic presentation helpers — has_val/osc8/editor_url/
# rainbow/gradient/model_color/braille_bar/color_by_threshold/format_tokens — live in lib.sh) ---

# pr_state_color STATE VARNAME — sets VARNAME to ANSI color for PR review state (no subshell)
pr_state_color() {
  case "$1" in
    approved)          printf -v "$2" '%s' "$GRN" ;;
    changes_requested) printf -v "$2" '%s' "$RED" ;;
    pending)           printf -v "$2" '%s' "$YLW" ;;
    draft)             printf -v "$2" '%s' "$DRAFT" ;;
    *)                 printf -v "$2" '%s' "$DIM" ;;
  esac
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

# --- Extra-usage spend (usage-credits, cached, background refresh) ---
# stdin に無い唯一の課金情報。/usage OAuth エンドポイントの spend.used を cents で取得。
# `CLAUDE_STATUSLINE_NO_NET` を設定するとネットワーク取得を止める (オフライン/プライバシー用)。
readonly USAGE_CACHE="${CACHE_BASE}/usage_spend"
readonly USAGE_CACHE_MAX_AGE=300

# fetch_usage_spend — sets _usage_cents (background curl; hot path はキャッシュ読みのみ)
fetch_usage_spend() {
  _usage_cents=""
  [[ -d "$CACHE_BASE" ]] || mkdir -p -m 700 "$CACHE_BASE"
  if [[ -z "${CLAUDE_STATUSLINE_NO_NET:-}" ]] && cache_stale "$USAGE_CACHE" "$USAGE_CACHE_MAX_AGE"; then
    (
      local blob token out cents=0
      blob=$(get_credentials_blob)
      token=$(jq -r '.claudeAiOauth.accessToken // empty' <<< "$blob" 2>/dev/null)
      if [[ -n "$token" ]]; then
        # トークンは --config 経由 stdin で渡す (argv/ps 露出を防ぐ)
        out=$(printf 'header = "Authorization: Bearer %s"\nheader = "anthropic-beta: oauth-2025-04-20"\n' "$token" \
          | curl -s -m 4 --config - https://api.anthropic.com/api/oauth/usage 2>/dev/null)
        cents=$(jq -r '(.spend.used // {}) | ((.amount_minor // 0) / pow(10; (.exponent // 2) - 2)) | round' <<< "$out" 2>/dev/null)
        [[ "$cents" =~ ^[0-9]+$ ]] || cents=0
      fi
      # spend 0 / トークン無し / 取得失敗でも「0」を必ず atomic に書く。書かないと
      # cache_stale が (ファイル不在=stale で) 毎レンダー refetch して curl storm になる
      # (extra-usage 0 のユーザーが大多数なので致命的)。display は 0 を非表示にするので実害なし。
      echo "$cents" > "${USAGE_CACHE}.tmp" && mv "${USAGE_CACHE}.tmp" "$USAGE_CACHE"
    ) & disown
  fi
  [[ -f "$USAGE_CACHE" ]] && _usage_cents=$(<"$USAGE_CACHE")
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
model="" model_id="" current_dir="." used_pct=""
exceeds_200k="false" cc_version="" session_name=""
agent_name="" ctx_window_size=0
five_pct="" five_reset_epoch="" seven_pct="" seven_reset_epoch=""
wt_name="" wt_path="" wt_orig_branch="" added_dirs_count=0 ws_git_worktree=""
ws_repo_host="" ws_repo_owner="" ws_repo_name="" ws_repo_id=""
pr_review_state=""
vim_mode=""
effort_level="" thinking_enabled="false" fast_mode="false"
cost_cents=0
_jq_ok=1
_jq_out=$(jq -r '
  @sh "model=\(.model.display_name // "Unknown")",
  @sh "model_id=\(.model.id // "")",
  @sh "current_dir=\(.workspace.current_dir // ".")",
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
  @sh "thinking_enabled=\(.thinking.enabled // false)",
  @sh "fast_mode=\(.fast_mode // false)",
  @sh "cost_cents=\(.cost.total_cost_usd // 0 | . * 100 | round)"
' <<< "$input" 2>/dev/null) || _jq_ok=0
if ((_jq_ok)); then eval "$_jq_out" || true; fi

# Claude Code 2.1.145+ workspace.repo: precompute "owner/repo" once, share between build_git and cold-start.
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
    # Repo identity: prefer precomputed $ws_repo_id (Claude Code 2.1.145+) — zero fork, available at cold start.
    # Fallback: parse origin URL (SSH/HTTPS → canonical https://github.com/owner/repo) for older Claude Code.
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

    # Origin identifier (before branch) — repo 識別の一次情報。ローカル dir 名と origin repo 名が
    # 食い違うケースはここでしか判別できないため owner/repo は通常輝度、gh: プレフィックスのみ dim。
    [[ -n "$repo_id" ]] && text+="${DIM}gh:${RST}${repo_id} "

    # GitHub tree URL — PR は Claude Code 組み込みフッターの PR badge に任せ、ここは tree URL のみ
    [[ -n "$remote" ]] && link_url="${remote}/tree/${branch}"
    [[ -n "$link_url" ]] && osc8 "$link_url" "$branch" branch_show
    text+="${GIT}${branch_show}${RST}"

    # PR review state (Claude Code 2.1.145+ pr.review_state) — text colored by state.
    # Claude Code's built-in footer already shows "PR #<num>" with link, so we only surface the
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
      text+=" ${DIM}base:${from_ref}${RST}"
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

# Vim mode badge (Claude Code 2.1.x vim.mode) — leftmost so it catches the eye while typing.
# Claude Code's footer shows a dim "-- INSERT --" hint; this badge is intentionally louder.
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
if [[ "$model_id" =~ ^(global|jp|us-gov|us|eu|au|apac)\. ]] || [[ "${CLAUDE_CODE_USE_BEDROCK:-}" == "1" ]] || [[ "${CLAUDE_CODE_USE_MANTLE:-}" == "1" ]]; then
  provider="bedrock"
elif [[ "${CLAUDE_CODE_USE_VERTEX:-}" == "1" ]]; then
  provider="vertex"
elif [[ "${CLAUDE_CODE_USE_FOUNDRY:-}" == "1" ]]; then
  provider="foundry"
fi
shopt -u nocasematch

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

# Model (colored by tier) — 共有 model_color が nocasematch スコープを内部管理する
model_color _model_col "$model_show"
line1+=("$_model_col")

has_val "$effort_level" && line1+=("${EFFORT}${effort_level}${RST}")
[[ "$thinking_enabled" == "true" ]] && line1+=("${THINK}think${RST}")
# fast mode (Claude Code 2.1.216 docs で確認、fast_mode boolean) — /fast 有効時のみ。false/欠落は非表示
[[ "$fast_mode" == "true" ]] && line1+=("${FAST}fast${RST}")

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
# Always use current_dir: the worktree.path override (above) and Claude Code 2.1.176+ keep it
# pointing at the live dir. Do NOT fall back to project_dir — it pins to the launch dir (see CHANGELOG 1.32.0).
_display_dir="$current_dir"
_short_dir="${_display_dir/#$HOME/~}"

# Worktree path split: `<repo>/.claude/worktrees/<name>` はパス末尾がランダムな worktree 名になり
# リポ dir が中程に埋まって「どこの repo か」が読めないため、リポ root と 🌲<name> に分割表示する
# （リンクは root / worktree 各ディレクトリへ）。worktree 内サブディレクトリや既定外配置では
# marker 不一致で分割せずフルパス表示に fallback する。
_wt_marker="$WT_MARKER"   # lib.sh の共有定数（両 statusline で drift 防止）
_is_wt=""
if has_val "$wt_name" || has_val "$ws_git_worktree"; then _is_wt=1; fi
_wt_leaf=""
# `?*` = marker より前に 1 文字以上 — リポが / 直下の極端ケースで root が空になり空リンク要素が出るのを防ぐ
if [[ -n "$_is_wt" && "$_short_dir" == ?*"$_wt_marker"* ]]; then
  _wt_leaf="${_short_dir##*"$_wt_marker"}"
  [[ -z "$_wt_leaf" || "$_wt_leaf" == */* ]] && _wt_leaf=""
fi

if [[ -n "$_wt_leaf" ]]; then
  editor_url "${_display_dir%"$_wt_marker"*}" _editor_url
  osc8 "$_editor_url" "${_short_dir%"$_wt_marker"*}" _osc_tmp
else
  editor_url "$_display_dir" _editor_url
  osc8 "$_editor_url" "$_short_dir" _osc_tmp
fi
line2+=("$_osc_tmp")

# Worktree indicator: Claude Code worktree (wt_name) or git linked worktree (ws_git_worktree, Claude Code 2.1.97+)
# Placed adjacent to the path since it qualifies what the path *is*.
if [[ -n "$_is_wt" ]]; then
  if [[ -n "$_wt_leaf" ]]; then
    editor_url "$_display_dir" _editor_url
    osc8 "$_editor_url" "$_wt_leaf" _osc_tmp
    line2+=("🌲${DIM}${_osc_tmp}${RST}")
  else
    line2+=("🌲")
  fi
  # from:HEAD (detached HEAD から作成) も「detached から切った」事実を示すので表示する
  # (Line 3 base: が reflog GC 等で欠けた時の唯一の切り元シグナルになりうる)
  if has_val "$wt_orig_branch"; then
    line2+=("${DIM}from:${wt_orig_branch}${RST}")
  fi
fi

# Aggregate, not per-basename: per-basename can be truncated at terminal edge,
# hiding which dirs are added. Claude Code 2.1.141 fixed row-drop on overflow but still truncates.
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
      # gh: は detached (raw sha) では出さない — build_git の detached パスと gate を揃えないと
      # cache populate 時に gh: が消えるフリッカーになる (3 パス問題)。
      [[ -n "$ws_repo_id" && "$_head" == ref:* ]] && line_git+=("${DIM}gh:${RST}${ws_repo_id}")
      # .invalid: Git's placeholder ref for empty/uninitialized repos (git init, clone aborted, ghq get失敗残骸)
      if [[ "$_head" == "ref: refs/heads/.invalid" ]]; then
        line_git+=("${DIM}(empty)${RST}")
      elif [[ "$_head" == ref:* ]]; then
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

# 5-hour rate limit (Anthropic only, Claude Code 2.1.80+) — leftmost for quick glance
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

# Extra-usage spend (usage-credits, Anthropic only) — 実課金額。stdin に無いので /usage を背景取得。
# weekly の後・session cost の前に置き、参考値の session cost とは別に「実際に溶けた額」を示す。
if [[ -z "$provider" ]]; then
  fetch_usage_spend
  if [[ "$_usage_cents" =~ ^[0-9]+$ ]] && ((_usage_cents > 0)); then
    printf -v _xtra 'extra:$%d.%02d' $((_usage_cents / 100)) $((_usage_cents % 100))
    line3+=("${SPEND}${_xtra}${RST}")
  fi
fi

# Session cost (全プロバイダー共通。Claude Code 計算済みの API 換算 USD; subscription では実請求なしの参考値)
# cost_cents > 0 が「フィールド欠落 (旧 Claude Code)」と「$0.00」の両方を非表示に倒す
if ((cost_cents > 0)); then
  printf -v _cost '$%d.%02d' $((cost_cents / 100)) $((cost_cents % 100))
  line3+=("${DIM}${_cost}${RST}")
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
