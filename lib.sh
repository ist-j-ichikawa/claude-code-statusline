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
# 変更行数と ahead/behind の色。**ANSI 31/32 を使わない** — あれは端末テーマがマップし直すので、
# 実測では olive (#b5bf70) と brick (#c36c68) に化けて「緑と赤」に見えなかった。
# **値は GitHub Primer の diff トークン（ダークモード）に合わせる** — `--fgColor-success`
# `#3fb950` / `--fgColor-danger` `#f85149`（ユーザー提示。2026-08-17）。**ダーク基準**にするのは
# statusline が載る端末が暗いから（Primer ライトの `#1a7f37` / `#cf222e` は暗い地では沈む）。
# 256 色の最近傍を計算して採用: add → 71 `#5faf5f`（Δ37）/ del → 203 `#ff5f5f`（Δ27）。
# 最初はスクリーンショットから採色して del=131 `#af5f5f` にしていたが、あれは**アンチエイリアスで
# 背景と混ざった値**（Δ78）で、実際のトークンより暗く濁っていた。
# **アラームの赤 (ANSI 31) とは分ける** — `!N` コンフリクト / detached / コンテキスト 90%+ /
# 遅れた版は「問題」、`+N -N ↑N ↓N` は「量」なので、色の役割を混ぜない。
readonly DIFF_ADD=$'\033[38;5;71m'    # GitHub dark --fgColor-success 相当 (#5faf5f)
readonly DIFF_DEL=$'\033[38;5;203m'   # GitHub dark --fgColor-danger  相当 (#ff5f5f)
readonly CORAL_N=173   # Opus の粘土コーラル。SGR 文字列と OPUS5_PAL の両方がここから派生する
readonly CORAL=$'\033[38;5;'"${CORAL_N}"'m' TEAL=$'\033[38;5;79m' AMBER=$'\033[38;5;214m' LAVENDER=$'\033[38;5;183m'
# 公式単色が無いモデルのアートワーク由来パレット (rainbow=文字ごとの循環 / gradient=1回スイープ)。
# 公式色が claude.ai に現れたら flat 単色へ差し替える前提の暫定色。
readonly FABLE_PAL=(178 172 130 167 143 107 66)   # Fable 5: 蝶標本図版 — 暖色循環 gold→amber→rust→red→olive→green→teal
# Fable 5.1 以降: 発表記事の図版が Venus / Magellan のレーダー画像なので別パレットにする
# (**「ヒーローアートワーク」ではない** — 5.1 の発表ページは記事のヒーロー画像を持たず、この
# レーダー画像と標高マップは本文「Computational analysis and modeling」節の図版。Fable 5.1 自身が
# Magellan のレーダー画像から Venus の 1/3 の高解像度標高マップを作った、という成果の説明図)
# (蝶標本は `FABLE_PAL` として **Fable 5 専用に残す** — 旧モデルを選んだ人の画面は変えない)。
# 実写の明度分位から 1 周ぶんの物語を取る: 暗いレーダー地表 → tan の地形 → amber の空 → 明るい山頂。
# **アートワークの生値そのままにはしない** — 実測の最暗は `#4a4338` (238 = 純グレー) で黒地では
# 先頭文字がほぼ沈み、最明は near-white で light テーマで飛ぶ。**知覚明度を 38 ずつ等間隔**に
# 引き直した (`L = 0.2126R + 0.7152G + 0.0722B` = 相対輝度で 103.5/140.6/179.4/212.1、ΔL +37/+39/+33。
# 式は `/model-colors` の規則と同じもので **CIE L* ではない**)。**180 は使わない** — すぐ左の `Anthropic` ラベルと同じ色なので
# 1 塊に見えて要素の境界が消える。214 は Sonnet 4.5 の flat 色と同値だが、スイープ内部の 1 ストップ
# なので衝突しない (Opus 5 が 173 = Opus 4.x 色を内部に持つのと同じ前例)。
readonly FABLE51_PAL=(95 137 214 187)            # Fable 5.1: Venus レーダー — brick→tan→amber→cream の 1 回スイープ
readonly SONNET5_PAL=(28 70 148 154)              # Sonnet 5: 植物モチーフ — 濃緑→黄緑
# Opus 5: 鳥卵標本図版 (支配色が無いので単色を選べない)。Sonnet 5 と同じ「単色相を暗→明にスイープ」構造で、
# 色相を Opus の coral 一族に取る: dark orange→CORAL→gold。彩度と明度レンジを稼ぐのが要点 —
# 実測に忠実な低彩度の tan/olive はターミナルでくすんで「グラデーション」に見えなかった (v1.50.0 で差し替え)。
# 両端とも mid/high 彩度なので light テーマでも飛ばない (near-white の 216/223 は不可)。
# **ストップは知覚明度で 30 以上離す** — 隣接ストップの明度差が 10 未満だと見分けられず、スロットの無駄に
# なる (v1.53.0 までの 5 ストップ版は 130/166 と 173/209 が各 8.5 差でほぼ同色。実質 3 段だった)。
readonly OPUS5_PAL=(130 $CORAL_N 215)
readonly AGENT=$'\033[38;5;213m' DIMVER=$'\033[38;5;248m'
# 最新版から遅れている時だけの色。**アラーム色 = 既存の赤**（ユーザー選択、2026-08-17）—
# 明度だけ上げる白 (231) は「気づく」には弱かった。赤はこの statusline で既に
# 「注意すべき状態」の語彙（detached / conflicts / 削除行 / behind / コンテキスト 90%+）なので、
# 新しい色相を増やさずにアラームの強さだけを借りる。Line 1 に赤はこれが初出。
# 非ブランド色なので可読性で調整して良い（もっと強くするなら 196、弱めるなら 214）。
readonly VEROLD="$RED"
# output style (`/output-style`) — `default` 以外の時だけ出す。**白 = Line 1 に唯一残っていた
# 「色相を持たない」枠**（ユーザー選択 2026-08-17）。最初の light orchid (176) は Agent 名の
# ピンク (213) とほぼ同色で、`claude agents` 経由のセッションで実際に見分けが付かなかった。
# 色相が無いので**将来モデル色が増えても衝突しない**のが白を選ぶ理由（think 117 / fast 190 の
# 隣に寒色や黄緑を足すと系統が混む）。宛名の無色（既定前景色）とは Agent 名を挟んで離れて並ぶ。
readonly OSTYLE=$'\033[38;5;231m'
readonly BOLD=$'\033[1m'
# effort は **Claude Code 自身の `/effort` ピッカーの配色に合わせる**（実測 2026-08-15）。
# 単色だった頃はレベルが上がっても見た目が変わらず、`high` と `max` を色で区別できなかった。
# low=gold → medium=green → high=薄紫 → xhigh=濃紫 → max=多色 のランプで、
# **上がるほど彩度と派手さが増す**ので位置関係が色だけで読める。非ブランド色なので調整可。
readonly EFFORT_LOW=$'\033[38;5;178m'      # gold
readonly EFFORT_MED=$'\033[38;5;71m'       # green
readonly EFFORT_HIGH=$'\033[38;5;105m'     # 薄紫（periwinkle）
# **リテラルは 1 箇所** — 既定/未知のレベルは high と同じ薄紫。両方に 105 を書くと
# 片方だけ調整したときに「未知は high と同色」という意図が黙って崩れる
readonly EFFORT="$EFFORT_HIGH"
readonly EFFORT_XHIGH=$'\033[38;5;99m'     # 濃紫（violet）
# max だけ多色。ピッカーでも `m`/`a`/`x` が紫→桃→橙に振られているので、順序に意味がある
# gradient（1 回スイープ）で描く。
readonly EFFORT_MAX_PAL=(99 170 209)

