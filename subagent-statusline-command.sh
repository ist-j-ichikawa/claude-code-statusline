#!/bin/bash
# subagent-statusline-command.sh — agent panel の各サブエージェント行を独自描画する。
# settings.json の "subagentStatusLine" で有効化。色/ヘルパーは lib.sh で主 statusline と共有。
# 詳細は docs/internals.md「Subagent statusline」参照。
#
# 契約 (Claude Code docs): stdin = `columns` + `tasks[]` を持つ 1 個の JSON。
# stdout = 上書きしたい行ごとに JSON 1 行 `{"id":..,"content":..}`。id を省いた行は既定描画のまま。
# content は ANSI / OSC 8 をそのまま解釈。per-task の model/contextWindowSize は 2.1.205+ で来る。
#
# 行 = 説明 + モデル(pretty・tier色) + context%バー + [status語] + 経過 + [🌲worktree]。
# 「実行中」表示は Claude Code のネイティブ chrome (行頭の ○/スピナー) に委ね、行本文に独自グリフは出さない。
# 端末幅での切り詰めはしない方針 (主 statusline と同じ。全要素フル出力・折り返し/切れは端末に委ねる)。
set -uo pipefail
# 相対起動でも解決できるよう %/* が縮まない (スラッシュ無し) 場合は "." に fallback
_selfdir="${BASH_SOURCE%/*}"; [[ "$_selfdir" == "$BASH_SOURCE" ]] && _selfdir="."
source "$_selfdir/lib.sh"

IFS= read -r -d '' input || true
[[ -z "$input" ]] && exit 0

_now=$(date +%s)   # 経過時間用に 1 回だけ (主 statusline の _NOW と同じく 1 date fork)

# per-task を単一 jq で US(0x1f) 区切り抽出。全 text フィールドの改行/タブは空白化 (US 連結行の分割崩れ防止)。
_rows=$(jq -r '.tasks[]? | [
  (.id // "" | gsub("[\n\r\t]"; " ")),
  (.label // .description // .name // "" | gsub("[\n\r\t]"; " ")),
  (.model // "" | gsub("[\n\r\t]"; " ")),
  (.status // "" | gsub("[\n\r\t]"; " ")),
  (.tokenCount // 0 | tostring),
  (.contextWindowSize // 0 | tostring),
  (.startTime // 0 | tostring),
  (.cwd // "" | gsub("[\n\r\t]"; " "))
] | join("\u001f")' <<< "$input" 2>/dev/null) || exit 0
[[ -z "$_rows" ]] && exit 0

# model id -> "Opus 4.8" 風 (Line 1 の display_name と協調、fork-free)。先頭セグメントが tier 名
# (opus/sonnet/haiku/fable) の新形式 id のみ整形。旧形式 (claude-3-5-sonnet-… 版が tier より前) や
# 未知形式は cleaned id をそのまま出す (誤分割で "3 5.sonnet…" のように文字化けさせない)。
prettify_model() {
  local m="${1##*.anthropic.}"     # Bedrock inference-profile prefix (jp./global./us. 等 .anthropic.) を剥がす
  m="${m#claude-}"; m="${m%\[1m\]}"; m="${m%-v[0-9]}"   # claude- 接頭辞 / [1m] / Bedrock の -vN 接尾辞を除去
  local tier="${m%%-*}" ver="${m#*-}" _t
  case "$tier" in
    opus)_t=Opus;; sonnet)_t=Sonnet;; haiku)_t=Haiku;; fable)_t=Fable;;
    *) printf -v "$2" '%s' "$m"; return;;
  esac
  [[ "$m" != *-* ]] && ver=""      # 版が無い id (例 "opus") は tier のみ
  ver="${ver//-/.}"
  printf -v "$2" '%s%s' "$_t" "${ver:+ $ver}"
}

# 秒 -> "45s"/"3m"/"1h03m" (Line 3 の commit age と協調。dim・コンパクト)
fmt_elapsed() {
  local s=$1
  if   ((s < 60));   then printf -v "$2" '%ds' "$s"
  elif ((s < 3600)); then printf -v "$2" '%dm' $((s / 60))
  else printf -v "$2" '%dh%02dm' $((s / 3600)) $(((s % 3600) / 60)); fi
}

# row への追記。要素間は 2 スペース区切り (先頭要素には付けない → row が空なら区切り無し。全要素で統一)。
add() { row+="${row:+  }$1"; }

# here-string 供給なのでループは現シェル (サブシェル無し・_out に蓄積)。
_out=""
while IFS=$'\037' read -r id label model status tok ctx start cwd; do
  [[ -z "$id" ]] && continue
  row=""
  # 説明 (先頭・通常輝度・切り詰めなし)
  has_val "$label" && add "$label"
  # モデル (pretty-name + tier 色)
  if has_val "$model"; then
    prettify_model "$model" _pm; model_color _mc "$_pm"; add "$_mc"
  fi
  # context 使用率バー + % (主 Line 4 と同じ braille + 閾値色: 黄≥80/赤≥90)
  if [[ "$ctx" =~ ^[0-9]+$ ]] && (( ctx > 0 )) && [[ "$tok" =~ ^[0-9]+$ ]]; then
    pct=$(( tok * 100 / ctx )); (( pct > 100 )) && pct=100
    braille_bar "$pct" _bar; color_by_threshold "$pct" 90 80 _bc
    add "${_bc}${_bar}${RST} ${DIM}${pct}%${RST}"
  fi
  # 「実行中」表示は Claude Code のネイティブ chrome (行頭 ○/スピナー) に委ね、行本文に独自グリフは出さない。
  # running / completed(行はまもなく消える) / 無し は無表示、それ以外(入力待ち等)だけ黄で status 語を出す。
  case "$status" in
    running|completed|"") : ;;
    *) add "${YLW}${status}${RST}" ;;
  esac
  # 経過時間 (startTime は epoch ms)。completed は now-start が伸び続け「まだ実行中」に見えるので出さない。
  if [[ "$status" != "completed" ]] && [[ "$start" =~ ^[0-9]+$ ]] && (( start > 0 )); then
    _els=$(( _now - start / 1000 )); (( _els < 0 )) && _els=0
    fmt_elapsed "$_els" _el; add "${DIM}${_el}${RST}"
  fi
  # worktree: cwd が .claude/worktrees 配下の時だけ 🌲名 (Line 2 の worktree 表示と協調)
  if [[ "$cwd" == *"$WT_MARKER"* ]]; then
    _wt="${cwd##*"$WT_MARKER"}"; _wt="${_wt%%/*}"
    has_val "$_wt" && add "${DIM}🌲${_wt}${RST}"
  fi
  [[ -z "$row" ]] && continue
  _out+="${id}"$'\037'"${row}"$'\n'
done <<< "$_rows"

# JSON lines を単一 jq で出力 (id/content を US で分割)。入力側と同じく here-string で printf のサブシェル fork を避ける。
# _out 末尾の改行を 1 個外す (<<< が改行を付けるため。付けたままだと空行 → bogus な空 record が出る)。
[[ -n "$_out" ]] && jq -Rc 'split("\u001f") | {id: .[0], content: .[1]}' <<< "${_out%$'\n'}"
exit 0
