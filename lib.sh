#!/bin/bash
# lib.sh — shared colors + presentation helpers.
# Sourced by both statusline-command.sh (main statusLine) and
# subagent-statusline-command.sh (agent-panel subagentStatusLine).
# Meant to be `source`d, not executed. Defines readonly color constants and
# fork-free helper functions (printf -v pattern) only — no side effects at load,
# no network, no cache/date. Main-only constants (cache dirs, _NOW) and
# stateful helpers (git/credentials/fetch) stay in statusline-command.sh.

# --- Colors ---
readonly RST=$'\033[0m' GRN=$'\033[32m' YLW=$'\033[33m' RED=$'\033[31m'
readonly CTX_OK=$'\033[38;5;82m'
readonly DIM=$'\033[2m'
readonly ANTH=$'\033[38;5;180m' BDCK=$'\033[38;5;72m' VTEX=$'\033[38;5;33m' FNDY=$'\033[38;5;39m'
readonly GIT=$'\033[38;5;202m'
readonly CORAL=$'\033[38;5;173m' TEAL=$'\033[38;5;79m' AMBER=$'\033[38;5;214m' LAVENDER=$'\033[38;5;183m'
readonly AGENT=$'\033[38;5;213m' DIMVER=$'\033[38;5;248m'
readonly EFFORT=$'\033[38;5;105m' THINK=$'\033[38;5;117m'
readonly FAST=$'\033[38;5;190m'  # fast mode — greenyellow, 非ブランド(速度感)。fast は Opus 専用なので model coral と同一行でも色相が離れ衝突しにくい。EFFORT/THINK 同様 tunable
readonly SPEND=$'\033[38;5;220m'  # extra-usage (usage-credits) 実課金額 — gold, 非ブランド
readonly DRAFT=$'\033[38;5;245m'  # PR review_state=draft — GitHub の draft バッジ準拠のニュートラルグレー, 非ブランド
# vim mode badges: bold + bg color + black fg — louder than Claude Code's footer "-- INSERT --" hint.
# Colors follow gruvbox / vim-airline convention (lime green + gold) for instant recognition.
readonly VIM_INSERT=$'\033[1;30;48;5;148m'  # bold black on lime-green (gruvbox-ish INSERT)
readonly VIM_VISUAL=$'\033[1;30;48;5;214m'  # bold black on gold (gruvbox-ish VISUAL)

# Claude Code worktree レイアウトの marker（外部契約文字列）。両 statusline が参照し drift を防ぐ。
readonly WT_MARKER='/.claude/worktrees/'

# --- Helpers (fork-free: printf -v / [[ ]] only) ---
has_val() { [[ -n "$1" && "$1" != "null" ]]; }

# osc8 URL TEXT VARNAME — sets VARNAME to OSC 8 hyperlink (no subshell)
osc8() { printf -v "$3" '\033]8;;%s\a%s\033]8;;\a' "$1" "$2"; }

# editor_url PATH VARNAME — sets VARNAME to file:// URL for OSC 8 hyperlink (no subshell)
editor_url() { printf -v "$2" 'file://%s' "$1"; }

# rainbow VARNAME TEXT — sets VARNAME to TEXT with each char cycling through a
# multi-color palette (no subshell). Used for Fable: no official brand color, so the
# palette is sampled from its announcement artwork (a vintage butterfly-specimen plate)
# — a warm gold→rust→red→olive→green→teal cycle — to make it recognizable on Line 1.
rainbow() {
  local _txt="$2" _out="" _i _len=${#2}
  local _pal=(178 172 130 167 143 107 66) _n=7
  for ((_i=0; _i<_len; _i++)); do
    _out+=$'\033[38;5;'"${_pal[_i % _n]}"'m'"${_txt:_i:1}"
  done
  printf -v "$1" '%s%s' "$_out" "$RST"
}

# gradient VARNAME TEXT — sets VARNAME to TEXT with a single sweep across a green
# palette (no subshell). Sonnet 5: no official brand color, so a green gradient
# (from its botanical announcement artwork) distinguishes it from Sonnet 4.6's flat teal.
gradient() {
  local _txt="$2" _out="" _i _len=${#2}
  local _pal=(28 34 70 106 148 154) _n=6 _idx
  for ((_i=0; _i<_len; _i++)); do
    _idx=$(( _len > 1 ? _i * (_n - 1) / (_len - 1) : 0 ))
    _out+=$'\033[38;5;'"${_pal[_idx]}"'m'"${_txt:_i:1}"
  done
  printf -v "$1" '%s%s' "$_out" "$RST"
}

# model_color VARNAME MODEL_SHOW — sets VARNAME to MODEL_SHOW fully rendered in its
# tier color (no subshell). Shared by Line 1 (main) and the subagent rows so both
# use identical model coloring. Handles its own nocasematch scope (bash 3.2-safe).
# Fable/Sonnet 5 have no official flat color → multi-color rainbow/gradient render.
# Sonnet 5 match uses "sonnet 5"/"sonnet-5" (not *sonnet*5* which also hits "4.5").
model_color() {
  local _ms="$2"
  shopt -s nocasematch
  if [[ "$_ms" == *fable* ]]; then
    rainbow "$1" "$_ms"
  elif [[ "$_ms" == *opus* ]]; then
    printf -v "$1" '%s' "${CORAL}${_ms}${RST}"
  elif [[ "$_ms" == *"sonnet 5"* || "$_ms" == *"sonnet-5"* ]]; then
    gradient "$1" "$_ms"
  elif [[ "$_ms" == *sonnet*4.5* || "$_ms" == *sonnet*3.5* || "$_ms" == *sonnet*4-5* || "$_ms" == *sonnet*3-5* ]]; then
    # display_name ("Sonnet 4.5") と model id ("claude-sonnet-4-5") の両形を拾う
    # (主 statusline は display_name 空時に model_id=dash 形へ fallback するため両形が来る)
    printf -v "$1" '%s' "${AMBER}${_ms}${RST}"
  elif [[ "$_ms" == *sonnet* ]]; then
    printf -v "$1" '%s' "${TEAL}${_ms}${RST}"
  elif [[ "$_ms" == *haiku* ]]; then
    printf -v "$1" '%s' "${LAVENDER}${_ms}${RST}"
  else
    printf -v "$1" '%s' "$_ms"
  fi
  shopt -u nocasematch
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

# format_tokens TOK VARNAME — sets VARNAME to compact token count e.g. 12.3k / 1.5M (no subshell)
format_tokens() {
  local tok=$1
  [[ "$tok" =~ ^[0-9]+$ ]] || { printf -v "$2" '%s' '?'; return; }
  if ((tok >= 1000000)); then printf -v "$2" '%d.%dM' $((tok / 1000000)) $((tok % 1000000 / 100000))
  elif ((tok >= 1000)); then printf -v "$2" '%d.%dk' $((tok / 1000)) $((tok % 1000 / 100))
  else printf -v "$2" '%d' "$tok"
  fi
}