readonly THINK=$'\033[38;5;117m'
readonly FAST=$'\033[38;5;190m'  # fast mode — greenyellow, 非ブランド(速度感)。fast は Opus 専用なので model coral と同一行でも色相が離れ衝突しにくい。EFFORT/THINK 同様 tunable
readonly SPEND=$'\033[38;5;220m'  # usage-credits の**実課金額** (画面ラベルは `credits:`) — 明るい gold, 非ブランド
# セッションコスト — 落ち着いた金色 (ブロンズ)。**SPEND と同じ色相で明度だけ下げる**のが要点:
# 同系色なので「どちらも金額」と読め、明度差で「実課金 (明) / 参考値 (暗)」の序列が付く。
# v1.74.0 まで無色だったのは SPEND と隣接して混同するからで、Line 4/5 の行分割で
# コスト (セッション行) と credits (アカウント行) が別行になり、その前提が消えた。
readonly COST=$'\033[38;5;136m'
readonly DRAFT=$'\033[38;5;245m'  # PR review_state=draft — GitHub の draft バッジ準拠のニュートラルグレー, 非ブランド
# vim mode badges: bold + bg color + black fg — louder than Claude Code's footer "-- INSERT --" hint.
# **vim 側の慣習に合わせる: INSERT=青 / VISUAL=橙**。lualine の gruvbox_dark（`insert.a.bg`
# = `#83a598` 青 / `visual.a.bg` = `#fe8019` 橙）と vim-airline 既定が一致する流儀で、
# 256 色の近似は 109 / 208。**緑にしない** — 緑は lightline 系（lualine 16color）では INSERT だが、
# gruvbox/airline では NORMAL または COMMAND の色なので、モードを誤読させる。
# NORMAL は非表示なので緑は使わない（REPLACE も Claude Code の `vim.mode` に無い）。
readonly VIM_INSERT=$'\033[1;30;48;5;109m'  # bold black on gruvbox blue (INSERT)
readonly VIM_VISUAL=$'\033[1;30;48;5;208m'  # bold black on gruvbox orange (VISUAL / V-LINE)

