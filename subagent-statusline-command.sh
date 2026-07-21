#!/bin/bash
# subagent-statusline-command.sh — agent panel の各サブエージェント行を独自描画する。
# settings.json の "subagentStatusLine" で有効化。色/ヘルパーは lib.sh で主 statusline と共有。
# 詳細は docs/internals.md「Subagent statusline」参照。
#
# 契約 (Claude Code docs): stdin = `columns` + `tasks[]` を持つ 1 個の JSON。
# stdout = 上書きしたい行ごとに JSON 1 行 `{"id":..,"content":..}`。id を省いた行は既定描画のまま。
# content は ANSI / OSC 8 をそのまま解釈。per-task の model/contextWindowSize は 2.1.205+、effort は 2.1.214+。
set -uo pipefail
# 相対起動でも解決できるよう %/* が縮まない (スラッシュ無し) 場合は "." に fallback
_selfdir="${BASH_SOURCE%/*}"; [[ "$_selfdir" == "$BASH_SOURCE" ]] && _selfdir="."
source "$_selfdir/lib.sh"

# stdin 全取り: $(cat) の 2 fork を避け read builtin で受ける (主 statusline と同一パターン)
IFS= read -r -d '' input || true
[[ -z "$input" ]] && exit 0

# 端末幅 (description 切り詰めの予算に使う)。欠落/非数値は 80 に fallback
cols=$(jq -r '.columns // 80' <<< "$input" 2>/dev/null) || cols=80
[[ "$cols" =~ ^[0-9]+$ ]] || cols=80

# per-task フィールドを単一 jq で抽出し US(0x1f)区切りで連結。全フィールドに default を付け、
# model/effort/contextWindowSize を持たない旧 Claude Code でも graceful degradation する。
# 区切りに tab を使うと read の IFS=tab が空フィールドを潰して桁ずれするため非空白の US を使う。
# name/description の改行・タブは空白に潰し、1 行 = 1 task を保つ (effort は数値 token budget もあり得るので tostring)。
_rows=$(jq -r '.tasks[]? | [
  (.id // ""),
  (.label // .name // "" | gsub("[\n\r\t]"; " ")),
  (.model // ""),
  (.effort // "" | tostring),
  (.tokenCount // 0 | tostring),
  (.contextWindowSize // 0 | tostring),
  (.description // "" | gsub("[\n\r\t]"; " "))
] | join("\u001f")' <<< "$input" 2>/dev/null) || exit 0
[[ -z "$_rows" ]] && exit 0

# description の表示予算 (概算): 端末幅から name+model+bar+effort 分を差し引く。
# ANSI 幅は数えず概算 — 端末側の折り返しに委ねる方針 (主 statusline と同じ)。
_desc_budget=$(( cols - 34 ))
(( _desc_budget < 12 )) && _desc_budget=12

# 各行を id<US>content で組む (抽出と同じ US で統一)。here-string 供給なのでループは現シェル (サブシェル無し・_out に蓄積)。
_out=""
while IFS=$'\037' read -r id name model effort tok ctx desc; do
  [[ -z "$id" || -z "$name" ]] && continue   # id/name 無しは上書きせず既定描画に委ねる
  row="${AGENT}⚡${name}${RST}"
  if has_val "$model"; then
    model_color _mc "$model"
    row+="  ${_mc}"
  fi
  # context 使用率 (tokenCount / contextWindowSize) を braille バー + % で。主 Line 4 と同系。
  if [[ "$ctx" =~ ^[0-9]+$ ]] && (( ctx > 0 )) && [[ "$tok" =~ ^[0-9]+$ ]]; then
    pct=$(( tok * 100 / ctx ))
    (( pct > 100 )) && pct=100
    braille_bar "$pct" _bar
    color_by_threshold "$pct" 90 70 _bc
    row+="  ${_bc}${_bar}${RST} ${DIM}${pct}%${RST}"
  fi
  has_val "$effort" && row+="  ${EFFORT}${effort}${RST}"
  if has_val "$desc"; then
    (( ${#desc} > _desc_budget )) && desc="${desc:0:_desc_budget}…"
    row+="  ${DIM}${desc}${RST}"
  fi
  _out+="${id}"$'\037'"${row}"$'\n'
done <<< "$_rows"

# JSON lines を単一 jq で出力 (id/content を US で分割)。content 内の ESC/引用符/バックスラッシュは jq が安全にエスケープする。
[[ -n "$_out" ]] && printf '%s' "$_out" | jq -Rc 'split("\u001f") | {id: .[0], content: .[1]}'
exit 0
