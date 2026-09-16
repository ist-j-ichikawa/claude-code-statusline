#!/bin/bash
# statusline-command.sh — 並列セッションで困る 3 つ（「これはどのセッションか」「どのアカウントに
# 課金されるか」「枠の残り」）に絞った 3 行。**1 ファイルで完結**（旧 `lib.sh` は取り込み済み。
# `source` しないのでどのディレクトリから起動しても動く）。
#
# **Built against Claude Code 2.1.273**（`experiments/upstream/2.1.273/` に教典 3 つを snapshot 済み）。
# 2.1.270 → 273 は**実質差分ゼロ** — 教典② は差分なし、① は minify 名、③ は表記ゆれ
# （`Claude.ai` → `claude.ai`）と walkthrough の文言だけ。**契約は動いていない**。
# その前（2.1.260 → 270）の実質差分は `prompt_cache.caching_observed` の gate 1 点で、取り込み済み。
# **要素を増やすより「載せない理由」を先に固める** — 組み込みの UI が常時見せているものと、
# 後から `/cost` や `/usage` で取り戻せる累積値は載せない。通すのは**一過性**（窓が閉じたら
# コマンドでも見られない）か**決断のトリガー**（その数字が無いとコマンドを打つべきかも
# 判断できない）のどちらかだけ。**左から順に優先度が高い** — 本体は全行を右端で切るので、
# 並び順がそのまま「狭い窓で何が残るか」になる。
#
#   1 行目: provider(契約プラン) · 宛名 · モデル(tier 色) · effort · 版
#            ← どのセッションか / どのアカウントに課金されるか
#   2 行目: パス · 🌲worktree · ブランチ · 進行中の操作 · conflicts · ahead/behind
#            ← どこで何を触っているか / いま git の途中か
#   3 行目: コンテキスト・課金額・cold(セッション) │ 5h・週間・モデル別枠(アカウント)
#            ← いくら使ったか / あとどれだけ
#
# v1 との違い（ゼロから作る方針の第 1 歩）:
#   - **git のキャッシュを持たない**。同期で **1 回**だけ呼ぶ（v1 は約 10 回 + 5 秒キャッシュ +
#     背景更新で、代償として表示が最大 5 秒古かった）。本体のデバウンス 300ms に対して十分速い。
#     **キャッシュはアカウント情報の 1 個だけ**（下記）。git・stdin 由来の要素は一切持たない。
#   - **変更行数 `+42 -17` は出さない** — 2026-09-04 の本体アップデートで diff パネルが付き、
#     `5 files changed +2 -26` を出すようになった（`/diff` でトグル、パネルが開いている間は常時見える）。
#     本体が出すものは載せない。**`ahead/behind` は残す** — パネルに無い情報で、しかも
#     `status --porcelain=v2 -b` の `branch.ab` にタダで乗ってくる（プロセスは増えない）。
#   - **ネットワークと Keychain に触る要素が 3 つだけある**（2026-09-04 に追加）— 契約プラン・
#     モデル別週間枠・（provider は env と `model.id` だけなのでタダ）。**同期パスは触らない**:
#     hot path はキャッシュを読むだけで、取得は背景 subshell 1 本。**Keychain の blob 1 回で
#     契約プランと OAuth token の両方が取れる**ので、キャッシュも背景も 1 本で足りる。
#   - 5h と週間の枠は stdin の `rate_limits` に、セッションの課金額は stdin の
#     `cost.total_cost_usd` に来る（**この 2 つは fork もネットワークもゼロ**）。
#   - **落としたのは実課金の `credits:$` だけ** — このアカウントは `/usage` の応答が
#     `spend.enabled: false` / `can_purchase_credits: false` で **usage credits が構造的に
#     使えない**ので、出しても永久に空（2026-09-04 実測）。プラン名とモデル別週間枠は出す。
#   - **US 区切りと形式タグを持つのはアカウントのレコード 1 つだけ**。stdin の抽出は 1 回の
#     jq で、あとは bash の文字列操作だけ。
#   - `git` は **optional locks を飛ばす**（公式 `/statusline` プロンプトのガイドライン）。
#   - untracked は数えない（`-uno`）。大きいリポでコストがサイズに比例するのを避ける
#     （5878 ファイルのリポで 41.3 → 16.8ms、サイズ非依存になる）。**2026-09-04 に「数えない」で
#     決着**（累積なので `/cost` の `Total code changes` から取り戻せる = 物差しで落ちる）。
set -uo pipefail
# ── 色と fork-free ヘルパー（旧 lib.sh を取り込んだもの）────────────────────
# **1 ファイルで完結させる**（2026-09-08）。v1 を消して release tag で版を分ける方針にしたので、
# `source` で 2 本に割る理由が無くなった。**取り込みは丸ごと** — 旧 `lib.sh` の 63%（12 関数 /
# 31 定数）は実際に使っており、選択抽出すると 1 行関数（`gradient` / `rainbow`）の範囲を誤る。
# **未使用のまま残しているものがある**（`osc8` / `editor_url` / `fmt_elapsed` / vim 色 /
# `FORK_GLYPH` / `AGENT` / `DRAFT` 等）。park 中の subagent 行とフッターで使うもので、色の根拠と
# `%` エンコード順の教訓が乗っているので**消さない**。**剪定を試みて撤回した**理由も残す:
# `(( ))` の算術は変数を `$` なしで参照するので、`$` ベースで未使用を数えると `ACCT_TTL` を
# 「未参照」と誤判定する（37 行の削減にリスクを払う価値がない）。
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
# **枠 90%+** / 遅れた版は「問題」、`+N -N ↑N ↓N` は「量」なので、色の役割を混ぜない。
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
# 「注意すべき状態」の語彙（detached / conflicts / 削除行 / behind / コンテキスト 90%+ /
# 枠 90%+）なので、
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
# 実働は `cost.total_api_duration_ms` 側（この関数は現在 park 中で呼んでいない）。
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
  # **`10#` で 10 進を強制する** — `08` / `09` は 8 進として解釈され「value too great for base」が
  # **毎描画 stderr に漏れる**。呼び出し側の gate は `^[0-9]+$` なのでゼロ埋めを通す。
  local pct=$1 width=5
  [[ "$pct" =~ ^[0-9]+$ ]] && pct=$((10#$pct))
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
  [[ "$val" =~ ^[0-9]+$ ]] && val=$((10#$val))   # ゼロ埋めを 8 進に読ませない
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


readonly CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# **資格情報は `CONFIG_DIR` とは別の変数から派生させる。** 上流は credentials だけ
# `CLAUDE_SECURESTORAGE_CONFIG_DIR` 側に置き、Keychain のサービス名の suffix もそちらの値で
# 決める（**定義済みなら空でも優先**され、空なら suffix 無し）。`CONFIG_DIR` で代用すると、
# 2 つを別々に設定している環境で**別アカウントの blob を読んでプラン名と枠を出す**（誤読）。
# ハッシュの元は**env の値そのまま** — 上流は NFC 正規化だけで、path の解決も末尾スラッシュの
# 除去もしない。
if [[ -n "${CLAUDE_SECURESTORAGE_CONFIG_DIR+x}" ]]; then
  readonly SECURESTORAGE_DIR="${CLAUDE_SECURESTORAGE_CONFIG_DIR:-$HOME/.claude}"
  readonly SECURESTORAGE_HASH_DIR="${CLAUDE_SECURESTORAGE_CONFIG_DIR}"
else
  readonly SECURESTORAGE_DIR="$CONFIG_DIR"
  readonly SECURESTORAGE_HASH_DIR="${CLAUDE_CONFIG_DIR:+$CONFIG_DIR}"
fi

# **v2 専用の色はここに置く**。
# `cold` = 氷の青（xterm 81）。**最初 AMBER 214 にして外した** — ① 語が "cold" なのに暖色で
# **意味と色が逆** ② 隣の `$`（COST 136 ブロンズ）と同系で**並ぶと溶ける**（実機で確認）
# ③ 214 は Fable 5.1 の Venus パレット（95/137/214/187）と番号が衝突する。
# 81 は取り込み済みの使用番号（33 39 71 72 79 82 99 105 117 136 178 180 183 190 202 203
# 213 214 220 231 245 248）に無く、**3 行目の他の色（緑 82 / ブロンズ 136 / タン 180）が
# 全部暖色〜緑なので、寒色は 1 つで際立つ**。provider のブランド色（33/39/72）は避けた。
readonly COLD=$'\033[38;5;81m'

# **枠のゲージは context と同じ `braille_bar`（幅 5・空きは空白・数値つき）を使い、
# 色は要素まるごと 1 色に統一する**（2026-09-07 にユーザー指示「block 単位で色の統一を」）。
# ラベル・バー・`N%`・リセット時刻が同じ色になる: `5h` は ANTH、`week` は dim ANTH、
# モデル別枠は**名前が終わった色**（下の `_ecol`）。**ただし 90%+ は 3 つとも RED 単独に
# 切り替わる**（`LIMIT_HI`。下の宣言のコメントが理由の正典）。
#
# **却下した 3 案**（すべて実機の画面を見て撤回した）:
# ① **幅 3 + 軌道 `⠿` + 数値なし** — 軌道の `⠿` は 6 ドットで、低い fill（`⣀` 2 / `⣄` 3 /
#    `⣤` 4 ドット）より**密**なので見た目が反転し、どこまで埋まっているか読めない。加えて
#    **数値を落とすと何も読めない**（実際に読んでいるのは数字で、バーは地模様。低い % では
#    地模様がほぼ空になり 5% と 40% が区別できない）。
#    教訓: **ゲージは数値の代わりではなく、数値の隣に置く比較の道具**。context が最初からその形。
# ② **context と同じ閾値色（緑/黄/赤）** — ラベルと数値が識別色でバーだけ緑になり、
#    **要素が 2 つに割れて見える**。「1 要素に色系統を 2 つ入れない」がこれ。
#    context のバーが緑で成立するのは、**あの要素が識別色を持たない**（ラベルも無く閾値色が
#    唯一の色）から。識別色を持つ要素に足すと境界が読めなくなる。
# ③ **名前と同じ gradient をバーにスイープ** — 埋まり桁が 1 つだと `gradient` の添字が 0 に
#    なり、**パレット先頭の一番暗い色**が当たる（Fable 5.1 は `95` = brick）。名前は
#    `brick→tan→amber→cream` と流れて cream で終わるので、直後のバーが brick に戻って**逆走**する。
#
# **近接警告の色は 2026-09-16 に入れた**（v2.2.0。それまでは「バーの形と数値で読む」だけだった）。
# 入れ方は**要素まるごと赤**で、**バーだけ赤は②に戻る**ので採っていない。閾値と 3 箇所の
# 使い方は `LIMIT_HI` の宣言のコメントが正典。

# ── アカウント情報のキャッシュ（**これだけがディスクに書く**）──────────────
# **v2 は原則キャッシュを持たない**。例外がここ 1 つだけで、理由は「同期で払えない」から:
# Keychain 読み（`security` + `jq`）と `/usage` の `curl -m 4` は描画を止める長さになる。
# **`v1` とは別ディレクトリ**にする（park 中の v1 と混ざらない。seam の env 名も別）。
# **ファイル名に config dir を混ぜる** — `CACHE_BASE` は UID 単位なので、混ぜないと
# `CLAUDE_CONFIG_DIR` を分けた 2 アカウントが**別アカウントのプラン名と枠を表示する**。
readonly CACHE_BASE="${CLAUDE_STATUSLINE_V2_CACHE_DIR:-${TMPDIR:-/tmp}/claude-statusline-v2-$UID}"
# **鍵には config dir と securestorage dir の両方を混ぜる。** キャッシュに入るのは
# **`CLAUDE_SECURESTORAGE_CONFIG_DIR` で引いた Keychain の値**（プラン・枠）なので、
# `CONFIG_DIR` だけで鍵にすると**同じ config dir で securestorage を分けた 2 つが同じファイルを
# 読み書きし、互いのプラン名と枠を表示する**（SECURESTORAGE を分けた目的が消える）。
_cfgk="${CONFIG_DIR//\//_}"
# **securestorage を明示的に分けているときだけ鍵に足す。** 比較相手は `CONFIG_DIR` ではなく
# **「`CLAUDE_SECURESTORAGE_CONFIG_DIR` を設定しなかったときの値」** — `SECURESTORAGE_HASH_DIR` は
# `CLAUDE_CONFIG_DIR` が未設定なら**空**になるので、`CONFIG_DIR` と比べると既定でも食い違い、
# **全ユーザーのキャッシュ名が変わって一斉に取り直す**（実際に踏んだ）。
if [[ "$SECURESTORAGE_HASH_DIR" != "${CLAUDE_CONFIG_DIR:+$CONFIG_DIR}" ]]; then
  _cfgk="${_cfgk}__${SECURESTORAGE_HASH_DIR//\//_}"
fi
readonly CFG_KEY="$_cfgk"
readonly ACCT_CACHE="${CACHE_BASE}/account${CFG_KEY}"
# **枠が尽きかけているときの閾値**（5h / week / モデル別枠の 3 つ共通。context の 90 と同じ数字)。
# ここを超えたら**要素まるごと RED** にする — **バーだけ赤にしない**のは、ラベルに識別色を残して
# バーに別系統を当てると「要素が 2 つに割れて見える」実機の失敗（2026-09-07）を再演するから。
# context の閾値色が成立するのは**あの要素が識別色を持たない**からで、枠の 3 要素は
# ANTH / dim ANTH / モデル色という識別色を持っている。だから**色系統を足すのではなく差し替える**。
readonly LIMIT_HI=90
readonly ACCT_TTL=300
# **確認できなくなった値を出し続けない上限**（`at.*` は claim で毎回進むので鮮度の判定に使えない。
# 「最後に**取れた**時刻」を別に持ち、これを超えたら要素ごと落とす）。ログアウトやアカウント
# 切り替えの後に**古いプラン名を現在のものとして出し続ける**のは「無表示 < 誤読」の裏返し。
# 24 時間にしてあるのは、プランは滅多に変わらない一方で「取れない状態」は数分で復帰しうるから。
readonly ACCT_MAX_AGE=86400
# **形式タグ = フィールド一覧そのもの**。不一致なら値を捨てて即取り直す（TTL を待たせない）。
# **版番号をファイル名に持たせない**（製品版と紛らわしく、番号上げを忘れる）。
# **形式タグは「フィールド一覧」ではなく schema 番号にする。** 一覧をタグにすると**項目を 1 つ
# 足すだけで全ユーザーの既存レコードが無効化**され、並走している全セッションが同じ瞬間に
# 取り直す（2026-09-08 までに `,reset` と `,tz` の 2 回それをやった）。`schema` は
# **既存キーの意味が変わったときだけ**上げる — 追加では上げない。
readonly ACCT_SCHEMA=1
# レコードの区切り。**`printf` の書式に直接埋めない**ので変数で持つ。
readonly _USEP=$'\037'

# ── 抽出: 1 回の jq で全部 ────────────────────────────────────────────────
# **入れ子の index は各段に `?` を付ける**（`?` は直前の 1 段にしか効かない） — `.effort.level` は `effort` が**文字列や数値に変わった
# 瞬間に jq 全体を abort** させ、`jq error` の 1 行だけになる（= 表示が丸ごと落ちる）。`?` は
# 文字列・数値・配列のどれを食っても空を返す（実測）。**算術と時刻整形は `type != "number"` で
# 守る** — `?` は index の失敗しか捕まえないので、`round` / `* 100` / `strflocaltime` に
# 文字列が入る経路は別に塞ぐ。**`// ""` だけでは足りない**（欠損は防げても型変更は防げない）。
# payload は未文書なので、上流が型を変える可能性は「無い」と決められない。
# `// ""` を必ず付ける（古い Claude Code では要素が出ないだけで壊れない）。
model="" model_id="" effort_level="" current_dir="." wt_name="" used_pct="" ctx_size=0
five_pct="" five_at="" seven_pct="" seven_at="" session_id="" cc_version="" cost_cents=0
pc_state="" pc_cause="" _NOW=0 fast_mode=false _jq_ok=1
tz_setting="" tf_setting="" five_ep="" seven_ep=""
# **時刻表記の設定はユーザー settings から読む**（2.1.257+ の `timeZone`）。**既存の 1 回の jq に
# `--rawfile` で相乗りさせる**ので fork は増えない。**`--slurpfile` は使わない** — jq が JSON として
# 読むので、人が手で壊した settings.json で**抽出が丸ごと死んで statusline が空白になる**。
# **`fromjson? | objects` を `// {}` で受けるのが必須** — `?` が吸うのは構文エラーだけなので
# `[]` や `5` は通り抜け、さらに**素朴に書くと空ストリームになって `@sh` の行が丸ごと消える**
# （実測: `tz=` の行が出ず、eval しても変数が未定義のまま = `set -u` で死ぬ）。`as $cfg` で束ねる。
# **存在しないときは `/dev/null`**（`--rawfile` は実在するパスを要求する）。**gate は `-f` + `-r`** —
# `-r` だけだとディレクトリを通し、`--rawfile` はディレクトリで abort する。
# **読むのはユーザー settings 1 枚だけ** — project 側のパスは `current_dir` 依存で、その値は
# この jq が返すものなので起動前に決まらない。取りこぼしても従来表記に倒れる（誤表示にならない）。
_settings_file="${CONFIG_DIR}/settings.json"
[[ -f "$_settings_file" && -r "$_settings_file" ]] || _settings_file=/dev/null
_jq=$(jq -r --rawfile _settings "$_settings_file" '
  (($_settings | fromjson? | objects) // {}) as $cfg
  | @sh "tz_setting=\($cfg.timeZone // "" | tostring)",
  @sh "tf_setting=\($cfg.timeFormat // "" | tostring)",
  @sh "model=\(.model?.display_name? // "" | tostring | gsub("[[:cntrl:]]"; " "))",
  @sh "model_id=\(.model?.id? // "" | tostring | gsub("[[:cntrl:]]"; " "))",
  @sh "effort_level=\(.effort?.level? // "" | tostring | gsub("[[:cntrl:]]"; " "))",
  @sh "current_dir=\(.workspace?.current_dir? // .cwd? // "." | tostring | gsub("[[:cntrl:]]"; " "))",
  @sh "wt_name=\(.worktree?.name? // "" | tostring | gsub("[[:cntrl:]]"; " "))",
  @sh "used_pct=\(.context_window?.used_percentage? // null | if type != "number" then "" else round end)",
  @sh "ctx_size=\(.context_window?.context_window_size? // 0 | if type != "number" then 0 else floor end)",
  @sh "five_pct=\(.rate_limits?.five_hour?.used_percentage? // null | if type != "number" then "" else round end)",
  @sh "five_ep=\(.rate_limits?.five_hour?.resets_at? // null | if type != "number" then "" else floor end)",
  @sh "five_at=\(.rate_limits?.five_hour?.resets_at? // null | if type != "number" then "" elif . <= now then "now" else (((. + 30) / 60 | floor) * 60 | strflocaltime("%H:%M")) end)",
  @sh "seven_pct=\(.rate_limits?.seven_day?.used_percentage? // null | if type != "number" then "" else round end)",
  @sh "seven_ep=\(.rate_limits?.seven_day?.resets_at? // null | if type != "number" then "" else floor end)",
  @sh "seven_at=\(.rate_limits?.seven_day?.resets_at? // null | if type != "number" then "" elif . <= now then "now" else (((. + 30) / 60 | floor) * 60 | strflocaltime("%w %H:%M")) end)",
  @sh "session_id=\(.session_id? // "")",
  @sh "cost_cents=\(.cost?.total_cost_usd? // 0 | if type != "number" then 0 else . * 100 | round end)",
  @sh "fast_mode=\(.fast_mode // false)",
  @sh "pc_state=\(if (.prompt_cache|type) == "object" then (if .prompt_cache.caching_observed == false then "" elif .prompt_cache.warm == false then "cold" else "warm" end) else "" end)",
  @sh "pc_cause=\((.prompt_cache?.last_miss_cause?.causes? // []) | if type != "array" or length == 0 then "" else (.[0] | tostring | gsub("[[:cntrl:]]"; " ")) end)",
  @sh "cc_version=\(.version? // "" | tostring | gsub("[[:cntrl:]]"; " "))",
  @sh "_NOW=\(now|floor)"
' 2>/dev/null) && eval "$_jq" || _jq_ok=""
# **空の出力も失敗**として扱う — jq は**空の stdin では rc=0 で何も出さない**ので、
# rc だけ見ると素通りする（実測: 空入力で `jq error` が出なかった）。抽出プログラムは常に
# 18 行の `@sh` を出すので、**出力が空 = 失敗**と断定できる。
[[ -n "$_jq" ]] || _jq_ok=""

# ── 時刻表記: `timeZone` に追従し、曜日は英語 3 文字に固定する ──────────────
# **曜日は locale に頼らない。** jq には `%w`（0=日曜の数値）を出させて、bash 側で固定の英語名に
# 引く。`%a` は `LC_TIME` 依存で、Ghostty が入れる `en_US.UTF-8` を `~/.zshenv` が上書きしている
# この環境では**日本語の「土」が出ていた**。`LC_ALL=C` を jq に被せる案は却下 — `gsub` の
# 文字クラスまで巻き込むうえ、**「英語で出す」という意図がコードに現れない**。
#
# **ゾーンは `export TZ` 1 本で通す** — 描画側の jq も背景 subshell の jq も同じゾーンになるので、
# 時刻を作る箇所ごとに引数を配らなくて済む（**だから `fetch_account` より前に決める**）。
# **不正な名前は必ず落とす** — libc は不正な `TZ` を**黙って UTC にする**が、上流はシステムの
# ゾーンに戻す。落とさないと「UTC の時刻をローカルだと思って読む」= 誤読になる。判定は
# **先頭 4 バイトの TZif マジック**（fork ゼロ。`-e` の実在チェックだけでは `Asia` のような
# ディレクトリや `zone.tab` を通してしまう）。`..` / 先頭 `/` / 先頭 `:` は形で先に弾く
# （`../../etc/passwd` は zoneinfo 配下から**実在してしまう**）。
#
# **`timeFormat` はプリセット 3 つだけ追う。** `%` を含むユーザー定義パターンは**採らない** —
# `%n` / `%t` が **3 行契約を割り**、US がキャッシュのレコードを割る（v1 はサニタイズの多段で
# 塞いだが、アルファでその面積を持つ価値がない）。`auto` も追わない（BSD の `date` / jq に
# 「この locale の時刻書式」を安全に出させる指定が無い）。**12 時間と `Z` 付けは bash 側の
# 変換で済ませる**ので、jq に渡す書式文字列は `%H:%M` / `%w %H:%M` の 2 つに固定される
# = **書式の注入経路がそもそも無い。**
readonly WDAY=(Sun Mon Tue Wed Thu Fri Sat)
_tz="" _tf12="" _tfz=""
case "$tf_setting" in
  24-hour-utc) _tz="UTC"; _tfz="Z" ;;
  12-hour)     _tf12=1 ;;
esac
if [[ -z "$_tz" ]]; then
  case "$tz_setting" in
    ""|*..*|/*|:*) : ;;
    *) if [[ -f "/usr/share/zoneinfo/$tz_setting" ]]; then
         # **gate は `-f`**（`2>/dev/null` ではリダイレクト自身の失敗を黙らせられず、
         # `JST` や `Asia/Toyko` のような typo で**毎レンダー stderr に 1 行漏れる**）
         IFS= read -r -n 4 _magic < "/usr/share/zoneinfo/$tz_setting" || _magic=""
         [[ "$_magic" == TZif ]] && _tz="$tz_setting"
       fi ;;
  esac
fi
if [[ -n "$_tz" ]]; then
  export TZ="$_tz"
  # **ゾーンが決まったときだけ整形をやり直す**（1 回の `jq -n` = このときだけ fork が 1 増える）。
  # 既定（`timeZone` 未設定）では 0 回なので、**hot path の床は jq 1 + git 1 のまま**。
  # 書式は上の 2 つに固定なので `--arg` で渡す必要も無い。
  _rt=$(jq -rn --arg fe "$five_ep" --arg se "$seven_ep" '
    @sh "five_at=\($fe | if . == "" then "" else tonumber | if . <= now then "now" else (((. + 30) / 60 | floor) * 60 | strflocaltime("%H:%M")) end end)",
    @sh "seven_at=\($se | if . == "" then "" else tonumber | if . <= now then "now" else (((. + 30) / 60 | floor) * 60 | strflocaltime("%w %H:%M")) end end)"
  ' 2>/dev/null) && eval "$_rt" || true
fi

# fmt_time VARNAME VALUE — jq が出した `"%w %H:%M"` / `"%H:%M"` / `"now"` / `""` を表示形にする
# （曜日を英語名に、必要なら 12 時間と `Z` を適用。**fork ゼロ**）
fmt_time() {
  local _v="$2"
  if [[ -z "$_v" || "$_v" == now ]]; then printf -v "$1" '%s' "$_v"; return; fi
  local _wd="" _hm="$_v"
  if [[ "$_v" =~ ^([0-6])" "(.*)$ ]]; then
    _wd="${WDAY[${BASH_REMATCH[1]}]} "; _hm="${BASH_REMATCH[2]}"
  fi
  if [[ -n "$_tf12" && "$_hm" == *:* ]]; then
    local _h="${_hm%%:*}" _ap="AM"
    local _m="${_hm#*:}"
    _h=$((10#$_h))
    ((_h >= 12)) && _ap="PM"
    ((_h > 12)) && _h=$((_h - 12))
    ((_h == 0)) && _h=12
    _hm="${_h}:${_m} ${_ap}"
  fi
  printf -v "$1" '%s' "${_wd}${_hm}${_tfz}"
}
fmt_time five_at "$five_at"
fmt_time seven_at "$seven_at"
# **jq が読めなかったことを黙らない** — 抽出が丸ごと失敗すると全変数が初期値のままになり、
# **要素が静かに消えて 1 行だけの出力**になる（fixture を壊して実測）。それは「入力が壊れている」
# ではなく「何も起きていない」に読める = 誤読。v1 は `jq error` を赤で出していたので踏襲する。
# **表示できないことより、読めないと言えないことの方が悪い。**
#
# **算術に入れる値は数値に正規化する** — jq が落ちて eval されなかったときに
# `((cost_cents > 0))` が syntax error になり、毎描画 stderr が漏れる（ahead/behind で 1 回踏んだ）。
[[ "$cost_cents" =~ ^[0-9]+$ ]] || cost_cents=0
[[ "$_NOW" =~ ^[0-9]+$ ]] || _NOW=0

# ── 宛名: `<config dir>/sessions/<pid>.json` の `name`（cross-session messaging のアドレス）──
# stdin の `session_name` は**右上の表示名**（customTitle ?? aiTitle）で宛先ではないので使わない。
# `"formerNames"` から先は捨てる（過去の名前を拾うと誤配になる）。
peer=""
if has_val "$session_id"; then
  for _sf in "${CONFIG_DIR}"/sessions/*.json; do
    [[ -r "$_sf" ]] || continue
    IFS= read -r _sl < "$_sf" || true
    [[ "$_sl" == *"\"sessionId\":\"${session_id}\""* ]] || continue
    _sl="${_sl%%'"formerNames"'*}"
    [[ "$_sl" == *'"name":"'* ]] || continue
    peer="${_sl#*'"name":"'}"; peer="${peer%%'"'*}"
    break
  done
fi

# ── provider 検出（**fork ゼロ**。env と `model.id` だけ）────────────────────
# **判定は `model_id`** — `model_show` には `display_name` の "Opus 5" が入りうる。Bedrock の
# inference profile は `us.` / `eu.` / `apac.` などのリージョン prefix を持つ。
# **なぜ出すか**: 同じ "Opus 5" でも**どのアカウントに課金されるかが違う**。案件用の config dir
# （Bedrock）と個人用が画面で区別できないと、コストの読み違えが起きる。
provider=""
if [[ "$model_id" =~ ^(global|jp|us-gov|us|eu|au|apac)\. ]] \
   || [[ "${CLAUDE_CODE_USE_BEDROCK:-}" == "1" ]] || [[ "${CLAUDE_CODE_USE_MANTLE:-}" == "1" ]]; then
  provider="bedrock"
elif [[ "${CLAUDE_CODE_USE_VERTEX:-}" == "1" ]];  then provider="vertex"
elif [[ "${CLAUDE_CODE_USE_FOUNDRY:-}" == "1" ]]; then provider="foundry"
fi

# ── 契約プランとモデル別週間枠（背景取得 + キャッシュ 1 個）──────────────────
# **hot path は fork ゼロ** — キャッシュを `read` で読むだけ。取得は背景 subshell 1 本で、
# **Keychain の blob 1 回から契約プランと OAuth token の両方**を取り、同じ subshell で
# `/usage` を叩く。v1 は subscription（3600s）と usage（300s）で**キャッシュ 2 個・背景 2 本**
# だったが、blob が共通なので 1 本に畳める（TTL は短い方に合わせる = 背景なので損がない）。
#
# **鮮度はレコードの `ts` で見る**（`stat` を呼ばない = hot path の fork を増やさない）。
# v1 はこの方式を却下していたが、理由は「延命 touch が read-modify-write になり lost update を
# 作る」だった。**v2 は touch を使わず、失敗時も既存値 + 新しい ts で全体を書き直す**ので
# その経路が無い（atomic mv なので並走しても記録が裂けることはない）。
#
# **Bedrock / Vertex / Foundry では取得しない** — OAuth アカウントは課金先と無関係なので、
# 別アカウントのプラン名と枠を出す = 誤読になる（「無表示 < 誤読」）。
# **レコードは自己記述の key-value 行。** `キー US 値…` を 1 行 1 件で並べる。位置に依存しないので
# ① **未知のキーは読み飛ばす**（新しい版が書いたファイルを古い版が読んでも死なない）
# ② **無いキーは既定値**（古い版が書いたファイルを新しい版が読んでも死なない）
# ③ **項目追加でレコードが無効化されない**ので、上流に追従して要素を足しても**取り直しの一斉発生
#    （= 429 の再演）が起きない**。位置固定の `read -r a b c d e` は中間に足すと桁が全部ずれる。
#
# **鮮度は出所ごとに持つ**（`at.plan` / `at.limits`）。プランは Keychain、枠は `/usage` の curl で
# **失敗の仕方が別**なので、`ts` 1 個だと「429 で枠だけ古い」を表現できない。出所ごとに持つと
# 片方が落ちても他方の TTL を巻き込まない。**判定は値の有無ではなく時刻**で見る — 「枠 0 件で
# 成功」と「取れていない」を区別できる（今までは `_lim_ok` フラグで場当たりに分けていた）。
#
# **`tz` が食い違ったら枠だけ捨てる。** リセットは表示文字列まで背景で焼くので tz を変えたら
# 焼き直しが要るが、**プランは tz と無関係**なので巻き込まない（今までは全部捨てていた）。
#
# **繰り返しキー `limit` で N 個のモデルにスケールする。** 新しい種類のデータ（usage credits 等）を
# 足すときも**キーを 1 つ増やすだけ**で、ファイルもレイアウトも増やさない。
_C_plan="" _C_tier="" _C_tz="" _C_lim="" _C_at_plan=0 _C_at_lim=0 _C_ok_plan=0 _C_ok_lim=0
read_acct_cache() {
  _C_plan="" _C_tier="" _C_tz="" _C_lim="" _C_at_plan=0 _C_at_lim=0 _C_ok_plan=0 _C_ok_lim=0
  [[ -r "$ACCT_CACHE" ]] || return 0
  local _k="" _a="" _b="" _c="" _sc="" _has_ok=""
  # **`|| [[ -n "$_k" ]]` が必須** — 末尾に改行が無い行では `read` が rc=1 を返すので、
  # 付けないと**最後の 1 行が丸ごと無視される**（書き側は必ず改行で終えるが、
  # 途中で切れたファイルを読む経路が残る）。
  while IFS=$'\037' read -r _k _a _b _c || [[ -n "$_k" ]]; do
    case "$_k" in
      schema)    _sc="$_a" ;;
      plan)      _C_plan="$_a" ;;
      tier)      _C_tier="$_a" ;;
      tz)        _C_tz="$_a" ;;
      at.plan)   _C_at_plan="$_a" ;;
      at.limits) _C_at_lim="$_a" ;;
      ok.plan)   _C_ok_plan="$_a"; _has_ok=1 ;;   # 最後に**取れた**時刻（claim では進めない）
      ok.limits) _C_ok_lim="$_a"; _has_ok=1 ;;
      limit)     [[ -n "$_a" ]] && _C_lim="${_C_lim}${_C_lim:+$'\n'}${_a}${_USEP}${_b}${_USEP}${_c}" ;;
    esac
  done < "$ACCT_CACHE"
  if [[ "$_sc" != "$ACCT_SCHEMA" ]]; then
    _C_plan="" _C_tier="" _C_tz="" _C_lim="" _C_at_plan=0 _C_at_lim=0 _C_ok_plan=0 _C_ok_lim=0
    return 0
  fi
  [[ "$_C_at_plan" =~ ^[0-9]+$ ]] || _C_at_plan=0
  [[ "$_C_at_lim"  =~ ^[0-9]+$ ]] || _C_at_lim=0
  [[ "$_C_ok_plan" =~ ^[0-9]+$ ]] || _C_ok_plan=0
  [[ "$_C_ok_lim"  =~ ^[0-9]+$ ]] || _C_ok_lim=0
  # **`ok.*` を知らない版が書いたレコードは `at.*` で読み替える**（旧レコードの救済）。
  # これが無いと**アップグレード直後にプランと枠が消え、claim のせいで次の取得まで最大 300 秒
  # 戻らない**。「無いキーは既定値」の既定値が 0 だと退化が強すぎる例。**キーが 1 つでも
  # あれば救済しない** — 取得が失敗し続けている状態で `at.*` に読み替えると上限が永久に来ない。
  if [[ -z "$_has_ok" ]]; then _C_ok_plan="$_C_at_plan"; _C_ok_lim="$_C_at_lim"; fi
  # tz が違うのは枠の表示文字列だけ（プランは巻き込まない）
  [[ "$_C_tz" == "$_tz" ]] || { _C_lim=""; _C_at_lim=0; }
  return 0
}

write_acct_cache() {
  # **1 本の文字列にしてから 1 回で書く**（`>>` を並べると途中の失敗で裂けたレコードが残る）。
  # **US は変数（`_USEP`）で渡す** — `printf` の書式に埋めるとクォートが閉じてリテラルの
  # `$037` を書き出す（実際に踏んだ）。
  local _o="" _rest="$_C_lim" _l
  _o="schema${_USEP}${ACCT_SCHEMA}"$'\n'
  _o="${_o}tz${_USEP}${_tz}"$'\n'
  _o="${_o}plan${_USEP}${_C_plan}"$'\n'
  _o="${_o}tier${_USEP}${_C_tier}"$'\n'
  _o="${_o}at.plan${_USEP}${_C_at_plan}"$'\n'
  _o="${_o}at.limits${_USEP}${_C_at_lim}"$'\n'
  _o="${_o}ok.plan${_USEP}${_C_ok_plan}"$'\n'
  _o="${_o}ok.limits${_USEP}${_C_ok_lim}"$'\n'
  while [[ -n "$_rest" ]]; do
    _l="${_rest%%$'\n'*}"
    if [[ "$_rest" == *$'\n'* ]]; then _rest="${_rest#*$'\n'}"; else _rest=""; fi
    [[ -n "$_l" ]] && _o="${_o}limit${_USEP}${_l}"$'\n'
  done
  # **中間ファイル名に PID を入れる** — 固定名だと並走ペインが同じ `.tmp` に書いて混ざる
  local _t="${ACCT_CACHE}.tmp-$$"
  printf '%s' "$_o" > "$_t" && mv "$_t" "$ACCT_CACHE"
}

plan_type="" rate_tier="" scoped=""
fetch_account() {
  [[ -z "$provider" ]] || return 0                       # 非 Anthropic は素通り
  read_acct_cache
  plan_type="$_C_plan" rate_tier="$_C_tier" scoped="$_C_lim"
  # **確認できなくなって久しい値は出さない。** `at.*` は claim で毎回進むので「取れているか」を
  # 表さない。`ok.*`（最後に取れた時刻）で見て、上限を超えたら要素ごと落とす。
  (( _NOW - _C_ok_plan > ACCT_MAX_AGE )) && { plan_type="" rate_tier=""; }
  (( _NOW - _C_ok_lim  > ACCT_MAX_AGE )) && scoped=""
  # **判定は出所ごとの時刻だけ**（値の有無を混ぜない）。取れていなければ `at.*` は 0 なので必ず古い。
  local _need=""
  (( _NOW - _C_at_plan > ACCT_TTL )) && _need=1
  (( _NOW - _C_at_lim  > ACCT_TTL )) && _need=1
  # **`CLAUDE_STATUSLINE_NO_NET` は fetch だけを止め、キャッシュの読みは残す**（v1 の usage 側と
  # 同じ非対称。「外に問い合わせない」seam であって「表示しない」seam ではない）。
  if [[ -n "$_need" && -z "${CLAUDE_STATUSLINE_NO_NET:-}" ]]; then
    # 書くのは背景 subshell なので、起動前にここでディレクトリを用意する
    # （**BSD の `mkdir -p -m` は最後のディレクトリにしか mode を当てない**ので 1 段だけにする）
    [[ -d "$CACHE_BASE" ]] || mkdir -p -m 700 "$CACHE_BASE" 2>/dev/null
    (
      local _blob="" _rec="" _tok="" _plan="" _tier="" _out="" _lim="" _lim_ok=""
      # **先に claim を打つ**（値は現状のまま、`at.*` だけ今の時刻にする）。これが無いと、
      # `refreshInterval` で定期再実行している**並走セッションが同じ瞬間に「期限切れ」と判定し、
      # N 本の curl を同時に出す**（thundering herd）。fetch は `curl -m 4` で最大 4 秒かかるので
      # 窓が広い。claim を先に書けば窓が `mv` までの数 ms に縮む。**取れなくても `at.*` が
      # 進んでいるので、次の描画で毎回 fetch する storm にもならない。**
      _C_at_plan="$_NOW"; _C_at_lim="$_NOW"
      write_acct_cache
      local _svc="Claude Code-credentials" _hd="$SECURESTORAGE_HASH_DIR"
      # **Keychain のサービス名は config dir ごとに変わる**（`Claude Code-credentials` +
      # その config dir の **sha256 先頭 8 桁**）。決め打ちで引くと**別アカウントの blob**を読む。
      # **算出できないときは Keychain ごと飛ばす**（決め打ちに落ちるより無表示が安全）。
      local _skip=""
      if [[ -n "$_hd" ]]; then
        local _h; _h=$(printf '%s' "$_hd" | shasum -a 256 2>/dev/null) || _h=""
        _h="${_h%% *}"
        if [[ "$_h" =~ ^[0-9a-f]{8} ]]; then _svc="${_svc}-${_h:0:8}"; else _skip=1; fi
      fi
      if [[ -z "$_skip" ]] && command -v security >/dev/null 2>&1; then
        # **読みは `-a <USER>` 込み** — 上流は account 属性込みで識別するので、service だけで
        # 引くと同名 item が 2 つある keychain で別アカウントの blob を読む
        local _acct="${USER:-${LOGNAME:-}}"
        if [[ -n "$_acct" ]]; then
          _blob=$(security find-generic-password -s "$_svc" -a "$_acct" -w 2>/dev/null)
        else
          _blob=$(security find-generic-password -s "$_svc" -w 2>/dev/null)
        fi
      fi
      # ファイル fallback（`-r` で gate する。**`$(<f 2>/dev/null)` は 3.2 で常に空**になる）。
      # **`CONFIG_DIR` ではなく `SECURESTORAGE_DIR`** — 上流はこのファイルだけそちらに置く。
      if [[ -z "$_blob" && -r "${SECURESTORAGE_DIR}/.credentials.json" ]]; then
        _blob=$(<"${SECURESTORAGE_DIR}/.credentials.json")
      fi
      if [[ -n "$_blob" ]]; then
        # **契約種別・枠・token を 1 回の jq で**。here-string は 3.2 で一時ファイルを作るので
        # パイプで渡す（token をディスクに落とさないのは argv に出さないのと同じ理由）
        _rec=$(printf '%s' "$_blob" | jq -r '"\(.claudeAiOauth.subscriptionType // "")\u001f\(.claudeAiOauth.rateLimitTier // "")\u001f\(.claudeAiOauth.accessToken // "")"' 2>/dev/null)
        _plan="${_rec%%$'\037'*}"; _rec="${_rec#*$'\037'}"
        _tier="${_rec%%$'\037'*}"; _tok="${_rec#*$'\037'}"
      fi
      if [[ -n "$_tok" ]]; then
        # **Bearer は `-H @-`（stdin）で渡す** — argv には `@-` しか出ないので `ps` 漏れが無く、
        # 各行が必ずヘッダとして解釈されるのでトークンに何が入っても curl のオプションに化けない。
        # **`--config -` は使わない**（各行が設定ディレクティブ = `output = <path>` の注入経路）。
        _out=$(printf 'Authorization: Bearer %s\nanthropic-beta: oauth-2025-04-20\n' "$_tok" \
               | curl -s -m 4 -H @- https://api.anthropic.com/api/oauth/usage 2>/dev/null)
        # **モデル別の週間枠だけ拾う**（`group == "weekly"` かつ scope にモデル名があるもの）。
        # **リセット時刻は表示文字列まで背景で作る**（描画側で `date` fork を増やさない、の適用）。
        # **分単位に丸める** — 実データの `resets_at` は `15:59:59.6` のような値で、切り捨てると
        # 隣の `week:` が `16:00` と出すのと 1 分ずれて別の時刻に見える。
        # **`try … catch ""` で包む** — `resets_at` の型不正 1 件で jq が abort すると**枠が全滅**する
        # （`.limits` が配列でも中身で落ちる経路は型ガードだけでは塞げない）。
        # **型ガードを通す** — 型不正の枠が 1 つあると jq が abort して**枠が全滅する**。
        # `is_active` / `severity` で絞らない（意味論が未文書）。
        # **名前の制御文字を空白化する** — 生の US や改行はレコードを割り、3 行契約も割る。
        # **使える応答かは「`.limits` が配列か」で見る** — `curl -s` は `-f` を付けていないので
        # **401/429/5xx のエラー JSON も本文として来る**（実際に 429 を踏んだ）。エラー本文では
        # `.limits` が absent なので、`// []` を付けたままだと「枠 0 件の成功」と区別できず、
        # **ディスクにある良い値を空で上書きして 300s 消す**。`NA` を返させて分岐する。
        # 配列だが週間枠が 0 件のときは空文字列 = 「本当に枠が無い」として正しく空を書く。
        _lim=$(printf '%s' "$_out" | jq -r '
          if (.limits | type) != "array" then "NA" else
          (.limits) | map(select(
              (type == "object") and (.group? == "weekly")
              and ((.scope?.model?.display_name? // "") != "")
              and ((.percent? | type) == "number")))
          | map("\(.scope.model.display_name | gsub("[[:cntrl:]]"; " "))\u001f\(.percent | round)"
                 + "\u001f" + (try (.resets_at
                     | if type == "string" then
                         (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdate
                          | ((. + 30) / 60 | floor) * 60 | strflocaltime("%w %H:%M"))
                       else "" end) catch ""))
          | .[] end' 2>/dev/null)
        # `&&`/`||` の連鎖にしない（`{ }` の rc に依存する形は読み間違えやすい）
        if [[ "$_lim" == "NA" ]]; then _lim=""; else _lim_ok=1; fi
      fi
      # **プランと枠は別々に判定する** — 出所が違う（プラン = Keychain の blob / 枠 = `/usage` の
      # curl）ので、片方が失敗しただけでもう片方を捨ててはいけない。実際に踏んだ: 429 のときに
      # blob だけ成功して**枠が空で上書きされた**。
      #
      # **書く直前に読み直して、取れた出所だけ上書きする。** fork 時点の値を書き戻すと、その間に
      # **別の subshell が成功して書いた新しい値を古い値で潰す**（実測: 2 本同時のうち先に返った
      # 側が成功し、遅れて返った側が 429 だと、成功した枠が巻き戻った）。claim は「fetch 中の
      # 他セッションを止める」役しか果たしておらず、**書き込みの順序は守らない**。
      # 取れなかった出所は**読み直した値と `at.*` がそのまま残る**（claim 済みなので storm にならない）。
      read_acct_cache
      if [[ -n "$_plan" ]]; then _C_plan="$_plan"; _C_tier="$_tier"; _C_at_plan="$_NOW"; _C_ok_plan="$_NOW"; fi
      if [[ -n "$_lim_ok" ]]; then _C_lim="$_lim"; _C_at_lim="$_NOW"; _C_ok_lim="$_NOW"; fi
      write_acct_cache
    # **`>/dev/null 2>&1` が背景化の必須条件** — 付けないと subshell が親の stdout（Claude Code が
    # 読む pipe）を握ったままになり、読み手は最後の fd 保持者が終わるまで EOF を見ない。
    # ここが最も効く（`curl -m 4` は最大 4 秒粘るので、無いと描画が 4 秒止まる）。
    ) >/dev/null 2>&1 & disown
  fi
  return 0
}
fetch_account

# ── リポの位置と git dir を **fork ゼロ**で解決する ─────────────────────────
# **`.git` を上へ辿る。** 以前は `current_dir/.git` の存在だけを gate にしていて、**リポの
# サブディレクトリに `cd` するとブランチが丸ごと消えていた**（`docs/` で実測。v1 は
# `git -C` に任せていたので起きなかった退化）。辿りは `${_d%/*}` の文字列操作だけなので fork 0。
# 同時に **git dir** も取れる — 進行中の操作（rebase/merge/…）の判定に必要で、v1 は
# `git rev-parse --absolute-git-dir` に 1 fork 払っていたが、ここでは払わない。
_repo="" _gd="" _d="$current_dir"
while [[ -n "$_d" && "$_d" != "/" ]]; do
  if [[ -e "$_d/.git" ]]; then _repo="$_d"; break; fi
  # **`/` を含まなくなったら抜ける。** `${_d%/*}` は `/` の無い文字列を**変えずに返す**ので、
  # これが無いと `.` や `foo` で**無限ループ（100% CPU で永久に回る）**。`current_dir` の既定は
  # `"."` で、**jq が落ちた・jq が無い場合も `.` のまま**なので、「jq 未インストールで
  # git 管理外のディレクトリを開いた」だけで踏む（本体は毎描画呼ぶのでプロセスが溜まる）。
  [[ "$_d" == */* ]] || break
  _d="${_d%/*}"
done
[[ -z "$_repo" && -e "/.git" ]] && _repo="/"     # `/` 直下のリポ（稀だが素通りさせない）
# **`_repo` が空のときは触らない** — 空だと `"$_repo/.git"` が `/.git` に化ける。上の行で
# `/` 直下のリポは既に拾っているので実害は無いが、判定が「上の行の順序」に依存するのをやめる。
if [[ -z "$_repo" ]]; then
  :
elif [[ -d "$_repo/.git" ]]; then
  _gd="$_repo/.git"
elif [[ -f "$_repo/.git" ]]; then
  # worktree と submodule は `.git` が **`gitdir: <path>` 1 行のファイル**。相対パスもありうる。
  IFS= read -r _gl < "$_repo/.git" || true        # 末尾改行が無いと rc=1 なので `|| true`
  if [[ "$_gl" == "gitdir: "* ]]; then
    _gd="${_gl#gitdir: }"
    [[ "$_gd" == /* ]] || _gd="$_repo/$_gd"
  fi
fi

# ── git: 同期で **1 回**だけ（キャッシュなし）───────────────────────────────
# `status --porcelain=v2 -b` 1 発で branch.head / branch.ab（ahead/behind）/ **`u` 行（conflicts）**
# が取れる。**conflicts は追加コストがゼロ** — `-uno` は untracked を止めるだけで、
# **unmerged の `u UU …` 行は消えない**（実測で確認）。
# 行数は porcelain が持たないが**もう出さない**（`/cost` の `Total code changes` から取り戻せる）。
# `-uno` で untracked を数えない = リポのサイズにほぼ依存しない（5878 ファイルでも 16.8ms 実測）。
branch="" ahead="" behind="" conflicts=0 _oid="" _detached=""
if [[ -n "$_repo" ]]; then
  while IFS= read -r _l; do
    case "$_l" in
      '# branch.oid '*)  _oid="${_l#\# branch.oid }" ;;
      '# branch.head '*) branch="${_l#\# branch.head }" ;;
      '# branch.ab '*)   _ab="${_l#\# branch.ab }"; ahead="${_ab%% *}"; behind="${_ab#* }" ;;
      'u '*)             conflicts=$((conflicts + 1)) ;;
    esac
  done < <(git -C "$_repo" --no-optional-locks status --porcelain=v2 -b -uno 2>/dev/null)
fi
# **detached は赤で、sha も出す。** 「アラームの赤 31 は状態専用」に detached が
# 入っている。ここを普通のブランチと同じ橙で `HEAD` とだけ描くと、**detached checkout が
# 平常の状態に見え**、どのコミットに居るかも消える。`# branch.oid` から短縮 sha を作る。
_detached=""
if [[ "$branch" == "(detached)" ]]; then
  _detached=1
  if [[ "$_oid" =~ ^[0-9a-f]{7,} ]]; then branch="HEAD@${_oid:0:7}"; else branch="HEAD"; fi
fi
# `# branch.ab` は upstream が無いと出ないので、**必ず数値に正規化する**
# （空のまま算術に入れると `(( > 0))` で syntax error = stderr が毎描画漏れる）
ahead="${ahead#+}"; behind="${behind#-}"
[[ "$ahead"  =~ ^[0-9]+$ ]] || ahead=0
[[ "$behind" =~ ^[0-9]+$ ]] || behind=0

# ── 進行中の git 操作（**fork ゼロ**。ディスクのレイアウトを直接見る）──────────
# **なぜ出すか**: `feat/x` とだけ出ていると「マージ中」と「ただそのブランチにいる」が区別できない。
# diff パネルは **conflicts を出さない**（データ源は working tree vs HEAD の hunk と統計だけ。
# 2.1.260 のバイナリで確認）ので、ここは重複ではない。**一過性**（操作が終われば消える）なので
# 「常時見えるものは載せない」の物差しも通る。
#
# **arm はディスクレイアウト 1 つに 1 本**にする（v1 から踏襲）— 操作名は arm の中で導出する。
# `rebase-apply` を 2 arm に割ると進捗ファイルの組（`next`/`last`）が複製され、名前が変わったとき
# 片方だけ直す事故になる。進捗ファイルは **interactive rebase = `msgnum`/`end`、`git am` 系の
# rebase-apply = `next`/`last`** で名前が違うので両方見る。
op="" _cf="" _tf=""
if [[ -n "$_gd" ]]; then
  if   [[ -d "$_gd/rebase-merge" ]]; then op="rebase"; _cf="$_gd/rebase-merge/msgnum"; _tf="$_gd/rebase-merge/end"
  elif [[ -d "$_gd/rebase-apply" ]]; then
    # `rebase-apply` は `git am` でも作られる。`applying` があれば am
    # （`git rebase --abort` を打とうとして「am には無い」と気づく手戻りを防ぐ）
    if [[ -f "$_gd/rebase-apply/applying" ]]; then op="am"; else op="rebase"; fi
    _cf="$_gd/rebase-apply/next"; _tf="$_gd/rebase-apply/last"
  elif [[ -f "$_gd/MERGE_HEAD" ]];       then op="merge"
  elif [[ -f "$_gd/CHERRY_PICK_HEAD" ]]; then op="cherry-pick"
  elif [[ -f "$_gd/REVERT_HEAD" ]];      then op="revert"
  elif [[ -f "$_gd/BISECT_LOG" ]];       then op="bisect"
  fi
  # rebase 以外は `_cf`/`_tf` が空なので `-r` が偽 = 素通り。読めない / 数値でなければ操作名だけ出す
  if [[ -r "$_cf" && -r "$_tf" ]]; then
    IFS= read -r _cur < "$_cf" || true            # `$(<file)` は fork するので read で取る
    IFS= read -r _tot < "$_tf" || true
    [[ "$_cur" =~ ^[0-9]+$ && "$_tot" =~ ^[0-9]+$ ]] && op="${op} ${_cur}/${_tot}"
  fi
fi

# ── 整形 ──────────────────────────────────────────────────────────────────
# パスは $HOME を ~ に。worktree 配下ならリポ root までで切る（v1 と同じ作法）。
_path="$current_dir"
if [[ -n "$wt_name" && "$_path" == *"$WT_MARKER"* ]]; then _path="${_path%%"$WT_MARKER"*}"; fi
# **前方一致ではなくパス成分で見る** — `"$HOME"*` だと `/Users/user2/dev` が `~2/dev` になり、
# **実在しないディレクトリに読める**（無表示より悪い誤読）。`$HOME` そのものと配下だけ畳む。
if [[ "$_path" == "$HOME" ]]; then _path="~"
elif [[ "$_path" == "$HOME"/* ]]; then _path="~${_path#"$HOME"}"; fi

# ── 版: 最新から遅れている間だけ赤くする ──────────────────────────────────
# 最新版は **Claude Code 自身が置いたキャッシュ**（`<config dir>/cache/changelog.md` 冒頭の
# `## X.Y.Z`）から読む。**ネットワークもキャッシュ書き込みも fork もゼロ**。
# **状態を持たない** — 「今の版 vs 最新版」だけで決まるので、更新すれば次の描画で自然に dim へ戻る。
# 読めない / 形式が変わった / 追いついている ときは**すべて dim**（無表示 < 誤読）。
# 読む行数に上限を置く（`## ` を持たない形式に変わったとき 600KB を毎描画読み切らないため）。
ver_col="$DIMVER"
if has_val "$cc_version"; then
  _latest="" _scan=0 _cl="${CONFIG_DIR}/cache/changelog.md"
  if [[ -r "$_cl" ]]; then
    while IFS= read -r _line; do
      if [[ "$_line" == '## '* ]]; then _latest="${_line#'## '}"; break; fi
      ((++_scan >= 20)) && break
    done < "$_cl"
  fi
  # 比較は数値（文字列だと 2.1.9 > 2.1.10 になる）。下の `ver_older` を使う。
  [[ -n "$_latest" ]] && ver_older "$cc_version" "$_latest" && ver_col="$VEROLD"
fi

# ── 行を組む ──────────────────────────────────────────────────────────────
line1=() line2=() line3=()

# **jq が読めなかったら真っ先に言う**（他の要素は初期値のままなのでほぼ空になる）
[[ -n "$_jq_ok" ]] || line1+=("${RED}jq error${RST}")
# **宛名は行の先頭**（2026-09-04 にユーザー指示で provider と入れ替えた）。**理由は「並走ペインの
# 見分け」** — 3〜5 ペインを並べたとき、行頭が揃っている位置にあるものだけが視線を動かさずに読める。
# **プランは全ペインで同じ値なので、先頭を占める価値が最も低い**（当初は「課金先は宛名より先に効く」
# として provider を先頭にしていたが、**課金先が違うペインを同時に開くのは稀で、宛名は毎ペイン違う**。
# 差分がある要素を先に置く、が正しい向き）。宛名の詳細（`sessions/<pid>.json` の `name`・
# 記号も囲みも付けない・キャッシュを持たない・逆順なら丸ごと落とす）は上の宛名の抽出部に書いた。
has_val "$peer" && line1+=("$peer")
# **provider / プランは宛名の次** — 「どのアカウントに課金されるか」は同じ "Opus 5" でも違うので
# モデルより前に置く。**Anthropic 直のときは契約プランを括弧に入れて 1 要素にする**
# （`( )` は要素内の区切りにだけ使う、の適用）。プランが取れなければ何も出さない。
case "$provider" in
  bedrock) line1+=("${BDCK}Bedrock${RST}") ;;
  vertex)  line1+=("${VTEX}Vertex${RST}") ;;
  foundry) line1+=("${FNDY}Foundry${RST}") ;;
  *) if has_val "$plan_type"; then
       plan_label _pl "$plan_type" "$rate_tier"
       line1+=("${ANTH}Anthropic(${_pl})${RST}")
     fi ;;
esac
# **`(1M context)` は落とす** — 本体は `display_name` に付けてくるが、① 多色スイープが 19 文字に
# 伸びて色の意味が薄れる ② 1M であることは 3 行目の分母 `/1M` が既に示している。
# 落とすのは末尾の suffix だけで、モデル名そのものは触らない。
if has_val "$model"; then
  _mshow="${model% (1M context)}"
  model_color _mc "$_mshow" "$model_id"; line1+=("$_mc")
fi
if has_val "$effort_level"; then effort_color _ec "$effort_level"; line1+=("$_ec"); fi
# **fast モードは on のときだけ出す** — 差分がシグナル（既定は off）。
# **なぜ出すか**: Opus 5 の fast は **$10/$50 per MTok**（標準は $5/$25）= **単価 2 倍**。
# 隣の `$` の数字の意味that変わるのに、**組み込みはどこにも常時表示しない**（`/status` と `/fast`
# だけ）。物差しの②「決断のトリガー」を通る唯一の残り要素だった。
# **`fast_mode` は教典①（`/statusline` のプロンプト）に載っていない** — 公開 docs の
# フィールド表（"Whether fast mode is enabled for the session"）と例示 payload だけが裏取り。
# `cost` / `exceeds_200k_tokens` と同じクラスで、**プロンプトのスキーマは網羅ではない**。
[[ "$fast_mode" == "true" ]] && line1+=("${FAST}fast${RST}")
# 版は**行の最後**（行動に効かない参照情報なので、溢れたとき最初に削られてよい）
has_val "$cc_version" && line1+=("${ver_col}v${cc_version}${RST}")

[[ "$_path" != "." ]] && line2+=("$_path")
has_val "$wt_name" && line2+=("${DIM}🌲${wt_name}${RST}")
if has_val "$branch"; then
  if [[ -n "$_detached" ]]; then line2+=("${RED}${branch}${RST}"); else line2+=("${GIT}${branch}${RST}"); fi
fi
# **op と conflicts はブランチの直後**（ブランチの状態を限定する事実なので隣に置く）。
# **色は RED** — 「アラームの赤 31 は状態専用（detached / conflicts / behind / …）」
# に conflicts と進行中操作の両方が含まれる。**平常時は両方とも出ない**ので桁を食わない。
has_val "$op" && line2+=("${RED}${op}${RST}")
((conflicts > 0)) && line2+=("${RED}!${conflicts}${RST}")
# **変更行数は出さない**（diff パネルが `5 files changed +2 -26` を出す）。
# ahead/behind だけ残す — パネルに無く、上の 1 回の git にタダで乗っている。
_chg=""
((ahead  > 0)) && _chg="${DIFF_ADD}↑${ahead}${RST}"
((behind > 0)) && _chg="${_chg:+$_chg }${DIFF_DEL}↓${behind}${RST}"
[[ -n "$_chg" ]] && line2+=("$_chg")

if [[ "$used_pct" =~ ^[0-9]+$ ]]; then
  braille_bar "$used_pct" _bar
  # **上は `LIMIT_HI` と同じ数字を渡す** — 「3 行目の閾値は 1 つ」（CHANGELOG 2.2.0）を
  # 実装でも保つため。リテラルの 90 を残すと `LIMIT_HI` を動かしたときにここだけ取り残される。
  color_by_threshold "$used_pct" "$LIMIT_HI" 80 _cc
  _den=""; ((ctx_size > 0)) && { fmt_ctx_size "$ctx_size" _ds; _den="/$_ds"; }
  # **バーと数値の間は空白 1 つ**（2026-09-08 にユーザー指示で 3 → 1）。`braille_bar` は空きを
  # **空白**で埋めるので、そこに 3 つ足すと**埋まり具合しだいで隙間が 3〜8 桁**になる（81% で
  # 4 桁、31% で 6 桁。実機で「空きすぎ」）。1 つにすると 1〜6 桁に締まり、**枠の 3 要素と
  # 作法も揃う**。バーは常に 5 セルなので**数値の桁位置は動かない**（この性質だけは維持する）。
  line3+=("${_cc}${_bar} ${used_pct}%${_den}${RST}")
fi
# ── セッションの課金額（stdin の `cost.total_cost_usd`。**fork もネットワークもゼロ**）──
# 全プロバイダー共通で **Claude Code 自身が計算した API 換算 USD**。
# **教典①（組み込み `/statusline` のプロンプト）にはこのフィールドが載っていない** — 2.1.260 でも
# JSON スキーマのブロックに `cost` が 1 度も出てこない。実在の裏取りは教典②③ 側:
# 公開 docs の例示 payload に `"cost": {"total_cost_usd": 0.01234, ...}` があり、CHANGELOG 2.1.246 に
# 「status line の cost と duration が agents view 往復で 0 に戻るのを修正」がある。**つまり
# プロンプトのスキーマも網羅ではない**（CHANGELOG が網羅でないのと同じクラスの罠）。
# **subscription では実請求されない参考値。** 実際に請求される分（usage credits）は同じ `/usage`
# の応答（`spend.used`）に乗っているが**出していない** — このアカウントは `spend.enabled: false`
# で構造的に使えず、出しても永久に空だから（2026-09-04 実測）。**取得コストはゼロ**なので、
# 有効になったら足せる。v1 は隣に `credits:$`（明るい gold, bold）を並べて「明るい方が実請求」の
# 序列を**色で**表していた。**v2 は片方しか出さないので色では区別が付かない** = この注記が唯一の
# 区別。だから金額を 2 つ並べる日が来たら色の序列ごと持ってくる。
# `> 0` の gate が「フィールドが無い（古い Claude Code）」と「$0.00」の**両方**を非表示に倒す。
if ((cost_cents > 0)); then
  printf -v _cost '$%d.%02d' $((cost_cents / 100)) $((cost_cents % 100))
  line3+=("${COST}${_cost}${RST}")
fi
# ── プロンプトキャッシュ: **cold の瞬間だけ出す** ────────────────────────────
# **判定基準（2026-09-04 に決めた。これが要素選択の物差し）:**
#   ① 組み込みが**常時見せている**もの（右上・中央・下・diff パネル）の複製は純粋な無駄
#   ② 組み込みの**スラッシュコマンド**（= 聞かないと出ない）の複製は、**「聞こうと思わなかった
#      問い」に答えるなら**無駄ではない。statusline の仕事は `/cost` の要約ではなく、
#      **`/cost` を打つ気にさせる最小限**を置くこと（何も怪しくないとき人は `/cost` を打たない）
#
# この基準で `prompt_cache` から残るのは **cold とその原因だけ**:
#   - **cold は一過性** — 窓が閉じたら `/cost` でも見られない。実例: ユーザーの `/cost` は
#     `warm` と出たが、cold は**その 1 分 14 秒前**に起きて既に終わっていた。**一過性の状態を
#     それが真である瞬間に出せるのは statusline だけ** = ここが唯一の置き場
#   - **`miss_recache_tokens`（`recache:4.2M`）は却下** — 累積なので**後から `/cost` で必ず
#     取り戻せる**うえ、「打つべきか」の判断は隣の `$` が既にしている（入れてから落とした）
#   - **`hit_ratio`（`cache:97%`）も却下** — 実データで反証: 375 req / 9 misses / 420 万トークン
#     再キャッシュ（上乗せ約 $24）で**率は 97% のまま動かない**。累計なので分母が育つほど鈍り、
#     **コストが出ている瞬間に画面が変わらない**
#   - **`recache_tokens_if_cold` も却下** — 実質 prefix のサイズで、左端の `52%/1M` の言い直し
#   この再検討条件（率なら「キャッシュが構造的に効いていない」実例が出たとき）は
#   **2.1.270 で到来した。率は採らず `caching_observed` を直接 gate にした**（次段） —
#   率を出しても「構造的に効いていない」と「たまたま cold」は区別できないが、
#   `caching_observed:false` は区別そのものだから。
#
# **`caching_observed:false` のときは cold ごと出さない**（2.1.270 で上流がこの gate を
# `/statusline` のプロンプトに明記した。教典① の例が
# `if .prompt_cache.caching_observed == true and .prompt_cache.warm == false` に変わった）。
# 理由: **キャッシュトークンを報告しないプロバイダ / ゲートウェイでは `warm` が常に `false`** に
# なるので、gate を入れないと**永久に `cold` が出続ける** = 「無表示 < 誤読」の誤読側。
# **判定は上流の `== true` ではなく `== false`**（= 明示的に false のときだけ落とす）。
# `caching_observed` は **2.1.270 のバイナリでは `prompt_cache` があれば無条件に載る**（教典④ で
# 確認。`prompt_cache` ごと absent になるのは `requests === 0` のときだけ）。**いつから同居して
# いるかは未確認** — 教典① は 2.1.258/259 の時点で `prompt_cache` 自体を書いていないので、
# 2.1.251 の導入時からか 2.1.260 で足されたかは裏が取れない。だから absent は
# **「載らない版がありうる」側に倒す** = 従来どおり cold を出す（`== true` にすると、その版で
# cold が黙って消える）。ここは動作に影響しない: absent は `== false` に一致しないので
# `elif` に落ち、`warm` の判定に進む。
#
# **`warm` の判定に jq の `//` を使わない** — `//` は `false` も absent に畳むので、まさに出したい
# cold が消える（2.1.260 のプロンプトが上流の作法として明記した）。**`prompt_cache` ごと absent は
# 旧 CC 専用の経路ではない** — 最初の API 応答までは毎セッション通る。
#
# **原因（`last_miss_cause.causes[0]`）は 2.1.260 の新フィールド**。閉じた集合なので**上流の綴りを
# そのまま出す**（独自の略号を作らない）。`[[:cntrl:]]` を空白化する — 生の制御文字は 3 行契約を割る。
#
# **色は寒色（`COLD` = xterm 81）で、RED も AMBER も使わない。** 赤を使わないのは、cold が
# 「壊れている」ではなく「お金がかかる」状態で、しかも**アイドル明けに正常に起きる**から
# （実データの 9 misses は全部 `idle past the 5m TTL`）— 赤にすると赤が狼少年になり、本当の
# アラーム（detached / behind / context 90%+ / **枠 90%+** / 遅れた版）が薄れる。
# **枠 90%+ を赤にした 2026-09-16 以降も、この判断は変えていない** — cold は毎日正常に起きるが、
# 枠が 9 割を超えるのは稀で「手が止まる」直前を指すので、赤の希少性を食わない。**AMBER も外した**理由は
# 上の `COLD` の定義に書いた（意味と色が逆・隣の `$` と溶ける・Venus パレットと番号衝突）。
if [[ "$pc_state" == "cold" ]]; then
  line3+=("${COLD}cold${pc_cause:+ $pc_cause}${RST}")
fi
if [[ "$five_pct" =~ ^[0-9]+$ ]]; then
  braille_bar "$five_pct" _fb
  # **90%+ は要素まるごと RED**（識別色の ANTH を置き換える。足さない）。
  _fc="$ANTH"; ((10#$five_pct >= LIMIT_HI)) && _fc="$RED"
  line3+=("${_fc}5h:${_fb} ${five_pct}%${five_at:+ $five_at}${RST}")
fi
_week_shown=""
if [[ "$seven_pct" =~ ^[0-9]+$ ]] && ((seven_pct > 0)); then
  _week_shown=1
  braille_bar "$seven_pct" _sb
  # **`5h` と同じ ANTH を一段落として使う**（2026-09-07 に確定）。`week` は `5h` と**同じ測り方で
  # 窓が長い方**なので、色相を変えると「別種のもの」に見えてこの対応が消える。dim の役②
  # （要素まるごと二次情報）は維持したまま、**色だけスクリプト側で確定させる**のが狙い —
  # `${DIM}` 単独だと**3 行目で唯一「色を指定していない要素」**になり、端末の既定前景色に
  # 依存して見た目がテーマで動く。新しい色相は 1 つも増やさない（3 行目は緑 82・金 136・
  # 氷青 81・タン 180・モデルのパレットで色の予算がほぼ埋まっている）。
  # **既知のリスク**: dim を 256 色と合成しない端末では `5h` と同じ色に見える。そのときの
  # 代替は色相を変えない一段暗い単色だが、**素直な「一段暗い 180」は 137 で Fable の
  # パレットに取られている**ので `144` / `101` へ振るしかなく色相がずれる（採らなかった）。
  # **90%+ では dim も外す** — dim の役②（要素まるごと二次情報）と「アラーム」は両立しない。
  # 尽きかけている枠は二次情報ではないので、**RED 単独**にして輝度を落とさない。
  _sc="${DIM}${ANTH}"; ((10#$seven_pct >= LIMIT_HI)) && _sc="$RED"
  line3+=("${_sc}week:${_sb} ${seven_pct}%${seven_at:+ $seven_at}${RST}")
fi
# ── モデル別の週間枠（`Fable:44%`）— stdin に無いので `/usage` から ──────────
# **モデル名は Line 1 と同じ `model_color`**（Fable なら Venus パレットの多色スイープ）。
# **`:` から先（バー・`N%`・時刻）は `_ecol` = 名前が終わった色の単色** — 1 要素に色系統を
# 2 つ入れない（グラデを担うのは名前だけ。下の「バー以降はグラデにしない」が経緯）。
# **90%+ ではスイープごと捨てて RED 1 色**（`LIMIT_HI`）。
# **`/usage` の `limits[]` は版を持たない `"Fable"` しか返さない**ので、`model_color` の
# generic な arm に落ちる。`model_color` の generic arm は**新しい方（5.1 = Venus）**に
# 向けてあるので Line 1 と色が揃う。
#
# **リセット時刻は `week:` と違うときだけ出す**（差分がシグナル。`effort` / `fast` と同じ作法）。
# 当初は「隣の `week:` が既に時刻を持つので重複」として落としていたが、**再検討条件に挙げていた
# 「`week:` とずれる実例」が実データで出た**（2026-09-04）: この口座は `/usage` の `seven_day` が
# `null` = **アカウント週間窓が無い**ので `week:` 自体が描かれず、`Fable:51%` が**行内で唯一
# 時刻を持たない枠**になっていた（残り 51% がいつ戻るのか読めない）。加えてモデル別枠の
# `resets_at`（土 16:00）は 5h（金 19:59）と別日で、**近い方の時刻から推測もできない**。
# 一致するときに省くのは、同じ時刻を 1 行に 2 回出さないため（`week:` がある口座はこちら）。
# **比較は書式済みの文字列同士**（`%a %H:%M` で揃えてある）。tz を追従させる版では、この文字列は
# 背景で作るので **tz と書式をキャッシュの鍵に足す**（v1 の `USAGE_FMT` に `tz,tf,loc` がある理由）。
_rest="$scoped"
while [[ -n "$_rest" ]]; do
  _line="${_rest%%$'\n'*}"
  if [[ "$_rest" == *$'\n'* ]]; then _rest="${_rest#*$'\n'}"; else _rest=""; fi
  [[ -n "$_line" ]] || continue
  _mname="${_line%%$'\037'*}"
  _rec2="${_line#*$'\037'}"
  _mpct="${_rec2%%$'\037'*}"
  # 3 つ目が無いレコード（旧い形式）でも桁がずれないように、有無で分ける
  if [[ "$_rec2" == *$'\037'* ]]; then _mrst="${_rec2#*$'\037'}"; else _mrst=""; fi
  [[ -n "$_mname" && "$_mpct" =~ ^[0-9]+$ ]] || continue
  # **0% は隠す（`week:` と同じ扱い。2026-09-16）。** モデル別枠も**週間の**枠なので、規則
  # 「0% を隠すのは週間の枠だけ」がそのまま当たる（`5h` だけが 0% でも出る = 左端の一目確認用）。
  # **0% のとき情報量がゼロ**だから隠す — 伝わるのは「このモデルに別枠がある」だけで、別モデルを
  # 常用していれば**来週も 0%** のまま最右を占め続ける（3 行目は左から優先度順なので、ここは
  # 狭い窓で最初に切られる位置）。非 0 になるのは実際にそのモデルを使ったときで、**それがまさに
  # 知りたい瞬間**なので取り逃さない。「0% のうちから別枠の存在を知らせる」は `/usage` を打てば
  # 分かるので、要素選択の物差し（一過性か決断のトリガーか）を通らない。
  ((10#$_mpct > 0)) || continue
  # **比較は表示形に直してから** — 生の `"6 16:00"` どうしでも一致するが、片方だけ 12 時間や
  # `Z` が付く経路が将来出たときに静かにずれる。`fmt_time` を通してから比べる。
  fmt_time _mrst "$_mrst"
  # **`week:` が実際に描かれたときだけ重複を落とす。** `week:` は 0% で隠れるので、
  # `seven_at` の有無だけで判定すると**週間枠がリセットされた直後（0%）に Fable の時刻まで
  # 消える** — この要素を足した理由（「行内で唯一時刻を持たない枠を作らない」）がそこで裏返る。
  # 週間窓を持つ口座では毎週必ず 0% を通るので、放置すると毎週再発する。
  [[ -n "$_week_shown" && "$_mrst" == "$seven_at" ]] && _mrst=""
  model_color _mcol "$_mname" "$_mname"
  # **時刻は dim にしない** — dim の 3 役（ラベル弱め / 要素まるごと二次情報 / プレースホルダ）の
  # どれでもなく**値**で、隣の `5h:16% 19:59` も時刻を通常輝度で出している。
  braille_bar "$_mpct" _mb
  # **バー以降はグラデにしない**（2026-09-08 にユーザー判断で撤回）。section ごとにスイープする
  # 版を実機で見て「グラデが見づらい」— **数値と時刻が 1 文字ずつ色を変えると読む速度が落ちる**。
  # グラデは**名前だけ**が担い、`:` から先は**名前が終わった色**（`_ecol`）の単色にする。
  # 却下版の残骸は下の履歴コメントに残す。
  #
  # 【却下】ブロックをセクションに割って、セクションごとにモデル色をスイープする
  # （2026-09-07 にユーザー指示「block ないで section 分けて その中でグラデ」）。
  # セクションは **名前+`:` / バーの埋まり桁 / `N%` / リセット時刻** の 4 つ。
  #
  # **`model_color` を section ごとに呼び直すだけでよい** — `model_key` は `SHOW|ID` を連結して
  # tier を**部分一致**で探すので、SHOW にバーや数字を渡しても ID 側の名前でキーが決まる。
  # パレットに触らずに済むので、**gradient / rainbow / flat / 色なしの 4 経路が全部そのまま
  # 効く**（flat なモデルは全 section 同色 = 従来と同じ絵、色なしは無色のまま）。
  # `printf -v` なのでフォークは増えない。
  #
  # **1 ブロックを 1 回でスイープしない理由**: 25 桁を 4 ストップで舐めると隣の文字が同色に
  # なってグラデに見えない。section ごとに舐め直すと**各部が必ず全ストップを通る**。
  # **空白（バーの空き）はスイープに入れない** — 見えない桁にストップを食われて、
  # 埋まっている側が先頭色だけになる。
  #
  # **各 section が先頭色（Fable なら `95` = brick）から始まることは受け入れる。** 名前の
  # `F` が既に brick で、それは気に入られている形なので、**全 section が同じ所から始まれば
  # 反復のリズムになる**（1 箇所だけ brick に戻ると「逆走」に見えたのが前案の問題だった）。
  # **名前が終わった色を取り出す。** `_mcol` は既に色付きの名前なので**追加の呼び出しも
  # フォークも要らない** — 末尾の RST を落として「最後の `ESC[`」以降を読めば、gradient でも
  # rainbow でも flat でも**最終文字に載った色**が取れる（Fable 5.1 なら `187` = cream）。
  # **色が付かないモデル（`model_color` の `*)` arm）では空にする** — ESC が無い文字列から
  # 切り出すと、名前そのものを色コードとして書き出してしまう。
  _ecol=""
  if [[ "$_mcol" == *$'\033['* ]]; then
    _et="${_mcol%$'\033[0m'}"; _et="${_et##*$'\033['}"; _et="${_et%%m*}"
    [[ "$_et" =~ ^[0-9\;]+$ ]] && _ecol=$'\033['"${_et}m"
  fi
  # **90%+ はスイープを捨てて要素まるごと RED**（`_mname` は色の付いていない生の名前）。
  # 識別色より状態を優先する理由は `LIMIT_HI` の宣言のコメント。
  if ((10#$_mpct >= LIMIT_HI)); then
    line3+=("${RED}${_mname}:${_mb} ${_mpct}%${_mrst:+ $_mrst}${RST}")
  else
    line3+=("${_mcol}${_ecol}:${_mb} ${_mpct}%${_mrst:+ $_mrst}${RST}")
  fi
done

# ── 出力: 空行は挟まず、単一 printf で書く（v1 と同じ作法）────────────────
# **要素間は 2 スペース**（v1 の作法）。`"${arr[*]}"` は IFS の 1 文字しか使えないので明示 join。
join2() {  # join2 OUT 要素...
  local _o="" _e; local _v="$1"; shift
  for _e in "$@"; do _o="${_o:+$_o  }$_e"; done
  printf -v "$_v" '%s' "$_o"
}
join2 _l1 ${line1[@]+"${line1[@]}"}
join2 _l2 ${line2[@]+"${line2[@]}"}
join2 _l3 ${line3[@]+"${line3[@]}"}
out=""
[[ -n "$_l1" ]] && out="$_l1"
[[ -n "$_l2" ]] && out="${out:+$out$'\n'}$_l2"
[[ -n "$_l3" ]] && out="${out:+$out$'\n'}$_l3"
printf '%s\n' "$out"
exit 0