# Claude Code worktree レイアウトの marker（外部契約文字列）。両 statusline が参照し drift を防ぐ。
readonly WT_MARKER='/.claude/worktrees/'

# `/fork` が session_name 末尾に付ける U+2442 (OCR FORK)。2.1.220 で実測。
# **8 進エスケープで書く** — 生グリフをソースに置くと Write/Edit で化けうる (US 区切りと同じ理由)。
# `$'⑂'` は bash 4+ 専用なので使えない。
readonly FORK_GLYPH=$'\342\221\202'

# --- Helpers (fork-free: printf -v / [[ ]] only) ---
has_val() { [[ -n "$1" && "$1" != "null" ]]; }

# osc8 URL TEXT VARNAME — sets VARNAME to OSC 8 hyperlink (no subshell)
# URL 側だけ percent-encode する (表示テキストの `;` 等はそのまま出す)。対象は 4 文字で、
# **`%` を最初に**やる — 後回しにすると `feat/a%3Bb`（git 上は合法）が `feat/a;b` と同じ出力に
# 畳まれて別ブランチへリンクする。`;` は OSC 8 の `OSC 8 ; params ; URI ST` のパラメータ区切り、
# `#`/`?` は URI の fragment/query 区切りで、どれも git のブランチ名と macOS のパスには入りうる
# (`#` を残すと `/Users/x/notes#1/repo` が `/Users/x/notes` を開く = 無言で別の対象を指す)。
# 空白と非 ASCII は生のまま出す — 現に動いており、encode 側に倒すと percent-decode しない端末で
# 今動いているリンクを壊す。壊れた実測が出たら対象に足す。
osc8() {
  local _u="${1//%/%25}"
  _u="${_u//;/%3B}"; _u="${_u//#/%23}"; _u="${_u//\?/%3F}"
  printf -v "$3" '\033]8;;%s\a%s\033]8;;\a' "$_u" "$2"
}

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
  # sweep の分母。1 文字なら 0 になるので下で if でガードする — **三項演算子は使えない**:
  # bash 3.2 は `((cond ? a/0 : 0))` で未選択の分岐も評価して "division by 0" を出し、
  # 呼び出し側の変数が未設定のまま set -u に当たって statusline が丸ごと空白になる (bash 4+ は平気)
  local _den=$(( 2 * (_len - 1) ))
  for ((_i=0; _i<_len; _i++)); do
    # sweep の添字は四捨五入。切り捨てだと最終ストップが末尾 1 文字にしか載らず
    # (35 字の Bedrock id で 17/17/1 字)、一番明るい色がほぼ見えなくなる
    if   ((_sweep && _den > 0)); then _idx=$(( (2 * _i * (_n - 1) + _len - 1) / _den ))
    elif ((_sweep));             then _idx=0
    else                              _idx=$(( _i % _n )); fi
    _out+=$'\033[38;5;'"${_pal[_idx]}"'m'"${_txt:_i:1}"
  done
  printf -v "$_vn" '%s%s' "$_out" "$RST"
}

