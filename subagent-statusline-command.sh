#!/bin/bash
# subagent-statusline-command.sh — agent panel の各サブエージェント行を独自描画する。
# settings.json の "subagentStatusLine" で有効化。色/ヘルパーは lib.sh で主 statusline と共有。
# 詳細は docs/internals.md「Subagent statusline」参照。
#
# 契約 (Claude Code docs): stdin = `columns` + `tasks[]` を持つ 1 個の JSON。
# stdout = 上書きしたい行ごとに JSON 1 行 `{"id":..,"content":..}`。id を省いた行は既定描画のまま。
# content は ANSI / OSC 8 をそのまま解釈。per-task の model は 2.1.205+ で来る。
#
# 行 = 説明 + モデル(pretty・tier色) + [effort] + [status語] + [🌲worktree] だけ。
# 「実行中」表示は Claude Code のネイティブ chrome (行頭の ○/スピナー) に委ねる。
# context% と経過時間は出さない — 並走する subagent はどれも似た値 (実測 5-9% / 5-6m) になり、
# 行が伸びるだけで判断に効かなかった (v1.51.0 で撤去。tokenCount/contextWindowSize/startTime の
# 抽出と date fork もまとめて落ちた)。
# 端末幅での切り詰めはしない方針 (主 statusline と同じ。全要素フル出力・折り返し/切れは端末に委ねる)。
set -uo pipefail
# 相対起動でも解決できるよう %/* が縮まない (スラッシュ無し) 場合は "." に fallback
_selfdir="${BASH_SOURCE%/*}"; [[ "$_selfdir" == "$BASH_SOURCE" ]] && _selfdir="."
source "$_selfdir/lib.sh"

