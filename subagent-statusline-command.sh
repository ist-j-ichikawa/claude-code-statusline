#!/bin/bash
# subagent-statusline-command.sh — agent panel の各サブエージェント行を独自描画する。
# settings.json の "subagentStatusLine" で有効化。色/ヘルパーは lib.sh で主 statusline と共有。
# 詳細は docs/internals.md「Subagent statusline」参照。
#
# 契約 (Claude Code docs): stdin = `columns` + `tasks[]` を持つ 1 個の JSON。
# stdout = 上書きしたい行ごとに JSON 1 行 `{"id":..,"content":..}`。id を省いた行は既定描画のまま。
# content は ANSI / OSC 8 をそのまま解釈。per-task の model は 2.1.205+ で来る。
#
# 行 = 説明 + モデル(pretty・tier色) + [status語] + [🌲worktree] だけ。
# 「実行中」表示は Claude Code のネイティブ chrome (行頭の ○/スピナー) に委ねる。
# context% と経過時間は出さない — 並走する subagent はどれも似た値 (実測 5-9% / 5-6m) になり、
# 行が伸びるだけで判断に効かなかった (v1.51.0 で撤去。tokenCount/contextWindowSize/startTime の
# 抽出と date fork もまとめて落ちた)。
# 端末幅での切り詰めはしない方針 (主 statusline と同じ。全要素フル出力・折り返し/切れは端末に委ねる)。
set -uo pipefail
# 相対起動でも解決できるよう %/* が縮まない (スラッシュ無し) 場合は "." に fallback
_selfdir="${BASH_SOURCE%/*}"; [[ "$_selfdir" == "$BASH_SOURCE" ]] && _selfdir="."
source "$_selfdir/lib.sh"

IFS= read -r -d '' input || true
[[ -z "$input" ]] && exit 0

# per-task を単一 jq で US(0x1f) 区切り抽出。全 text フィールドの改行/タブは空白化 (US 連結行の分割崩れ防止)。
_rows=$(jq -r '.tasks[]? | [
  (.id // "" | gsub("[\n\r\t]"; " ")),
  (.label // .description // .name // "" | gsub("[\n\r\t]"; " ")),
  (.model // "" | gsub("[\n\r\t]"; " ")),
  (.status // "" | gsub("[\n\r\t]"; " ")),
  (.cwd // "" | gsub("[\n\r\t]"; " "))
] | join("\u001f")' <<< "$input" 2>/dev/null) || exit 0
[[ -z "$_rows" ]] && exit 0

# model id -> "Opus 4.8" 風 (Line 1 の display_name と協調、fork-free)。先頭セグメントが tier 名
# (opus/sonnet/haiku/fable) の新形式 id のみ整形。旧形式 (claude-3-5-sonnet-… 版が tier より前) や
# 未知形式は cleaned id をそのまま出す (誤分割で "3 5.sonnet…" のように文字化けさせない)。
prettify_model() {
  local m="${1##*.anthropic.}"     # Bedrock inference-profile prefix (jp./global./us. 等 .anthropic.) を剥がす
  m="${m#claude-}"; m="${m%\[1m\]}"
  m="${m%%:*}"; m="${m%-v[0-9]*}"  # Bedrock の版接尾辞。実 id は "-v1:0" (:N 付き) なので :N を先に落とす
  local tier="${m%%-*}" ver="${m#*-}" _t
  case "$tier" in
    opus)_t=Opus;; sonnet)_t=Sonnet;; haiku)_t=Haiku;; fable)_t=Fable;;
    *) printf -v "$2" '%s' "$m"; return;;
  esac
  [[ "$m" != *-* ]] && ver=""      # 版が無い id (例 "opus") は tier のみ
  ver="${ver//-/.}"
  printf -v "$2" '%s%s' "$_t" "${ver:+ $ver}"
}

# row への追記。要素間は 2 スペース区切り (先頭要素には付けない → row が空なら区切り無し。全要素で統一)。
add() { row+="${row:+  }$1"; }

# here-string 供給なのでループは現シェル (サブシェル無し・_out に蓄積)。
_out=""
while IFS=$'\037' read -r id label model status cwd; do
  [[ -z "$id" ]] && continue
  row=""
  # 説明 (先頭・通常輝度・切り詰めなし)
  has_val "$label" && add "$label"
  # モデル (pretty-name + tier 色)
  if has_val "$model"; then
    prettify_model "$model" _pm; model_color _mc "$_pm" "$model"; add "$_mc"
  fi
  # 「実行中」表示は Claude Code のネイティブ chrome (行頭 ○/スピナー) に委ね、行本文に独自グリフは出さない。
  # running / completed(行はまもなく消える) / 無し は無表示、それ以外(入力待ち等)だけ黄で status 語を出す。
  case "$status" in
    running|completed|"") : ;;
    *) add "${YLW}${status}${RST}" ;;
  esac
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