# model_key VARNAME MODEL_SHOW [MODEL_ID] — sets VARNAME to a canonical "tier version"
# ("opus 5" / "sonnet 4.5" / "fable" / "" = unknown)。display_name と model id の両形、Bedrock の
# inference-profile を 1 つの正規形に畳む。
# 正規形は**必ず小文字**になる (tier 名はループのリテラルから取るので bash 4+ の ${var,,} が不要)。
# **サポート下限は 4.x** (3.x 系は全廃止済み)。旧形式 id (版が tier より前、`claude-3-5-sonnet-…`)
# は版スロットに日付が入る (`sonnet 20241022`) が、generic tier 色に落ちるだけで壊れない。
model_key() {
  local _s="$2|${3:-}" _t _mi _out=""
  shopt -s nocasematch
  for _t in fable opus sonnet haiku; do
    [[ "$_s" == *"$_t"* ]] || continue
    if [[ "$_s" =~ $_t[-\ ]([0-9]+)([-.][0-9]+)? ]]; then
      _out="$_t ${BASH_REMATCH[1]}"
      # 版スロットには**日付が来ることがある** — minor を持たない tier の dated id
      # (`claude-opus-4-20250514` / `claude-opus-5-20260101`) では第 2 group が `-20250514` になる。
      # 5 桁以上を日付とみなして捨て、正規形を常に `tier N[.N]` に保つ。これがあるので
      # model_color の arm は完全一致で足り「新モデルはパレット 1 行 + arm 1 行」が本当に成立する。
      _mi="${BASH_REMATCH[2]}"
      [[ ${#_mi} -le 3 ]] && _out="$_out${_mi/-/.}"   # "-5" も ".5" も ".5" に寄せる
    else
      _out="$_t"          # 版が読めない ("Opus" 単体等) — generic tier 色に落ちる
    fi
    break
  done
  shopt -u nocasematch
  printf -v "$1" '%s' "$_out"
}

# model_color VARNAME MODEL_SHOW [MODEL_ID] — sets VARNAME to MODEL_SHOW fully rendered in its
# tier color (no subshell)。Shared by Line 1 (main) and the subagent rows so both use identical
# model coloring。判定は model_key の正規形に対する**完全一致**で、残る順序ルールは
# 「generic tier の arm を最後に置く」の 1 つだけ。新モデルはパレット 1 行 + arm 1 行で足せる。
# Fable/Sonnet 5/Opus 5 は公式単色が無いので多色描画 (rainbow/gradient)。
# **Fable は 2 本ある** — `fable 5` だけが蝶標本の循環で、5.1 と**版が読めない裸の `Fable`**
# (`/usage` の `limits[]` は `"Fable"` しか返さない) は Venus のスイープに落ちる。既定モデルが
# 5.1 なので、Line 5 の `Fable:39%` が Line 1 と揃うのはこの向きだけ。
model_color() {
  local _ms="$2" _key
  model_key _key "$2" "${3:-}"
  case "$_key" in
    "fable 5")                  rainbow  "$1" "$_ms" ${FABLE_PAL[@]+"${FABLE_PAL[@]}"} ;;
    fable*)                     gradient "$1" "$_ms" ${FABLE51_PAL[@]+"${FABLE51_PAL[@]}"} ;;
    "opus 5"|"opus 5."*)        gradient "$1" "$_ms" ${OPUS5_PAL[@]+"${OPUS5_PAL[@]}"} ;;
    "sonnet 5"|"sonnet 5."*)    gradient "$1" "$_ms" ${SONNET5_PAL[@]+"${SONNET5_PAL[@]}"} ;;
    "sonnet 4.5")               printf -v "$1" '%s' "${AMBER}${_ms}${RST}" ;;
    opus*)                      printf -v "$1" '%s' "${CORAL}${_ms}${RST}" ;;
    sonnet*)                    printf -v "$1" '%s' "${TEAL}${_ms}${RST}" ;;
    haiku*)                     printf -v "$1" '%s' "${LAVENDER}${_ms}${RST}" ;;
    *)                          printf -v "$1" '%s' "$_ms" ;;
  esac
}