# per-task を単一 jq で US(0x1f) 区切り抽出。**stdin は変数に読まず jq に直接継承させる** — 主
# statusline と同じ作法で、`read` + here-string (bash 3.2 の `<<<` は一時ファイルを作る) が丸ごと
# 消える。空入力と tasks 欠落は jq が rc=0 で何も出さないので `_rows` が空になり**下の空チェック**で
# exit 0、不正 JSON は jq が rc≠0 なので**同じ行の `|| exit 0`** で抜ける (どちらも既定描画に戻る)。
#
# 全 text フィールドの制御文字は `[[:cntrl:]]` で空白化する。**改行/タブだけでは足りなかった** —
# US(0x1f) を含む label が来ると連結行が割れて**別フィールドを読む**。ESC も同時に落ちるので、
# task の説明文からの ANSI 注入も塞がる (行に色を付けるのは本スクリプトだけになる)。
_rows=$(jq -r '.tasks[]? | [
  (.id // "" | gsub("[[:cntrl:]]"; " ")),
  (.label // .description // .name // "" | gsub("[[:cntrl:]]"; " ")),
  (.model // "" | gsub("[[:cntrl:]]"; " ")),
  (.status // "" | gsub("[[:cntrl:]]"; " ")),
  (.cwd // "" | gsub("[[:cntrl:]]"; " ")),
  ((((.effort.level? // .effort?) // "") | if type == "string" or type == "number" then tostring else "" end) | gsub("[[:cntrl:]]"; " "))
] | join("\u001f")' 2>/dev/null) || exit 0
[[ -z "$_rows" ]] && exit 0

# model id -> "Opus 4.8" 風 (Line 1 の display_name と協調、fork-free)。先頭セグメントが tier 名
# (opus/sonnet/haiku/fable) の新形式 id のみ整形。旧形式 (claude-3-5-sonnet-… 版が tier より前) や
# 未知形式は cleaned id をそのまま出す (誤分割で "3 5.sonnet…" のように文字化けさせない。
# ただし**日付は新形式と同じ規則で落ちる**ので `3-5-sonnet` になる)。
prettify_model() {
  local m="${1##*.anthropic.}"     # Bedrock inference-profile prefix (jp./global./us. 等 .anthropic.) を剥がす
  m="${m#claude-}"; m="${m%\[1m\]}"
  m="${m%%:*}"; m="${m%-v[0-9]*}"  # Bedrock の版接尾辞。実 id は "-v1:0" (:N 付き) なので :N を先に落とす
  # 日付つき id (`claude-haiku-4-5-20251001`) の末尾を落とす。**8 桁ちょうどのパターンで消す** —
  # 「末尾の数字」で消すと `opus-5` の版まで食う。落とさないと Line 1 の display_name (`Haiku 4.5`)
  # に対して subagent 行だけ `Haiku 4.5.20251001` になり、同じモデルが 2 通りの名前で並ぶ。
  m="${m%-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]}"
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

# JSON 文字列値へ escape する (fork ゼロ。`jq -Rc` 1 個ぶんの起動が消える)。
# **不変条件は「`\` を最初に処理する」の 1 つだけ**。後回しにすると `"` と ESC の置換が入れた `\` を
# もう一度 escape して壊す (`osc8` が `%` を最初に処理するのと同じ理屈)。`"` と ESC は互いの生成物に
# 触らないので、この 2 つの順序は結果を変えない。
# **扱うのは自分が付けた ANSI の ESC だけ** — 他の制御文字は抽出側の `[[:cntrl:]]` で空白化済み。
# ESC を生バイトで出さないのは、Claude Code 側の JSON パーサに素の制御文字を渡さないため
# (`\u001b` は従来の `jq -Rc` の出力と同じ形なので、ワイヤ上の表現は変わっていない)。
_ESC=$'\033'
json_str() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$_ESC/\\u001b}"
  printf -v "$2" '%s' "$s"
}

# here-string 供給なのでループは現シェル (サブシェル無し・_out に蓄積)。
_out=""
while IFS=$'\037' read -r id label model status cwd effort; do
  [[ -z "$id" ]] && continue
  row=""
  # 説明 (先頭・通常輝度・切り詰めなし)
  has_val "$label" && add "$label"
  # モデル (pretty-name + tier 色)
  if has_val "$model"; then
    prettify_model "$model" _pm; model_color _mc "$_pm" "$model"; add "$_mc"
  fi
  # effort (2.1.214+): **セッションの effort を継承している行では absent** なので、出るのは
  # 「この subagent だけ effort が違う」時だけ = 差分そのものがシグナルになる (撤去した context%/経過は
  # 逆に全行に出て値が揃っていた)。色は Line 1 と同じ `effort_color`（lib.sh）でレベルごとに変える — 語彙と配色を 1 箇所に集約している。
  # 値はレベル文字列 (low/medium/high/xhigh/max) か**数値のトークン予算**なので数値だけ 8k 形に畳む
  # (`10#` で明示基数 — `08` のようなゼロ埋めを 8 進数と解釈させない)。
  # docs: 「設定された値をそのまま報告する」ので、モデル非対応レベルでは実際の適用値と異なりうる。
  # **row が空のうちは足さない** — effort だけで row を非空にすると、説明も名前も無い task の行を
  # 「effort 語だけ」で上書きしてしまい、Claude Code 既定描画 (名前 · 説明 · トークン数) より情報が減る。
  if [[ -n "$row" ]] && has_val "$effort"; then
    if [[ "$effort" =~ ^[0-9]+$ ]]; then fmt_ctx_size "$((10#$effort))" _ef; else _ef="$effort"; fi
    effort_color _ef_col "$_ef"
    add "$_ef_col"
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
  json_str "$id" _jid; json_str "$row" _jrow
  _out+='{"id":"'"$_jid"'","content":"'"$_jrow"'"}'$'\n'
done <<< "$_rows"

# JSON lines を**単一 printf** で出す (行ごとに書かない = pipe への書き込みが 1 回で済む。
# 主 statusline の「最後に単一 printf」と同じ作法)。`_out` は各行に改行を持つのでそのまま流す。
[[ -n "$_out" ]] && printf '%s' "$_out"
exit 0
