#!/bin/bash
# subagent-statusline-command.sh — agent panel の各サブエージェント行を独自描画する。
# settings.json の "subagentStatusLine" で有効化。色/ヘルパーは lib.sh で主 statusline と共有。
# 詳細は docs/internals.md「Subagent statusline」参照。
#
# 契約 (Claude Code docs): stdin = `columns` + `tasks[]` を持つ 1 個の JSON。
# stdout = 上書きしたい行ごとに JSON 1 行 `{"id":..,"content":..}`。id を省いた行は既定描画のまま。
# content は ANSI / OSC 8 をそのまま解釈。model/contextWindowSize は 2.1.205+、effort は 2.1.214+。
#
# 行 = 説明 + モデル(pretty・tier色) + context%バー + 状態(↑/▪/✓/status語) + 経過 + [🌲worktree]。
# 端末幅での切り詰めはしない方針 (主 statusline と同じ。全要素フル出力・折り返し/切れは端末に委ねる)。
set -uo pipefail
# 相対起動でも解決できるよう %/* が縮まない (スラッシュ無し) 場合は "." に fallback
_selfdir="${BASH_SOURCE%/*}"; [[ "$_selfdir" == "$BASH_SOURCE" ]] && _selfdir="."
source "$_selfdir/lib.sh"

IFS= read -r -d '' input || true
[[ -z "$input" ]] && exit 0

_now=$(date +%s)   # 経過時間用に 1 回だけ (主 statusline の _NOW と同じく 1 date fork)

# per-task を単一 jq で US(0x1f) 区切り抽出。grow(伸び) は tokenSamples の末尾と数点前を比較して算出。
# 区切りに tab を使うと read の IFS=tab が空フィールドを潰して桁ずれするため非空白の US を使う。
# 自由入力 (label) は改行/タブを空白へ潰し 1 行 = 1 task を保つ。
_rows=$(jq -r '.tasks[]? | [
  (.id // "" | gsub("[\n\r\t]"; " ")),
  (.label // .description // .name // "" | gsub("[\n\r\t]"; " ")),
  (.model // "" | gsub("[\n\r\t]"; " ")),
  (.status // "" | gsub("[\n\r\t]"; " ")),
  (.tokenCount // 0 | tostring),
  (.contextWindowSize // 0 | tostring),
  (.startTime // 0 | tostring),
  ((.tokenSamples // []) | if length >= 2 then (if .[-1] > (.[-4] // .[0]) then "1" else "0" end) else "0" end),
  (.cwd // "" | gsub("[\n\r\t]"; " "))
] | join("\u001f")' <<< "$input" 2>/dev/null) || exit 0
[[ -z "$_rows" ]] && exit 0

# model id -> "Opus 4.8" 風 (Line 1 の display_name と協調、fork-free)。claude- 接頭辞と [1m] 接尾辞を除く。
prettify_model() {
  local m="${1#claude-}"; m="${m%\[1m\]}"
  local tier="${m%%-*}" ver="${m#*-}" _t
  [[ "$ver" == "$tier" ]] && ver=""
  ver="${ver//-/.}"
  case "$tier" in opus)_t=Opus;;sonnet)_t=Sonnet;;haiku)_t=Haiku;;fable)_t=Fable;;*)_t="$tier";;esac
  printf -v "$2" '%s%s' "$_t" "${ver:+ $ver}"
}

# 秒 -> "45s"/"3m"/"1h03m" (Line 3 の commit age と協調。dim・コンパクト単一/二連単位)
fmt_elapsed() {
  local s=$1
  if   ((s < 60));   then printf -v "$2" '%ds' "$s"
  elif ((s < 3600)); then printf -v "$2" '%dm' $((s / 60))
  else printf -v "$2" '%dh%02dm' $((s / 3600)) $(((s % 3600) / 60)); fi
}

# here-string 供給なのでループは現シェル (サブシェル無し・_out に蓄積)。
_out=""
while IFS=$'\037' read -r id label model status tok ctx start grow cwd; do
  [[ -z "$id" ]] && continue
  # 説明 (先頭・通常輝度・切り詰めなし)
  row="$label"
  # モデル (pretty-name + tier 色)
  if has_val "$model"; then
    prettify_model "$model" _pm
    model_color _mc "$_pm"
    row+="${row:+  }${_mc}"
  fi
  # context 使用率バー + % (主 Line 4 と同じ braille + 閾値色)
  if [[ "$ctx" =~ ^[0-9]+$ ]] && (( ctx > 0 )) && [[ "$tok" =~ ^[0-9]+$ ]]; then
    pct=$(( tok * 100 / ctx )); (( pct > 100 )) && pct=100
    braille_bar "$pct" _bar; color_by_threshold "$pct" 90 80 _bc   # 主 Line 4 と同一閾値 (黄≥80/赤≥90)
    row+="  ${_bc}${_bar}${RST} ${DIM}${pct}%${RST}"
  fi
  # 状態グリフ: status + 伸び。running は ↑(伸び中)/▪(頭打ち)、completed は ✓、
  # それ以外 (入力待ち等の未知値) は生の値を黄で表示 (取りこぼし防止・PR review_state と同じ作法)。
  case "$status" in
    running)   [[ "$grow" == "1" ]] && row+="  ${CTX_OK}↑${RST}" || row+="  ${DIM}▪${RST}" ;;
    completed) row+="  ${DIM}✓${RST}" ;;
    "")        : ;;
    *)         row+="  ${YLW}${status}${RST}" ;;
  esac
  # 経過時間 (startTime は epoch ミリ秒)
  if [[ "$start" =~ ^[0-9]+$ ]] && (( start > 0 )); then
    _els=$(( _now - start / 1000 )); (( _els < 0 )) && _els=0
    fmt_elapsed "$_els" _el; row+="  ${DIM}${_el}${RST}"
  fi
  # worktree: cwd が .claude/worktrees 配下の時だけ 🌲名 (Line 2 の worktree 表示と協調)
  if [[ "$cwd" == */.claude/worktrees/* ]]; then
    _wt="${cwd##*/.claude/worktrees/}"; _wt="${_wt%%/*}"
    has_val "$_wt" && row+="  ${DIM}🌲${_wt}${RST}"
  fi
  [[ -z "$row" ]] && continue
  _out+="${id}"$'\037'"${row}"$'\n'
done <<< "$_rows"

# JSON lines を単一 jq で出力 (id/content を US で分割)。ESC/引用符/バックスラッシュは jq が安全にエスケープ。
[[ -n "$_out" ]] && printf '%s' "$_out" | jq -Rc 'split("\u001f") | {id: .[0], content: .[1]}'
exit 0