# fmt_elapsed SECONDS VARNAME — 経過秒を "41m" / "4h" / "27h" にする (no subshell)。
# 単位は常に 1 つ。**m/h 帯は Line 3 の commit age と同表記だが 24h 以降は分かれる** —
# 経過は `27h` のまま (セッションを開いている総時間が知りたい)、commit age は `1d` に丸める。
# **この値はアイドル込みの壁時計** = 「Claude が働いていた時間」ではない。根拠は
# `docs/internals.md`「Line 4」(実働は `cost.total_api_duration_ms` 側)。
# **H:MM にはしない** — リセット時刻（`19:31` / `土 16:00`）と桁の形が似て区別できなくなる。
# 経緯は CHANGELOG 1.60.0（当時は 5h が残り時間 `4:01` で、H:MM が 2 個並ぶ問題だった）。
fmt_elapsed() {
  local s=$1
  [[ "$s" =~ ^[0-9]+$ ]] || { printf -v "$2" '%s' ''; return; }
  if ((s < 3600)); then printf -v "$2" '%dm' $((s / 60))
  else                  printf -v "$2" '%dh' $((s / 3600)); fi
}

# fmt_ctx_size TOKENS VARNAME — コンテキスト窓の分母表記 ("500k" / "1M" / "1.5M")。
# format_tokens は必ず小数 1 桁を出す ("1.0M") が、分母では ".0" が邪魔なので落とす。
fmt_ctx_size() {
  format_tokens "$1" "$2"
  local _v="${!2}"
  printf -v "$2" '%s' "${_v/.0/}"
}

# plan_label VARNAME SUB_TYPE RATE_TIER — 契約種別 + レート枠を公式表記で組む (fork ゼロ)。
# 公式プラン名は Free / Pro / **Max 5x** / **Max 20x** / Team / Enterprise (claude.com/pricing、
# support.claude.com の Max プラン記事)。`subscriptionType` の生値は小文字なので正式表記に畳む。
# **`${var^}` は使わない** (bash 4+)。case が写像そのものなので不要。
#
# **`rateLimitTier` の値を列挙しない** — 未文書で増えうるフィールドなので、suffix が `Nx` の形かだけを
# 見る。`default_claude_max_5x` → `5x`、`default_claude_max_20x` → `20x`、`default_claude_ai` (Pro 相当、
# 上流 issue #43639 で実在) → 枠なし。値を許可リストで受けると v1.69.0 の `nameSource` と同じ
# 「未文書フィールドを列挙して実物で無言に壊れる」を繰り返す。
# 枠は契約種別と**独立**に付く — 実測で Enterprise 契約が `default_claude_max_5x` を持つ (= 契約が
# Enterprise でもレート枠は Max 5x 相当)。だから Team/Enterprise 専用の値を知らなくても壊れない。
plan_label() {
  local _st="$2" _rt="$3" _name _tier=""
  case "$_st" in
    free)       _name="Free" ;;
    pro)        _name="Pro" ;;
    max)        _name="Max" ;;
    team)       _name="Team" ;;
    enterprise) _name="Enterprise" ;;
    *)          _name="$_st" ;;   # 未知の契約種別は生のまま出す (旧/新 Claude Code の graceful degradation)
  esac
  # **桁数に上限を置かない** — `[0-9]x|[0-9][0-9]x` は `100x` を落とすので、「suffix が `Nx` か
  # だけを見る」という約束を満たしていなかった（列挙の粒度が値から桁数へ移っただけ。`/code-review` 指摘）
  local _sfx="${_rt##*_}"
  if [[ "$_sfx" == *x && "${_sfx%x}" =~ ^[0-9]+$ ]]; then _tier=" $_sfx"; fi
  printf -v "$1" '%s%s' "$_name" "$_tier"
}

