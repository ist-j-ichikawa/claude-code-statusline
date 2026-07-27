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
readonly CORAL_N=173   # Opus の粘土コーラル。SGR 文字列と OPUS5_PAL の両方がここから派生する
readonly CORAL=$'\033[38;5;'"${CORAL_N}"'m' TEAL=$'\033[38;5;79m' AMBER=$'\033[38;5;214m' LAVENDER=$'\033[38;5;183m'
# 公式単色が無いモデルのアートワーク由来パレット (rainbow=文字ごとの循環 / gradient=1回スイープ)。
# 公式色が claude.ai に現れたら flat 単色へ差し替える前提の暫定色。
readonly FABLE_PAL=(178 172 130 167 143 107 66)   # Fable: 蝶標本図版 — 暖色循環 gold→amber→rust→red→olive→green→teal
readonly SONNET5_PAL=(28 70 148 154)              # Sonnet 5: 植物モチーフ — 濃緑→黄緑
# Opus 5: 鳥卵標本図版 (支配色が無いので単色を選べない)。Sonnet 5 と同じ「単色相を暗→明にスイープ」構造で、
# 色相を Opus の coral 一族に取る: dark orange→CORAL→gold。彩度と明度レンジを稼ぐのが要点 —
# 実測に忠実な低彩度の tan/olive はターミナルでくすんで「グラデーション」に見えなかった (v1.50.0 で差し替え)。
# 両端とも mid/high 彩度なので light テーマでも飛ばない (near-white の 216/223 は不可)。
# **ストップは知覚明度で 30 以上離す** — 隣接ストップの明度差が 10 未満だと見分けられず、スロットの無駄に
# なる (v1.53.0 までの 5 ストップ版は 130/166 と 173/209 が各 8.5 差でほぼ同色。実質 3 段だった)。
readonly OPUS5_PAL=(130 $CORAL_N 215)
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