# effort_color VARNAME LEVEL — sets VARNAME to LEVEL rendered in its effort color (no subshell)。
# Line 1 と subagent 行の両方から呼び、語彙と配色を揃える。
# **未知のレベルは既定の薄紫に落とす** — 上流がレベルを増やしても無色にならず、色だけが既知の
# ランプから外れる（旧 Claude Code / 新レベルの両方で graceful degradation）。
# `effort` は数値のトークン予算で来ることもある（subagent 側）ので、その場合も既定色に落ちる。
effort_color() {
  case "$2" in
    low)    printf -v "$1" '%s' "${EFFORT_LOW}$2${RST}" ;;
    medium) printf -v "$1" '%s' "${EFFORT_MED}$2${RST}" ;;
    high)   printf -v "$1" '%s' "${EFFORT_HIGH}$2${RST}" ;;
    xhigh)  printf -v "$1" '%s' "${EFFORT_XHIGH}$2${RST}" ;;
    max)    gradient "$1" "$2" ${EFFORT_MAX_PAL[@]+"${EFFORT_MAX_PAL[@]}"} ;;
    *)      printf -v "$1" '%s' "${EFFORT}$2${RST}" ;;
  esac
}

# ver_older A B — A が B より古ければ rc=0 (fork ゼロ・純パラメータ展開)。
# **文字列比較にしない** — `2.1.9` と `2.1.10` の大小が逆になる（辞書順では `9` > `1`）。
# **数値として読めない成分が 1 つでもあれば「古くない」に倒す** — 上流が `2.2.0-rc.1` のような
# 形を出したときに「遅れている」と誤って立てるより、無表示（dim）に落ちるほうを選ぶ。
# 成分は 3 つまで見る（4 つ目以降が付いた形では 3 つ目までの比較に落ちる = 誤検出しない側）。
ver_older() {
  local i av bv arest="$1" brest="$2"
  # 空文字は `av=""` が数値マッチに落ちるので、別途の空判定は要らない
  for i in 1 2 3; do
    av="${arest%%.*}" bv="${brest%%.*}"
    [[ "$av" =~ ^[0-9]+$ && "$bv" =~ ^[0-9]+$ ]] || return 1
    # **`10#` で明示基数** — `2.1.08` のようなゼロ埋めを 8 進数と解釈されると
    # `value too great for base` が毎レンダー stderr に漏れる（regex は `08` を通すので防げない。
    # subagent 側が同じ作法を既に持っている。`/code-review` 指摘）
    ((10#$av < 10#$bv)) && return 0
    ((10#$av > 10#$bv)) && return 1
    # 次の成分へ。残りが無い側は 0 として扱う（`2.1` と `2.1.0` は同じ）
    [[ "$arest" == *.* ]] && arest="${arest#*.}" || arest=0
    [[ "$brest" == *.* ]] && brest="${brest#*.}" || brest=0
  done
  return 1
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