# rainbow  VARNAME TEXT COLOR... — 文字ごとにパレットを循環。順序に意味が無いパレット向け
#   (Fable: 蝶標本の多色を均等に出したい)。
# gradient VARNAME TEXT COLOR... — パレットを1回スイープ。順序に意味があるパレット向け
#   (Sonnet 5 / Opus 5: 暗→明の方向が絵になる)。先頭文字は必ずパレット先頭色になるが、
#   それ以外の色位置は文字数依存なので特定の語には固定できない。
# どちらも fork ゼロ (printf -v)。パレット未指定なら無色テキストへ degrade —
# 呼び出しは ${PAL[@]+"${PAL[@]}"} で展開すること (bash 3.2 の set -u は空配列の "${a[@]}" で即死し、
# _paint の空パレットガードに到達する前に statusline 全体が空白になる)。
rainbow()  { _paint 0 "$@"; }
gradient() { _paint 1 "$@"; }
_paint() {
  local _sweep=$1 _vn="$2" _txt="$3" _out="" _i _len=${#3} _idx
  shift 3                          # 以降 "$@" = パレット (変数名は先に _vn へ退避済み)
  local _pal=("$@") _n=$#
  (( _n == 0 )) && { printf -v "$_vn" '%s' "$_txt"; return; }
  for ((_i=0; _i<_len; _i++)); do
    # sweep の添字は四捨五入。切り捨てだと最終ストップが末尾 1 文字にしか載らず
    # (35 字の Bedrock id で 17/17/1 字)、一番明るい色がほぼ見えなくなる
    _idx=$(( _sweep ? (_len > 1 ? (2 * _i * (_n - 1) + _len - 1) / (2 * (_len - 1)) : 0) : _i % _n ))
    _out+=$'\033[38;5;'"${_pal[_idx]}"'m'"${_txt:_i:1}"
  done
  printf -v "$_vn" '%s%s' "$_out" "$RST"
}

# model_color VARNAME MODEL_SHOW [MODEL_ID] — sets VARNAME to MODEL_SHOW fully rendered in its
# tier color (no subshell). Shared by Line 1 (main) and the subagent rows so both
# use identical model coloring. Handles its own nocasematch scope (bash 3.2-safe).
# Fable/Sonnet 5/Opus 5 have no official flat color → multi-color rainbow/gradient render.
# 5-tier match uses "opus 5"/"opus-5" (not *opus*5* which also hits "Opus 4.5"), same for
# Sonnet 5. Both must be tested BEFORE the generic *opus*/*sonnet* flat-color branches.
# Tier 判定は MODEL_SHOW + MODEL_ID の連結で行い、描画は MODEL_SHOW のみ — display_name が版を
# 含まない形 ("Opus"/"Sonnet") で来ても id 側の "claude-opus-5" で拾い、Line 1 と subagent 行が
# 同じ tier 色に収まる (subagent 側は id しか持たないため、片側だけ版を見ると色が食い違う)。
model_color() {
  local _ms="$2" _key="$2|${3:-}"   # 区切りは非空白 — 空白だと "Opus"+"5-…" が跨って "opus 5" に化ける
  shopt -s nocasematch
  if [[ "$_key" == *fable* ]]; then
    rainbow "$1" "$_ms" ${FABLE_PAL[@]+"${FABLE_PAL[@]}"}
  elif [[ "$_key" == *"opus 5"* || "$_key" == *"opus-5"* ]]; then
    gradient "$1" "$_ms" ${OPUS5_PAL[@]+"${OPUS5_PAL[@]}"}
  elif [[ "$_key" == *opus* ]]; then
    printf -v "$1" '%s' "${CORAL}${_ms}${RST}"
  elif [[ "$_key" == *"sonnet 5"* || "$_key" == *"sonnet-5"* ]]; then
    gradient "$1" "$_ms" ${SONNET5_PAL[@]+"${SONNET5_PAL[@]}"}
  elif [[ "$_key" == *sonnet*4.5* || "$_key" == *sonnet*3.5* || "$_key" == *sonnet*4-5* || "$_key" == *sonnet*3-5* ]]; then
    # display_name ("Sonnet 4.5") と model id ("claude-sonnet-4-5") の両形を拾う
    # (主 statusline は display_name 空時に model_id=dash 形へ fallback するため両形が来る)
    printf -v "$1" '%s' "${AMBER}${_ms}${RST}"
  elif [[ "$_key" == *sonnet* ]]; then
    printf -v "$1" '%s' "${TEAL}${_ms}${RST}"
  elif [[ "$_key" == *haiku* ]]; then
    printf -v "$1" '%s' "${LAVENDER}${_ms}${RST}"
  else
    printf -v "$1" '%s' "$_ms"
  fi
  shopt -u nocasematch
}

# fmt_elapsed SECONDS VARNAME — 経過秒を "3m" / "1h03m" / "27h" にする (no subshell)。
# Line 3 の commit age と同じコンパクト表記。1 時間未満は分のみ、以降は時+分。
fmt_elapsed() {
  local s=$1
  [[ "$s" =~ ^[0-9]+$ ]] || { printf -v "$2" '%s' ''; return; }
  if   ((s < 3600));  then printf -v "$2" '%dm' $((s / 60))
  elif ((s < 86400)); then printf -v "$2" '%dh%02dm' $((s / 3600)) $(((s % 3600) / 60))
  else printf -v "$2" '%dh' $((s / 3600)); fi
}

# fmt_ctx_size TOKENS VARNAME — コンテキスト窓の分母表記 ("500k" / "1M" / "1.5M")。
# format_tokens は必ず小数 1 桁を出す ("1.0M") が、分母では ".0" が邪魔なので落とす。
fmt_ctx_size() {
  format_tokens "$1" "$2"
  local _v="${!2}"
  printf -v "$2" '%s' "${_v/.0/}"
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
