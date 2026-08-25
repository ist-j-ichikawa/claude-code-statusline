#!/usr/bin/env bats
# statusline-command.sh テスト
# 実行: bats test.bats  ← bats 自身は bash 4+ で。理由と機序は README「Development」
#
# bats を bash 3.2 で起動すると日本語テスト名のエンコードが割れ、**失敗ではなく 0 件実行**になる。
# 流し読みでは「通った」に見えるので、無言で緑にせずここで落とす。
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  printf '%s\n' \
    "FATAL: bats を bash ${BASH_VERSION} で起動しています。日本語テスト名が 0 件実行になります。" \
    "bash 4+ を PATH に入れてから実行してください (スクリプト本体は /bin/bash のままで良い)。" >&2
  exit 1
fi

# --- セットアップ: ヘルパー関数のみを読み込む ---
setup() {
  export COLUMNS=120
  # 色定数と presentation ヘルパー(has_val/braille_bar/color_by_threshold/format_tokens/
  # rainbow/gradient/model_color/osc8/editor_url)は lib.sh から読む(本体と単一ソース化)
  source "$BATS_TEST_DIRNAME/lib.sh"
  export _NOW=$(date +%s)
  # extra-usage の背景 curl を止めてテストを決定的にする
  export CLAUDE_STATUSLINE_NO_NET=1
  # キャッシュはテストごとに隔離する。本物 (ユーザーの TMPDIR) を触ると bats 実行中に
  # ライブ statusline へ偽の値が出るため、専用ディレクトリへ逃がす。
  export CLAUDE_STATUSLINE_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  # **スクリプトが読む env seam は必ず落とす** — テストの一部は `env -i` で密閉していないので
  # (`_peer_pre` は HOME だけ、多くの起動は env 上書きすら無い) 環境変数がそのまま漏れる。
  # 危険度が高い順に:
  #   `CLAUDE_SETTINGS`  — install テストが**開発者の実 settings.json に `--yes` で書き込む**
  #   `CLAUDE_CONFIG_DIR` — 「sessions ディレクトリが無くても…」が**無条件に緑**になる
  #                        (実在ディレクトリを読み未展開 glob の経路に入らず、stderr の assert が何も pin しない)
  #   `CLAUDE_CODE_USE_*` — 「Bedrock では extra-usage を出さない」が**検出が壊れていても緑**になる
  # 偽の赤は自分で申告するが、偽の緑は沈黙するので後者が本番。リストは下のメタテストが強制する。
  # 行継続で分けない — メタテストは 1 行ごとに `unset` と変数名の同居を見るため
  #   `CLAUDE_SECURESTORAGE_CONFIG_DIR` — Keychain のサービス名 suffix とファイル fallback 先を
  #                        両方動かすので、漏れると credentials 経路のテストが**別 dir を読んで**緑になる
  unset CLAUDE_SETTINGS CLAUDE_CONFIG_DIR CLAUDE_SECURESTORAGE_CONFIG_DIR
  unset CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_MANTLE CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
}

# build_git の background cache 書き込み完了まで polling (最大 ~2秒)
# 4 テストで `sleep` 固定にすると合計数秒のオーバーヘッドになるため
_wait_for_cache() {
  local cache_dir=$1 i f
  # **前半は 0.01s 刻み** — 背景の書き込みは実測 4.4ms で着くのに、一律 0.1s だと 1 回目の確認で
  # 間に合わず 0.1s まるごと眠る (待ちの 96% が無駄な sleep)。呼び出しは 15 箇所あり、
  # PostToolUse hook が編集ごとに全テストを回すので実測 2.1s / 回の差になる。
  # 合計タイムアウトは 2.0s → 2.2s でほぼ据え置き (遅いマシンで待ち足りなくならないように)。
  # `{1..N}` の brace 展開のまま — `$(seq)` にすると 1 呼び出しごとに fork が増える
  for i in {1..40}; do
    # atomic 書き込みの中間ファイル (.tmp-<pid>) は完成キャッシュではないので無視する
    for f in "$cache_dir"/*; do
      [[ -e "$f" && "$f" != *.tmp* ]] && return 0
    done
    if (( i <= 20 )); then sleep 0.01; else sleep 0.1; fi
  done
  return 1
}

# _wait_for_file PATH [-s] — 背景書き込みの完了を polling で待つ (固定 sleep を置かないため)。
# `-s` を付けると「存在する」ではなく「非空」まで待つ。
_wait_for_file() {
  local f=$1 mode=${2:-} i
  # 前半 0.01s 刻みの理由は `_wait_for_cache` の注記と同じ。合計は 3.0s → 3.2s で据え置き
  for i in {1..50}; do
    if [[ "$mode" == "-s" ]]; then [[ -s "$f" ]] && return 0
    else                           [[ -e "$f" ]] && return 0; fi
    if (( i <= 20 )); then sleep 0.01; else sleep 0.1; fi
  done
  return 1
}

# _strip — stdin から ANSI (SGR) を落とす。**このファイルで剥がし方を 1 つに保つ** —
# `perl -pe` と `sed` の 2 記法が混ざると「どちらを直せばいいか」が読めなくなる (実際に分裂した)。
_strip() { sed $'s/\033\\[[0-9;]*m//g'; }

# _wait_for_mtime FILE EPOCH — FILE の mtime が EPOCH より新しくなるまで待つ。
# 「内容は同じだが touch された」を見たいテスト用（`_wait_for_file` は存在/非空しか見られない）。
# **刻みは既存 2 ヘルパーと同じ 2 段ラダー**（前半 0.01s）。`{1..N}` のまま — `$(seq)` にすると
# 1 呼び出しごとに fork が増える。
_wait_for_mtime() {
  local f=$1 since=$2 i
  for i in {1..50}; do
    [[ -e "$f" ]] && (( $(stat -f %m "$f") > since )) && return 0
    if (( i <= 20 )); then sleep 0.01; else sleep 0.1; fi
  done
  return 1
}

# _repo_at DIR — commit 1 個の git repo を作る（各テストが init+config+commit を書き写さない）
_repo_at() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" -c user.email=t@t -c user.name=t commit --allow-empty -qm init
}

# _line3_of JSON — JSON を渡して **cold → キャッシュ待ち → warm** の Line 3（ANSI つき）を返す。
# この 4 行の手順が各テストに写されていたので 1 箇所に寄せた。色を見るテストがあるので**剥がさない**
# （必要なら呼び出し側で `| _strip`）。`/bin/bash …statusline-command.sh` のリテラルはここに残す
# — bash 3.2 メタテストが起動形を走査する対象なので、ヘルパー内でも同じ形で書く。
_line3_of() {
  local j=$1
  rm -f "$CLAUDE_STATUSLINE_CACHE_DIR/git"/* 2>/dev/null
  printf '%s' "$j" | /bin/bash statusline-command.sh >/dev/null 2>&1
  _wait_for_cache "$CLAUDE_STATUSLINE_CACHE_DIR/git"
  printf '%s' "$j" | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p'
}

# _wait_for_change FILE GLOB — FILE の内容が GLOB に一致しなくなるまで待つ。
# 「新鮮だが形式が違うファイルが、取り直しで置き換わる」ことを見たいテスト用
# （mtime は既に新しいので `_wait_for_mtime` では見られない）。刻みは他の待ちヘルパーと同じ。
_wait_for_change() {
  local f=$1 pat=$2 i
  for i in {1..50}; do
    [[ -r "$f" ]] && [[ "$(< "$f")" != $pat ]] && return 0
    if (( i <= 20 )); then sleep 0.01; else sleep 0.1; fi
  done
  return 1
}

# _stub_env DIRNAME [CURL_BODY] — 密閉した HOME + PATH を組み、`env -i` に渡す前置きを _stub_pre に入れる。
# statusline が fork するコマンドだけを PATH に置くので、`security` は**入らない** =
# Keychain 経路を外してファイル fallback を必ず通る。CURL_BODY を渡すと偽 curl を置く。
# 複数テストで同じ足場を組んでいたのを 1 箇所に寄せた (symlink 一覧の drift が一番危ない)。
_stub_env() {
  local name=$1 curl_body=${2:-} x
  _stub_bin="$BATS_TEST_TMPDIR/$name-bin"
  _stub_home="$BATS_TEST_TMPDIR/$name-home"
  _stub_cache="$BATS_TEST_TMPDIR/$name-cache"
  mkdir -p "$_stub_bin" "$_stub_home/.claude"
  for x in jq git md5 stat date grep mkdir touch mv rm sleep seq; do
    ln -s "$(command -v $x)" "$_stub_bin/" 2>/dev/null || true
  done
  [[ -n "$curl_body" ]] && { printf '#!/bin/bash\n%s\n' "$curl_body" > "$_stub_bin/curl"; chmod +x "$_stub_bin/curl"; }
  printf '%s' '{"claudeAiOauth":{"accessToken":"AAAAtest","subscriptionType":"max"}}' \
    > "$_stub_home/.claude/.credentials.json"
  _stub_pre=(env -i "HOME=$_stub_home" "PATH=$_stub_bin" "TMPDIR=$BATS_TEST_TMPDIR"
             "CLAUDE_STATUSLINE_CACHE_DIR=$_stub_cache")
}

# _count_cmd DIR NAME LOG — NAME の**起動回数**を数える偽コマンドを DIR に置く（実体へ exec する
# ので挙動は変わらない）。ログは 1 起動 1 行 `called <args>` なので `grep -c .` で回数、
# `grep -c -- '<arg>'` で引数も見られる。fork / メモ化の回帰は表示では見えないのでこれで見る。
# **ログのパスは埋め込む** — 環境変数で渡すと呼び出し側が `env` に並べ忘れて `>> ""` になる。
# **先に `rm -f` する** — `_stub_env` の偽 PATH は実体への symlink なので、上書きしようとすると
# 実体（`/usr/bin/stat` 等）へ書きに行って "Operation not permitted" で失敗する。
# **exec 先は BSD 版に固定する** — `command -v` だけだと homebrew coreutils の gnubin が PATH に
# ある機体で GNU 版に化け、`stat -f` / `date -j` が失敗して「原因の読めない赤」になる。
_count_cmd() {
  local dir=$1 name=$2 log=$3 real
  # **絶対パスを強制する** — 相対や変数名を渡すと、偽コマンドが**リポ直下にログを作る**
  # （実際に `FAKE_GIT_LOG` 等 3 個を作った。ここは本番のスクリプトが置かれている場所）
  [[ "$log" == /* ]] || { echo "_count_cmd: ログは絶対パスで渡す（受け取った値: $log）" >&3; return 1; }
  real=$(PATH=/usr/bin:/bin command -v "$name") || real=$(command -v "$name")
  mkdir -p "$dir"; rm -f "$dir/$name"
  printf '%s\n' '#!/bin/bash' "echo \"called \$*\" >> $(printf %q "$log")" "exec $real \"\$@\"" > "$dir/$name"
  chmod +x "$dir/$name"
}

# ============================================================================
# has_val — 値の有無を判定すること
# ============================================================================
@test "has_val: 通常の文字列を有効と判定すること" {
  has_val "hello"
}

@test "has_val: 空文字列を無効と判定すること" {
  ! has_val ""
}

@test "has_val: 文字列nullを無効と判定すること" {
  ! has_val "null"
}

@test "has_val: 文字列0を有効と判定すること" {
  has_val "0"
}

# ============================================================================
# osc8 — OSC 8 ハイパーリンクを組むこと
# ============================================================================
@test "osc8: URL とテキストを OSC 8 シーケンスで包むこと" {
  local out
  osc8 "https://example.com/tree/main" "main" out
  [ "$out" = $'\033]8;;https://example.com/tree/main\amain\033]8;;\a' ]
}

@test "osc8: URL の ; # ? を percent-encode し、表示テキストは素のまま出すこと" {
  # どれも git のブランチ名には入りうるが、URI では区切り文字として解釈される
  local out
  osc8 "https://example.com/tree/a;b#c?d" "a;b#c?d" out
  [ "$out" = $'\033]8;;https://example.com/tree/a%3Bb%23c%3Fd\aa;b#c?d\033]8;;\a' ]
}

@test "osc8: % を先に encode して別ブランチへのリンクに畳まれないこと" {
  # `%` を後回しにすると `a%3Bb` が `a;b` と同じ出力になり、別ブランチを指す
  local semi pct
  osc8 "https://example.com/tree/a;b" "x" semi
  osc8 "https://example.com/tree/a%3Bb" "x" pct
  [ "$semi" != "$pct" ]
  [[ "$pct" == *"tree/a%253Bb"* ]]
}

# ============================================================================
# braille_bar — パーセンテージを点字バーに変換すること
# ============================================================================
@test "braille_bar: 0%で空バーを返すこと" {
  braille_bar 0 result
  [[ "$result" == "     " ]]
}

@test "braille_bar: 100%で全て埋まったバーを返すこと" {
  braille_bar 100 result
  [[ "$result" == "⣿⣿⣿⣿⣿" ]]
}

@test "braille_bar: 50%で半分埋まったバーを返すこと" {
  braille_bar 50 result
  [[ "$result" == "⣿⣿⣤  " ]]
}

@test "braille_bar: 100%超でも全埋めで打ち止めになること" {
  braille_bar 120 result
  [[ "$result" == "⣿⣿⣿⣿⣿" ]]
}

@test "braille_bar: 5文字幅であること" {
  braille_bar 30 result
  [[ ${#result} -eq 5 ]]
}

# ============================================================================
# color_by_threshold — 閾値に応じた色を返すこと
# ============================================================================
@test "color_by_threshold: 上限以上で赤を返すこと" {
  color_by_threshold 95 90 80 result
  [[ "$result" == "$RED" ]]
}

@test "color_by_threshold: 中間で黄を返すこと" {
  color_by_threshold 85 90 80 result
  [[ "$result" == "$YLW" ]]
}

@test "color_by_threshold: 下限以下でlime green(CTX_OK)を返すこと" {
  color_by_threshold 50 90 80 result
  [[ "$result" == "$CTX_OK" ]]
}

@test "color_by_threshold: 上限ちょうどで赤を返すこと" {
  color_by_threshold 90 90 80 result
  [[ "$result" == "$RED" ]]
}

@test "color_by_threshold: 中間ちょうどで黄を返すこと" {
  color_by_threshold 80 90 80 result
  [[ "$result" == "$YLW" ]]
}

# ============================================================================
# format_tokens — トークン数を人間が読みやすい形式に変換すること
# ============================================================================
@test "format_tokens: 100万以上でM表記になること" {
  format_tokens 1500000 result
  [[ "$result" == "1.5M" ]]
}

@test "format_tokens: 1000以上でk表記になること" {
  format_tokens 45000 result
  [[ "$result" == "45.0k" ]]
}

@test "format_tokens: 1000未満でそのまま表示されること" {
  format_tokens 999 result
  [[ "$result" == "999" ]]
}

@test "format_tokens: ちょうど1000でk表記になること" {
  format_tokens 1000 result
  [[ "$result" == "1.0k" ]]
}

# ============================================================================
# 統合テスト: モデル色 — 公式ブランドカラーで表示されること
# ============================================================================
@test "モデル色: Opusがコーラルで表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"38;5;173"*"Opus 4.6"* ]]
}

@test "モデル色: Opus 5がcoral一族の暗→明スイープで表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-5[1m]","display_name":"Opus 5"},"version":"2.1.220","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  # dark rust 130 起点 → 途中に Opus の CORAL 173 → 末尾 gold 215
  # (130 は flat coral 分岐では絶対に出ないので flat への退行を検出できる)
  [[ "$result" == *"38;5;130mO"* ]]
  [[ "$result" == *"38;5;173m"* ]]
  [[ "$result" == *"38;5;215m5"* ]]
}

@test "モデル色: 実display_nameの(1M context)を名前から剥がし、スイープが端から端まで載ること" {
  result=$(echo '{"model":{"id":"claude-opus-5[1m]","display_name":"Opus 5 (1M context)"},"version":"2.1.220","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48,"context_window_size":1000000}}' \
    | /bin/bash statusline-command.sh 2>/dev/null)
  local l1; l1=$(printf '%s' "$result" | head -1)
  # コンテキスト量は Line 4 の分母に回すので、名前からは括弧を剥がす
  [[ "$l1" != *"1M context"* ]]
  [[ "$(printf '%s' "$l1" | _strip)" == *"Opus 5"* ]]
  # 先頭文字=パレット先頭 (130)、末尾文字=パレット末尾 (215)
  [[ "$l1" == *"38;5;130mO"* ]]
  [[ "$l1" == *"38;5;215m5"* ]]
  # 分母は Line 4 の % の直後に出る
  [[ "$(printf '%s' "$result" | tail -1 | _strip)" == *"48%/1M"* ]]
}

@test "モデル色: display_nameに版が無くてもmodel_idで Opus 5 と判定されること" {
  result=$(echo '{"model":{"id":"claude-opus-5[1m]","display_name":"Opus (1M context)"},"version":"2.1.220","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  # display_name だけ見ると flat coral に落ちる形。id 側の "opus-5" で拾い subagent 行と色を揃える
  [[ "$result" == *"38;5;130mO"* ]]
}

@test "モデル色: display_name空(Bedrock)でもmodel_id全体がスイープされること" {
  result=$(echo '{"model":{"id":"global.anthropic.claude-opus-5-v1:0","display_name":""},"version":"2.1.220","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"38;5;130mg"* ]]
  [[ "$result" == *"38;5;215m0"* ]]
}

@test "モデル色: Opus 5判定が Opus 4.5 に誤マッチしないこと" {
  result=$(echo '{"model":{"id":"claude-opus-4-5","display_name":"Opus 4.5"},"version":"2.1.220","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  # coral フラットのままで、スイープ(起点 130)にならないこと
  [[ "$result" == *"38;5;173"*"Opus 4.5"* ]]
  [[ "$result" != *"38;5;130m"* ]]
}

@test "モデル色: model_showとmodel_idを跨いだ偽マッチが起きないこと" {
  # _key の区切りが空白だと "Opus" + "5-…" が連結で "opus 5" に化けてスイープしてしまう
  model_color c "Opus" "5-something"
  [[ "$c" == *"38;5;173mOpus"* ]]   # flat coral のまま
  [[ "$c" != *"38;5;130m"* ]]
}

@test "モデル色: パレット未指定のrainbow/gradientが無色テキストに degrade すること" {
  rainbow a "XY"; [[ "$a" == "XY" ]]
  gradient b "XY"; [[ "$b" == "XY" ]]
}

@test "モデル色: Sonnet 4.6がティールで表示されること" {
  result=$(echo '{"model":{"id":"claude-sonnet-4-6","display_name":"Sonnet 4.6"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"38;5;79"*"Sonnet 4.6"* ]]
}

@test "モデル色: Sonnet 4.5がアンバーで表示されること" {
  result=$(echo '{"model":{"id":"claude-sonnet-4-5","display_name":"Sonnet 4.5"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"38;5;214"*"Sonnet 4.5"* ]]
}

@test "モデル色: Sonnet 5が緑グラデーション(文字ごとに色が変わる)で表示されること" {
  result=$(echo '{"model":{"id":"claude-sonnet-5","display_name":"Sonnet 5"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  # 緑パレットを1回スイープ: 先頭 28(濃緑) → 末尾 154(黄緑)
  [[ "$result" == *"38;5;28mS"* ]]
  [[ "$result" == *"38;5;154m5"* ]]
}

@test "モデル色: Sonnet 5判定が Sonnet 4.5 に誤マッチしないこと" {
  result=$(echo '{"model":{"id":"claude-sonnet-4-5","display_name":"Sonnet 4.5"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  # amber フラットのままで、グラデーション(28)にならないこと
  [[ "$result" == *"38;5;214"*"Sonnet 4.5"* ]]
  [[ "$result" != *"38;5;28m"* ]]
}

@test "モデル色: Haikuがラベンダーで表示されること" {
  result=$(echo '{"model":{"id":"claude-haiku-4-5","display_name":"Haiku 4.5"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"38;5;183"*"Haiku 4.5"* ]]
}

@test "モデル色: Fableが蝶標本パレット(文字ごとに色が変わる)で表示されること" {
  result=$(echo '{"model":{"id":"claude-fable-5","display_name":"Fable 5"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  # 各文字が蝶標本パレットで着色される: F=178, a=172, b=130 ...
  [[ "$result" == *"38;5;178mF"*"38;5;172ma"*"38;5;130mb"* ]]
}

@test "モデル色: 大文字混在のdisplay_nameでも正しい色になること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"OPUS 4.6"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"38;5;173"*"OPUS 4.6"* ]]
}

@test "モデル色: nocasematchがスクリプト外に漏れないこと" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null; shopt -q nocasematch && echo "LEAKED" || echo "OK")
  [[ "$result" == *"OK" ]]
}

# ============================================================================
# 統合テスト: プロバイダー検出 — 正しいプロバイダーが表示されること
# ============================================================================
@test "プロバイダー: model_idのglobal.プレフィックスでBedrockと検出すること" {
  result=$(echo '{"model":{"id":"global.anthropic.claude-opus-4-6-v1","display_name":""},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"Bedrock"* ]]
}

@test "プロバイダー: model_idのus-gov.プレフィックス(GovCloud)でBedrockと検出すること" {
  result=$(echo '{"model":{"id":"us-gov.anthropic.claude-opus-4-6-v1","display_name":""},"version":"2.1.174","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"Bedrock"* ]]
}

@test "プロバイダー: CLAUDE_CODE_USE_MANTLE環境変数でBedrockと検出すること" {
  result=$(CLAUDE_CODE_USE_MANTLE=1 /bin/bash -c 'echo "{\"model\":{\"id\":\"claude-opus\",\"display_name\":\"Opus 4.6\"},\"version\":\"2.1.94\",\"workspace\":{\"current_dir\":\"/tmp\"},\"context_window\":{\"used_percentage\":48}}" | /bin/bash statusline-command.sh 2>/dev/null | head -1')
  [[ "$result" == *"Bedrock"* ]]
}

@test "プロバイダー: CLAUDE_CODE_USE_VERTEX環境変数でVertexと検出すること" {
  result=$(CLAUDE_CODE_USE_VERTEX=1 /bin/bash -c 'echo "{\"model\":{\"id\":\"claude-opus\",\"display_name\":\"Opus 4.6\"},\"version\":\"2.1.76\",\"workspace\":{\"current_dir\":\"/tmp\"},\"context_window\":{\"used_percentage\":48}}" | /bin/bash statusline-command.sh 2>/dev/null | head -1')
  [[ "$result" == *"Vertex"* ]]
}

# ============================================================================
# 統合テスト: Effort & Thinking — 推論努力と拡張思考が正しく表示されること
# ============================================================================
@test "Effort: レベルごとに色が変わること(Claude Code の /effort ピッカー準拠)" {
  # 旧「light purple で出ること」テストはこのランプ側に統合した (high の arm は下で pin される)。
  # ラベル (`effort:`) を付けないことも同時に見る
  # 単色だった頃は `high` と `max` を色で区別できなかった。
  # low=gold → medium=green → high=薄紫 → xhigh=濃紫 → max=多色 のランプ。
  # 色は**生のリテラル**で assert する — 定数で書くとどんな値でも通り、無断の再調整を検出できない。
  _eff() { echo '{"model":{"id":"claude-opus-4-7","display_name":"Opus 4.7"},"version":"2.1.128","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"effort":{"level":"'"$1"'"}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1; }
  [[ "$(_eff low)"    == *$'\033[38;5;178m'"low"*    ]]
  [[ "$(_eff medium)" == *$'\033[38;5;71m'"medium"*  ]]
  [[ "$(_eff high)"   == *$'\033[38;5;105m'"high"*   ]]
  [[ "$(_eff xhigh)"  == *$'\033[38;5;99m'"xhigh"*   ]]
  # max は多色 (1 文字ずつ ANSI が入るのでリテラル一致は効かない)。紫→桃→橙の 3 ストップ。
  m=$(_eff max)
  [[ "$m" == *$'\033[38;5;99m'"m"*   ]]
  [[ "$m" == *$'\033[38;5;170m'"a"*  ]]
  [[ "$m" == *$'\033[38;5;209m'"x"*  ]]
  # 未知のレベルは既定の薄紫に落ちる (上流がレベルを増やしても無色にならない)
  [[ "$(_eff someday)" == *$'\033[38;5;105m'"someday"* ]]
  # ラベルは付けない (値だけ)
  [[ "$(_eff high)" != *"effort:"* ]]
}

@test "Thinking: thinking.enabled=trueでlight cyan(38;5;117)のthinkが表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-7","display_name":"Opus 4.7"},"version":"2.1.128","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"thinking":{"enabled":true}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[38;5;117m'*"think"* ]]
}

@test "Effort/Thinking: 両方ありで半角スペース区切りで結合されること(中黒なし)" {
  result=$(echo '{"model":{"id":"claude-opus-4-7","display_name":"Opus 4.7"},"version":"2.1.128","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"effort":{"level":"high"},"thinking":{"enabled":true}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"high"*"think"* ]]
  [[ "$result" != *"·"*"think"* ]]
  [[ "$result" != *"effort:"* ]]
}

@test "Effort/Thinking: 旧 Claude Code(両キーなし)でeffort/thinkが表示されないこと" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.118","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" != *"effort:"* ]]
  [[ "$result" != *"think"* ]]
}

@test "Thinking: thinking.enabled=falseでthinkが表示されないこと" {
  result=$(echo '{"model":{"id":"claude-opus-4-7","display_name":"Opus 4.7"},"version":"2.1.128","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"thinking":{"enabled":false}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" != *"think"* ]]
}

@test "FastMode: fast_mode=trueでgreenyellow(38;5;190)のfastが表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-8","display_name":"Opus 4.8"},"version":"2.1.216","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"fast_mode":true}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[38;5;190m'*"fast"* ]]
}

@test "FastMode: fast_mode=falseでfastが表示されないこと" {
  result=$(echo '{"model":{"id":"claude-opus-4-8","display_name":"Opus 4.8"},"version":"2.1.216","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"fast_mode":false}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" != *"fast"* ]]
}

@test "FastMode: fast_modeキー欠落(旧 Claude Code)でfastが表示されないこと" {
  result=$(echo '{"model":{"id":"claude-opus-4-8","display_name":"Opus 4.8"},"version":"2.1.128","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" != *"fast"* ]]
}

@test "FastMode: effort/think/fastが半角スペース区切りで併記されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-8","display_name":"Opus 4.8"},"version":"2.1.216","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"effort":{"level":"high"},"thinking":{"enabled":true},"fast_mode":true}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"high"*"think"*"fast"* ]]
}

# ============================================================================
# 統合テスト: Line 3 — コンテキスト + プロバイダー別表示が正しいこと
# ============================================================================
@test "Line4: トークン数が表示されないこと" {
  result=$(echo '{"model":{"id":"global.anthropic.claude-opus-4-6-v1","display_name":"Opus 4.6"},"version":"2.1.77","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48,"total_input_tokens":125000,"total_output_tokens":8500}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" != *"↑"* ]]
  [[ "$result" != *"↓"* ]]
  [[ "$result" != *"125"* ]]
}

@test "Line4: cost.total_cost_usdがdimの\$表示で出ること" {
  result=$(echo '{"model":{"id":"claude-fable-5","display_name":"Fable 5"},"version":"2.1.173","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"cost":{"total_cost_usd":4.83}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" == *'$4.83'* ]]
}

@test "Line4: コストがセント単位に四捨五入されること" {
  result=$(echo '{"model":{"id":"claude-fable-5","display_name":"Fable 5"},"version":"2.1.173","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"cost":{"total_cost_usd":0.426}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" == *'$0.43'* ]]
}

@test "Line4: コストが0のとき表示されないこと" {
  result=$(echo '{"model":{"id":"claude-fable-5","display_name":"Fable 5"},"version":"2.1.173","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"cost":{"total_cost_usd":0}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" != *'$'* ]]
}

@test "Line4: costフィールドがない旧Claude Codeで\$が表示されないこと" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" != *'$'* ]]
}

@test "Line5: usage-credits キャッシュがあると credits:\$X.XX が表示されること" {
  mkdir -p $CLAUDE_STATUSLINE_CACHE_DIR
  printf 'cents,limits\037214\n' > $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '5p')
  rm -f $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  [[ "$result" == *'credits:$2.14'* ]]
  # **色と太字も生のリテラルで pin する** — この行で唯一「実際に請求される額」なので、
  # SPEND (明るい gold) を COST (ブロンズ) に取り違えたり `BOLD` を落とした mutant は
  # ラベルの assert だけでは緑になる（実際にこの diff がこの行を書き換えたのに pin が無かった）。
  # 定数 (`$SPEND`) で書くとどんな値でも通り、無断の再調整を検出できない。
  [[ "$result" == *$'\033[1m'$'\033[38;5;220m'"credits:\$2.14"* ]]
}

@test "週間枠: limits[] 由来のモデル別枠が名前つきで出ること" {
  # stdin の rate_limits は five_hour/seven_day だけなので、モデル別の週間制限は
  # `/usage` の limits[] から来る (同じ curl の結果なので追加ネットワークゼロ)。
  mkdir -p $CLAUDE_STATUSLINE_CACHE_DIR
  # 1 行目 = cents、2 行目以降 = 名前 US % US epoch
  printf 'cents,limits\0370\nFable\03739\037Sat 16:00' > $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '5p')
  rm -f $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  # **多色モデルは名前のリテラル一致が効かない** (1 文字ずつ ANSI が入る) ので ANSI を剥がす
  local plain
  plain=$(printf '%s' "$result" | _strip)
  [[ "$plain" == *"Fable:39%"* ]]
  # 色は Line 1 と同じ model_color。**生のリテラルで assert** する — 定数で書くと
  # どんな値でも通り、無断の再調整を検出できない (FABLE_PAL の先頭 = 178)
  [[ "$result" == *'38;5;178m'* ]]
}

@test "週間枠: 0% のモデル別枠を出さないこと(アカウント全体の week: と揃える)" {
  # `week:` が 0 を落とすのにモデル別枠は 0 を通していた = 同じ行で非対称
  # (理由は statusline-command.sh の `render_scoped_limits` の 0% ガードのコメント)。
  # **非 0 の枠が同時に生き残ること**も見る — `continue` を `break` に書き換えた mutant は
  # 「0 を出さない」だけなら緑になる（以降の枠が全部消える）。
  # **2 つの枠のリセット時刻は別の値にする** — 同じ文字列だと、落とした枠のリセット時刻だけが
  # residue として残る壊れ方を検出できない（「リセット時刻も連れてこない」が pin されない）。
  local plain
  mkdir -p $CLAUDE_STATUSLINE_CACHE_DIR
  printf 'cents,limits\0370\nSonnet 5\0370\037Mon 09:00\nFable\03739\037Sat 16:00' > $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  plain=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.245","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '5p' | _strip)
  rm -f $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  # 0% の枠は名前ごと出さない。リセット時刻も連れてこない
  [[ "$plain" != *"Sonnet 5"* ]]
  [[ "$plain" != *"Mon 09:00"* ]]
  # 非 0 の枠は生きる = 0 の行だけ落ちている
  [[ "$plain" == *"Fable:39%"* ]]
  [[ "$plain" == *"Sat 16:00"* ]]
}

@test "Line5: 週間枠は 0% を落とすが 5h は 0% でも出すこと(意図的な非対称)" {
  # 上の 0% ガードのコメントは `week:` 側の `((seven_pct > 0))` を根拠に挙げているのに、
  # **`week:` 側には 0% の fixture が 1 つも無かった** — `> 0` を外してもスイートは緑のまま、
  # コメントだけが嘘になる（2026-08-25 の /simplify 指摘）。ここで実行可能にする。
  # **5h は 0% でも出す** — 行の左端の一目確認用なので `has_val` だけで gate している。
  # 「制限は 0% なら隠す」ではなく「**週間の枠だけ** 0% なら隠す」が実際の規則。
  local l5
  l5=$(printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"version":"2.1.245","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":0,"resets_at":4070908800},"seven_day":{"used_percentage":0,"resets_at":4070995200}}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '5p' | _strip)
  [[ "$l5" != *"week:"* ]]
  # **`0%` の部分一致だけでは弱い** — バー (`⣿⣶`) やリセット時刻を落とす mutant が緑になる。
  # `0% <時刻>` の並びで取る。**期待値は `date -j -r` でローカルに直す**（TZ 依存にしない）
  local exp
  exp=$(date -j -r 4070908800 +%H:%M)
  [[ "$l5" == *"0% $exp"* ]]
  # **バーは 0% でも幅ぶんの空白として出る**（実測: `······0%·09:00`）ので、行頭が `0%` に
  # なったらバーが落ちている。幅を数値で書かずに「何かが前に付いていること」で見る。
  # 隣のテストの「空バー + 裸の `%`」とはここで区別される — あちらは `%` の前に数字が無い
  [[ "$l5" != "0%"* ]]
}

@test "週間枠: /usage のレスポンスから枠を抽出できること(偽 curl で本番経路を通す)" {
  # 他の枠テストは**キャッシュを直接置く**ので抽出 jq が一度も実行されず、壊しても全緑だった
  # (v1.74.0 のレビューで発見)。ここだけ偽 curl で背景 fetch の経路を通し、jq 側を pin する。
  # `06:59:59.987654` は**分丸めの pin** — 切り捨てだと 06:59 になり、実測でこの揺れが起きる
  # (同じリセットが 06:59:59.987654 と 07:00:00.155204 の両方で返る)。
  # `38.6` は `| round` の pin。weekly 以外の枠・% が数値でない枠が落ちることも同時に見る。
  local fixture="$BATS_TEST_TMPDIR/usage.json"
  printf '%s' '{"spend":{"used":{"amount_minor":214,"exponent":2}},"limits":[
    {"kind":"weekly_scoped","group":"weekly","percent":38.6,"resets_at":"2026-08-15T06:59:59.987654+00:00","scope":{"model":{"display_name":"Fable"}},"is_active":true},
    {"kind":"weekly_scoped","group":"weekly","percent":"bad","resets_at":"2026-08-15T07:00:00.000000+00:00","scope":{"model":{"display_name":"Broken"}}},
    {"kind":"five_hour","group":"five_hour","percent":10,"resets_at":"2026-08-15T07:00:00.000000+00:00","scope":{"model":{"display_name":"Hourly"}}}]}' \
    > "$fixture"
  # 偽 curl は `cat` を使えない (PATH に置いていない) ので bash 組み込みだけで返す
  _stub_env limits "$(printf 'printf "%%s" "$(< %s)"' "$fixture")"
  echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"}}' \
    | "${_stub_pre[@]}" /bin/bash statusline-command.sh >/dev/null 2>&1
  _wait_for_file "$_stub_cache/usage_spend" -s \
    || { echo "背景 fetch がキャッシュに届いていない = テストが無意味" >&3; return 1; }
  local cache exp
  cache=$(< "$_stub_cache/usage_spend")
  # 期待するリセット表示は TZ 依存なので、07:00Z を this machine のローカルに直して比べる
  exp=$(date -j -f '%Y-%m-%dT%H:%M:%S %z' '2026-08-15T07:00:00 +0000' +'%a %H:%M')
  [[ "$(printf '%s' "$cache" | sed -n '1p')" == "cents,limits"$'\037'"214" ]]   # 1 行目 = タグ US cents
  [[ "$cache" == *"Fable"$'\037'"39"$'\037'"$exp"* ]]           # 名前 US 丸めた% US 分丸めしたリセット
  [[ "$cache" != *"Broken"* ]]                                  # 型不正の枠は落ちる
  [[ "$cache" != *"Hourly"* ]]                                  # weekly 以外は入らない
  # キャッシュが新鮮になったので、次の描画は refetch せずこの値を出す
  local plain
  plain=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"}}' \
    | "${_stub_pre[@]}" /bin/bash statusline-command.sh 2>/dev/null \
    | sed -n '5p' | _strip)
  [[ "$plain" == *"Fable:39% $exp"* ]]
  [[ "$plain" == *'credits:$2.14'* ]]
}

@test "週間枠: 取得失敗で既存のキャッシュを消さないこと(延命する)" {
  # Wi-Fi 断や `curl -m 4` のタイムアウトで空応答になったとき、上書きすると
  # **ディスクに良い値があるのに credits:$ と全枠が 300s 消える** (code-review 指摘)。
  # `fetch_subscription` と同じく touch で延命し、storm も防いだまま表示を保つ。
  _stub_env usagefail 'exit 1'          # curl は失敗する
  mkdir -p "$_stub_cache"
  printf 'cents,limits\037214\nFable\03739\037Sat 16:00' > "$_stub_cache/usage_spend"
  # cache_stale を必ず踏ませる (300s より古くする)
  touch -t 202001010000 "$_stub_cache/usage_spend"
  # 描画は背景 fetch を起こすためだけに 1 回走らせる (出力は見ない)
  echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | "${_stub_pre[@]}" /bin/bash statusline-command.sh >/dev/null 2>&1
  # 背景の fetch が終わるのを待つ (mtime が新しくなる = touch された)
  _wait_for_mtime "$_stub_cache/usage_spend" 1600000000 \
    || { echo "背景 fetch が届いていない = テストが無意味" >&3; return 1; }
  local rec
  rec=$(< "$_stub_cache/usage_spend")
  [[ "$rec" == "cents,limits"$'\037'"214"$'\n'"Fable"$'\037'"39"$'\037'"Sat 16:00" ]]   # 内容は消えていない (touch だけ)
}

@test "週間枠: エラー応答で既存のキャッシュを消さないこと" {
  # `curl -s` は `-f` を付けていないので **401/429/5xx の JSON 本文も stdout に来る**。
  # 「応答が空か」で延命を判定していた頃は、`// 0` の既定値のせいで cents=0 と枠 0 件で
  # 良いキャッシュを上書きし、`credits:$` と全枠が 300s 消えた（`/code-review` 指摘）。
  # 判定は **`.spend.used.amount_minor` の有無**（パース結果）で行う。
  _stub_env usageerr 'printf "%s" "{\"error\":{\"type\":\"rate_limit_error\",\"message\":\"slow down\"}}"'
  mkdir -p "$_stub_cache"
  printf 'cents,limits\037214\nFable\03739\037Sat 16:00' > "$_stub_cache/usage_spend"
  touch -t 202001010000 "$_stub_cache/usage_spend"          # TTL を必ず踏ませる
  echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | "${_stub_pre[@]}" /bin/bash statusline-command.sh >/dev/null 2>&1
  _wait_for_mtime "$_stub_cache/usage_spend" 1600000000 \
    || { echo "背景 fetch が届いていない = テストが無意味" >&3; return 1; }
  local rec; rec=$(< "$_stub_cache/usage_spend")
  [[ "$rec" == "cents,limits"$'\037'"214"$'\n'"Fable"$'\037'"39"$'\037'"Sat 16:00" ]]
}

@test "週間枠: タグの無いキャッシュ(旧形式)を使わないこと" {
  # 形式タグはレコードの先頭にあるので、v1.73.0 が書いた `214` だけのファイルは
  # **cents として読まれない**（`214` がタグ位置に来るので不一致）。誤った金額を出すより出さない。
  mkdir -p $CLAUDE_STATUSLINE_CACHE_DIR
  local j='{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}'
  printf '214\n' > $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend   # 旧形式（タグ無し）
  result=$(printf '%s' "$j" | /bin/bash statusline-command.sh 2>/dev/null | sed -n '5p')
  [[ "$result" != *'credits:$2.14'* ]]
  [[ "$result" != *':39%'* ]]
  # **タグだけ違って中身は現行と同じ形**のケースも使わない（値の捨て忘れを pin する）
  printf 'OLD_FMT\037214\nFable\03739\037Sat 16:00' > $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  result=$(printf '%s' "$j" | /bin/bash statusline-command.sh 2>/dev/null | sed -n '5p')
  rm -f $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  [[ "$result" != *'credits:$2.14'* ]]
  [[ "$result" != *':39%'* ]]
}

@test "週間枠: タグ不一致なら TTL を待たずに取り直すこと(アップグレード経路)" {
  # **テストは常に空のキャッシュから始まるので、アップグレード経路を一度も通らない** —
  # v1.74.0 は形式を変えたのにファイル名を据え置き、**既存ユーザー全員が旧形式を新コードで読む**
  # 状態を出荷した（利用者からの報告で判明）。タグ方式では「不一致 = 古い」と同じ扱いにするので、
  # TTL（300s）を待たずにその場で取り直す。ここを pin すると、次に形式を変えたときの
  # 「タグを直し忘れた」ではなく「不一致を stale 扱いにし忘れた」を捕まえられる。
  _stub_env usagefmt 'printf "%s" "{\"spend\":{\"used\":{\"amount_minor\":777,\"exponent\":2}}}"'
  mkdir -p "$_stub_cache"
  # 新鮮（TTL 内）だがタグが違うファイルを置く。TTL だけを見る実装なら取り直しは起きない
  printf 'OLD_FMT\037214\n' > "$_stub_cache/usage_spend"
  echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | "${_stub_pre[@]}" /bin/bash statusline-command.sh >/dev/null 2>&1
  # **mtime では見られない** — 置いたファイルは既に新鮮なので、内容が変わるのを待つ
  _wait_for_change "$_stub_cache/usage_spend" 'OLD_FMT*' \
    || { echo "取り直しが走っていない = タグ不一致が stale 扱いになっていない" >&3; return 1; }
  local rec; rec=$(< "$_stub_cache/usage_spend")
  [[ "$rec" == "cents,limits"$'\037'"777"* ]]   # 現行タグで上書きされている
}

@test "週間枠: 壊れた枠の行を落として他の枠とcentsが生き残ること" {
  # 1 枠の形式不正で全体が消えないこと。cents は 1 行目にあるので枠の破損に巻き込まれない。
  mkdir -p $CLAUDE_STATUSLINE_CACHE_DIR
  # 2 行目 = % が数値でない(落ちる) / 3 行目 = 正常 / 4 行目 = 名前が空(落ちる)
  printf 'cents,limits\037214\nBroken\037abc\037Sat 16:00\nFable\03739\037Sat 16:00\n\03712\037Sat 16:00' \
    > $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '5p')
  rm -f $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  local plain
  plain=$(printf '%s' "$result" | _strip)
  [[ "$plain" == *"Fable:39%"* ]]      # 正常な枠は出る
  [[ "$plain" != *"Broken"* ]]         # 壊れた枠は落ちる
  [[ "$result" == *'credits:$2.14'* ]]   # cents は生きる
}

@test "週間枠: 枠のリセットと経過が別行になること" {
  # 枠は dim のリセット時刻で終わるので、経過 (dim の `2h`) と同じ行に並ぶと
  # 「枠の続き」に見えて属し先が消える。**行分割で構造的に起きなくなった**ことを pin する
  # (v1.74.0。以前は同一行で、間に何が挟まるかに依存していた)。
  mkdir -p $CLAUDE_STATUSLINE_CACHE_DIR
  printf 'cents,limits\0370\nFable\03739\037Sat 16:00' > $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  out=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"cost":{"total_duration_ms":7200000}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | _strip)
  rm -f $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  sess=$(printf '%s' "$out" | sed -n '4p')
  lim=$(printf '%s' "$out" | sed -n '5p')
  # 経過はセッション行、枠とそのリセットは制限行 — 同じ行に並ばない
  [[ "$sess" == *"2h"* ]]
  [[ "$lim" == *"Fable"* ]]
  [[ "$lim" == *"Sat 16:00"* ]]
  [[ "$lim" != *"2h"* ]]
  [[ "$sess" != *"Sat 16:00"* ]]
}

@test "週間枠: Bedrockではモデル別枠を出さないこと" {
  mkdir -p $CLAUDE_STATUSLINE_CACHE_DIR
  printf 'cents,limits\0370\nFable\03739\037Sat 16:00' > $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  result=$(echo '{"model":{"id":"global.anthropic.claude-opus-4-6-v1:0","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '5p')
  rm -f $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  local plain
  plain=$(printf '%s' "$result" | _strip)
  [[ "$plain" != *":39%"* ]]
}

@test "Line5: usage-credits データがないとき credits: が表示されないこと" {
  # setup() で usage_spend は削除済み・NO_NET で fetch も走らない。
  # **制限行（5 行目）で見る** — Line 4 には credits が元々出ないので、4 行目を見る形は
  # どう壊しても緑になる（Bedrock 側で同じ穴を踏んだ。`/code-review` 指摘）
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '5p')
  [[ "$result" != *'credits:'* ]]
}

@test "Line5: Bedrockでは usage-credits を取得も表示もしないこと" {
  mkdir -p $CLAUDE_STATUSLINE_CACHE_DIR
  printf 'cents,limits\037500\n' > $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  result=$(echo '{"model":{"id":"global.anthropic.claude-opus-4-6-v1","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '5p')   # 制限行（Line 4/5 の分割で credits は 5 行目へ移った）
  rm -f $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  [[ "$result" != *'credits:'* ]]
}

@test "Line5: Anthropicでレートリミットが表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.80","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":4070908800},"seven_day":{"used_percentage":12,"resets_at":4071427200}}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '5p')
  [[ "$result" == *"35%"* ]]
  [[ "$result" == *"week:12%"* ]]
}

@test "Line4: rate_limitsがない旧CCでも4行出力されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.79","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null)
  line_count=$(echo "$result" | grep -c . || echo 0)
  [[ "$line_count" -eq 4 ]]
}

@test "Line5: 片方の窓だけ来ても残った窓だけを出し、行を崩さないこと(2.1.243 の窓消失)" {
  # 2.1.243 で `rate_limits.<窓>` は「API が報告していて `resets_at` を過ぎていない間だけ present」に
  # なった。つまり**片方だけ present** が過渡状態として日常的に起きる。既存テストは常に両窓か
  # `rate_limits` ごと欠落しか見ておらず、この形を pin しているものが 1 本も無かった
  # (2026-08-25、Fable レビューの指摘)。
  # **assert は行頭で取る** — gate を外した mutant は空バー + 裸の `%` を出すので、行が
  # `······%·week:12%` になる。`⣿` の有無では見えない (空バーは空白なので glyph が出ない)。
  # **変わらない部分は 1 回だけ書く** — 3 シナリオの違いは `rate_limits` だけなので、そこを
  # `printf` の差し込みにする（同じ 230 字を 3 回並べると、唯一の違いが行末に埋もれる）
  local fmt j out l5 outf
  fmt='{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"version":"2.1.243","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":%s}'

  printf -v j "$fmt" '{"seven_day":{"used_percentage":12,"resets_at":4070908800}}'
  out=$(printf '%s' "$j" | /bin/bash statusline-command.sh 2>/dev/null)
  [[ "$(printf '%s' "$out" | grep -c .)" -eq 5 ]]
  l5=$(printf '%s' "$out" | sed -n '5p' | _strip)
  # 消えた 5h の痕跡が行頭に残らないこと (空バーも裸の `%` も出ない)
  [[ "$l5" == "week:12%"* ]]

  # 逆向き: seven_day を落として five_hour だけ
  printf -v j "$fmt" '{"five_hour":{"used_percentage":35,"resets_at":4070908800}}'
  out=$(printf '%s' "$j" | /bin/bash statusline-command.sh 2>/dev/null)
  [[ "$(printf '%s' "$out" | grep -c .)" -eq 5 ]]
  l5=$(printf '%s' "$out" | sed -n '5p' | _strip)
  [[ "$l5" == *"35%"* ]]
  [[ "$l5" != *"week:"* ]]

  # **両方消えたら Line 5 ごと出さない** — 空の制限行を連結すると空行が挟まって行が崩れる
  # (Bedrock で実際に踏んだ形。ここが 4 行であることが空行抑止を pin する)
  # **`grep -c .` では空行を検出できない** — 空要素の行を連結する mutant でも非空行は 4 のままで、
  # 差が出るのは**総行数**だけ (実測: 正常 4 / mutant 5)。**総行数は `grep -c ''`** で数える —
  # `$( )` は末尾改行を落とすので変数越しには見えず、ファイルに 1 回出せば 2 通りの数え方が
  # **同じ出力**を指す (描画を 2 回するとその間の背景書き込みで別物になりうる)。
  printf -v j "$fmt" '{}'
  outf="$BATS_TEST_TMPDIR/l5-both-gone.out"
  printf '%s' "$j" | /bin/bash statusline-command.sh >"$outf" 2>/dev/null
  [[ "$(grep -c . <"$outf")" -eq 4 ]]
  [[ "$(grep -c '' <"$outf")" -eq 4 ]]
}

@test "Line5: rate_limitsのused_percentageがfloatでもroundされること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.80","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":35.7,"resets_at":4070908800}}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '5p')
  [[ "$result" == *"36%"* ]]
}

# ============================================================================
# 統合テスト: Line 3 — Git情報が専用行に表示されること
# ============================================================================
@test "Git: git管理外ディレクトリでno gitと表示すること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" == *"no git"* ]]
}

@test "Git: gitリポジトリのコールドスタートでno gitを表示しないこと" {
  # Clear cache to simulate cold start
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$(pwd)"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" != *"no git"* ]]
}

@test "Git: 空リポジトリ(.invalid HEAD)を(empty)に翻訳すること" {
  # ghq get 失敗残骸 / git init 直後 / clone aborted を再現:
  # HEAD は ref: refs/heads/.invalid だが refs/ も objects/ も空
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  local tmp_repo
  tmp_repo=$(mktemp -d)
  mkdir -p "$tmp_repo/.git/refs" "$tmp_repo/.git/objects"
  printf 'ref: refs/heads/.invalid\n' > "$tmp_repo/.git/HEAD"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  rm -rf "$tmp_repo"
  [[ "$result" == *"(empty)"* ]]
  [[ "$result" != *".invalid"* ]]
  # (empty) は dim、Git オレンジでは無いこと
  [[ "$result" == *"${DIM}(empty)${RST}"* ]]
}

@test "Git: コールドスタートでブランチ名を即時表示すること" {
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$(pwd)"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" == *"main"* || "$result" == *"master"* || "$result" == *"HEAD@"* ]]
}

@test "Git: ブランチ名がGitオレンジ(38;5;202)で表示されること" {
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$(pwd)"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  # ブランチ名が Git オレンジ(38;5;202m)で着色されていること
  [[ "$result" == *$'\033[38;5;202m'* ]]
}

@test "Git: GitHub originでgh:プレフィックスがdim・owner/repoが通常輝度でブランチ前に表示されること" {
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  rm -f "$cache_dir"/* 2>/dev/null
  # cold start: build_git の background が cache を書く
  echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$(pwd)"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh >/dev/null 2>&1
  _wait_for_cache "$cache_dir"
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$(pwd)"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  # gh: のみ dim、値は RST 後の通常輝度（ローカル dir 名と origin 名の食い違い判別用）。
  # このリポ自身は dir 名 = repo 名なので、v1.74.0 以降は repo 部が畳まれて owner だけになる
  [[ "$result" == *"${DIM}gh:${RST}ist-j-ichikawa/"* ]]
  # gh: 部分が GIT オレンジのブランチ名より左にあること
  gh_pos="${result%%gh:*}"
  branch_pos="${result%%${GIT}*}"
  [[ ${#gh_pos} -lt ${#branch_pos} ]]
}

@test "Git: origin未設定リポではgh:が表示されないこと" {
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  local tmp_repo
  tmp_repo=$(mktemp -d)
  ( cd "$tmp_repo" && git init -q && git -c user.name=t -c user.email=t@t commit --allow-empty -q -m init )
  rm -f "$cache_dir"/* 2>/dev/null
  echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh >/dev/null 2>&1
  _wait_for_cache "$cache_dir"
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  rm -rf "$tmp_repo"
  [[ "$result" != *"gh:"* ]]
}

@test "Git: SSH形式originがgh:owner/repoに正規化されること" {
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  local tmp_repo
  tmp_repo=$(mktemp -d)
  ( cd "$tmp_repo" && git init -q \
    && git -c user.name=t -c user.email=t@t commit --allow-empty -q -m init \
    && git remote add origin "git@github.com:acme/widgets.git" )
  rm -f "$cache_dir"/* 2>/dev/null
  echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh >/dev/null 2>&1
  _wait_for_cache "$cache_dir"
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  rm -rf "$tmp_repo"
  [[ "$result" == *"gh:${RST}acme/widgets"* ]]
  # .git サフィックスが取れていること
  [[ "$result" != *"acme/widgets.git"* ]]
}

@test "Git: GitLab origin が gl: と GitLab の tree URL になること" {
  # 上流は 2.1.234 で GitLab MR を footer/statusline に載せた。`review_state` は GitLab でも来るので、
  # host を `github.com` 決め打ちにしていると **state だけ出て repo 識別もリンクも無い行**になる。
  # **`/-/tree/` であること**が要点 — GitHub と同じ `/tree/` を張ると GitLab では 404 になる
  # (リンクは見た目が壊れないので、テストで見ないと気付けない)。
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  local tmp_repo
  tmp_repo=$(mktemp -d)
  _repo_at "$tmp_repo"
  git -C "$tmp_repo" remote add origin "git@gitlab.com:acme/widgets.git"
  rm -f "$cache_dir"/* 2>/dev/null
  echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.234","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh >/dev/null 2>&1
  _wait_for_cache "$cache_dir"
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.234","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  rm -rf "$tmp_repo"
  [[ "$result" == *"gl:${RST}acme/widgets"* ]]
  [[ "$result" == *"https://gitlab.com/acme/widgets/-/tree/"* ]]
  # GitHub 用の略号と URL に落ちていないこと（両方 pin しないと片方の回帰が通る）
  [[ "$result" != *"gh:"* ]]
  [[ "$result" != *"https://gitlab.com/acme/widgets/tree/"* ]]
}

@test "Git: userinfo 付き https origin でもブランチのリンクを出すこと" {
  # 上流は 2.1.234 で `https://user@host/…` の host 誤読を直した。こちら側の origin 正規化は
  # userinfo 無しの 3 形しか受けていなかったので、`remote=""` になって**ブランチの OSC 8 リンクだけ**が
  # 静かに落ちていた（`gh:` は stdin の workspace.repo から出るので画面では気付けない）。
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  local tmp_repo
  tmp_repo=$(mktemp -d)
  _repo_at "$tmp_repo"
  git -C "$tmp_repo" remote add origin "https://bot@github.com/acme/widgets.git"
  rm -f "$cache_dir"/* 2>/dev/null
  echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.234","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh >/dev/null 2>&1
  _wait_for_cache "$cache_dir"
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.234","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  rm -rf "$tmp_repo"
  [[ "$result" == *"https://github.com/acme/widgets/tree/"* ]]
  # userinfo が URL に残っていないこと（残ると認証情報が画面とリンクに載る）
  [[ "$result" != *"bot@"* ]]
  [[ "$result" == *"gh:${RST}acme/widgets"* ]]
}

@test "Git: workspace.repo(Claude Code 2.1.145+)がコールドスタートでもgh:を表示すること" {
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  rm -f "$cache_dir"/* 2>/dev/null
  # cache を消して即座に sed -n '3p' する = cold start。git remote get-url を介さず stdin から gh: が出る
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" == *"gh:${RST}acme/widgets"* ]]
}

@test "Git: パス末尾が owner/repo と一致するとき gh: を省くこと" {
  # ghq 系のレイアウト (~/ghq/github.com/<owner>/<repo>) では Line 2 のパス末尾がそのまま
  # owner/repo なので、Line 3 の gh: は同じ文字列の二度出しになる (v1.74.0 で省く)。
  local d="$BATS_TEST_TMPDIR/ghq/github.com/acme/widgets"
  _repo_at "$d"
  result=$(_line3_of '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$d"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"context_window":{"used_percentage":10}}')
  [[ "$result" != *"gh:"* ]]
  [[ "$result" != *"acme/widgets"* ]]   # 省くのは gh: ごと (プレフィックスだけ消して値が残らない)
  [[ -n "$result" ]]                     # 行そのものは出る (ブランチ等が残る)
}

@test "Git: パス末尾が repo 名だけ一致するとき gh:owner/ に畳むこと" {
  # `~/dev/<repo>` という最も普通の clone レイアウト。repo 名は真上の行にあるので owner だけ残す。
  # **末尾の `/`** は「続きは真上の行の末尾」の標識 — 裸の `gh:acme` は「acme という repo」に誤読される。
  local d="$BATS_TEST_TMPDIR/dev/widgets"
  _repo_at "$d"
  result=$(_line3_of '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$d"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"context_window":{"used_percentage":10}}')
  [[ "$result" == *"gh:${RST}acme/"* ]]
  [[ "$result" != *"acme/widgets"* ]]   # repo 名は畳まれて残らない
}

@test "Git: worktree でも Line 2 が描いたパスと突き合わせて畳むこと" {
  # worktree では Line 2 が `<repo>/.claude/worktrees/<name>` を repo root で切って
  # `~/dev/myrepo 🌲wt` と描く。**画面に出ている末尾は repo 名**なので、`current_dir`
  # (末尾 = worktree 名) と比べると畳めず、repo 名が縦に 2 回出たままになる (code-review 指摘)。
  local root="$BATS_TEST_TMPDIR/wtrepo/widgets" wt
  wt="$root/.claude/worktrees/fix-bug"
  _repo_at "$wt"
  result=$(_line3_of '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$root"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"worktree":{"name":"fix-bug","path":"'"$wt"'","original_branch":"main"},"context_window":{"used_percentage":10}}')
  [[ "$result" == *"gh:${RST}acme/"* ]]
  [[ "$result" != *"acme/widgets"* ]]
}

@test "Git: repo 名が上位文字列に含まれるだけでは畳まないこと(/ アンカー)" {
  # `my-widgets` は `widgets` を含むが別の dir。アンカー無しの比較だと誤爆して owner だけになる
  local d="$BATS_TEST_TMPDIR/anchor/my-widgets"
  _repo_at "$d"
  result=$(_line3_of '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$d"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"context_window":{"used_percentage":10}}')
  [[ "$result" == *"gh:${RST}acme/widgets"* ]]
}

@test "Git: ローカルdir名とorigin repo名が食い違うとき gh: を出すこと" {
  # gh: の存在理由そのもの。一致しないケースは**出し続ける**側に倒す (大文字小文字差も含む)。
  local d="$BATS_TEST_TMPDIR/case/acme/Widgets"   # 名前は同じで大文字小文字だけ違う
  _repo_at "$d"
  result=$(_line3_of '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$d"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"context_window":{"used_percentage":10}}')
  [[ "$result" == *"gh:${RST}acme/widgets"* ]]
}

@test "Git: untracked が上限を超えたら行数を数えないこと(全走査で毎レンダー再走査になるのを防ぐ)" {
  # 数えるコストは untracked の総バイト数に比例するので、ignore 漏れの node_modules
  # (実測 30,000 件で 5.17 秒) ではキャッシュ寿命 5s を超えて毎レンダー全走査 + 背景 job の
  # 積み上がりになる (code-review 指摘)。上限超過では**要素ごと落とす** (中途半端な合計は
  # 「間違った数」になるため)。上限は 500。
  local d="$BATS_TEST_TMPDIR/capped" i plain
  _repo_at "$d"
  # 501 件の untracked (各 1 行) — 数えていれば +501 が出る
  ( cd "$d" && for i in {1..501}; do printf 'x\n' > "u$i.txt"; done )
  plain=$(_line3_of "{\"model\":{\"id\":\"test\",\"display_name\":\"Test\"},\"version\":\"2.1.146\",\"workspace\":{\"current_dir\":\"$d\"},\"context_window\":{\"used_percentage\":10}}" | _strip)
  [[ "$plain" != *"+501"* ]]
  [[ "$plain" != *"+5"* ]]     # 途中まで数えた中途半端な合計も出さない
}

@test "Git: untracked が上限内なら行数を数えること" {
  # 上限の実装で通常ケースを落としていないこと (上のテストだけだと「常に 0」でも緑になる)
  local d="$BATS_TEST_TMPDIR/uncapped" plain
  _repo_at "$d"
  printf 'a\nb\nc\n' > "$d/u.txt"
  plain=$(_line3_of "{\"model\":{\"id\":\"test\",\"display_name\":\"Test\"},\"version\":\"2.1.146\",\"workspace\":{\"current_dir\":\"$d\"},\"context_window\":{\"used_percentage\":10}}" | _strip)
  [[ "$plain" == *"+3"* ]]
}

@test "Git: rebase 中は進捗つきで先頭に出すこと(HEAD@sha と区別できるように)" {
  # `HEAD@<sha>` だけでは「sha を直接 checkout した」と「rebase 中」が区別できず、
  # 実際に「Line 3 の表示が変」と読まれた。**本物のコンフリクト付き rebase** を作って確認する。
  local d="$BATS_TEST_TMPDIR/rebasing" plain
  mkdir -p "$d"
  ( cd "$d" && git init -q -b main \
    && git config user.email t@t && git config user.name t \
    && printf 'a\n' > f && git add f && git commit -qm base \
    && git checkout -q -b topic && printf 'topic\n' > f && git commit -qam topic \
    && git checkout -q main && printf 'main\n' > f && git commit -qam main \
    && git checkout -q topic && git rebase main ) >/dev/null 2>&1 || true   # rebase は conflict で rc=1
  # 前提の確認 — rebase が本当に中断していること (成功していたらテストが無意味)
  [[ -d "$d/.git/rebase-merge" || -d "$d/.git/rebase-apply" ]] \
    || { echo "rebase が中断していない = テストが無意味" >&3; return 1; }
  plain=$(_line3_of "{\"model\":{\"id\":\"test\",\"display_name\":\"Test\"},\"version\":\"2.1.146\",\"workspace\":{\"current_dir\":\"$d\"},\"context_window\":{\"used_percentage\":10}}" | _strip)
  [[ "$plain" == "rebase 1/1"* ]]        # 先頭 = この行で最も行動に直結する事実
  [[ "$plain" == *"HEAD@"* ]]            # detached の事実も残す
  [[ "$plain" == *"!1"* ]]               # コンフリクトも並ぶ
}

@test "Git: merge 中は merge と出すこと" {
  local d="$BATS_TEST_TMPDIR/merging" plain
  mkdir -p "$d"
  ( cd "$d" && git init -q -b main \
    && git config user.email t@t && git config user.name t \
    && printf 'a\n' > f && git add f && git commit -qm base \
    && git checkout -q -b topic && printf 'topic\n' > f && git commit -qam topic \
    && git checkout -q main && printf 'main\n' > f && git commit -qam main \
    && git merge topic ) >/dev/null 2>&1 || true   # merge は conflict で rc=1
  [[ -f "$d/.git/MERGE_HEAD" ]] \
    || { echo "merge が中断していない = テストが無意味" >&3; return 1; }
  plain=$(_line3_of "{\"model\":{\"id\":\"test\",\"display_name\":\"Test\"},\"version\":\"2.1.146\",\"workspace\":{\"current_dir\":\"$d\"},\"context_window\":{\"used_percentage\":10}}" | _strip)
  [[ "$plain" == "merge"* ]]
  [[ "$plain" == *"main"* ]]   # merge 中はブランチに乗ったままなので branch も出る
}

@test "Git: 通常の状態では進行中の操作を出さないこと" {
  # 常に何か出るなら差分シグナルにならない (このリポ自身は clean な状態で回る)
  local plain
  plain=$(_line3_of "{\"model\":{\"id\":\"test\",\"display_name\":\"Test\"},\"version\":\"2.1.146\",\"workspace\":{\"current_dir\":\"$(pwd)\"},\"context_window\":{\"used_percentage\":10}}" | _strip)
  [[ "$plain" != *"rebase"* ]]
  [[ "$plain" != *"merge"* ]]
  [[ "$plain" != *"cherry-pick"* ]]
}

@test "Git: detached HEADのcold startではgh:を表示しないこと(build_git detachedパスとgate統一)" {
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  local tmp_repo
  tmp_repo=$(mktemp -d)
  ( cd "$tmp_repo" && git init -q \
    && git -c user.name=t -c user.email=t@t commit --allow-empty -q -m init \
    && git checkout -q --detach )
  rm -f "$cache_dir"/* 2>/dev/null
  # cold start: build_git の detached パスは gh: を出さないので、cold start が出すと cache populate 時にフリッカーする
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$tmp_repo"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  rm -rf "$tmp_repo"
  [[ "$result" != *"gh:"* ]]
  [[ "$result" == *"HEAD@"* ]]
}

@test "PR: pr.review_state=approvedで緑色のテキストが表示されること" {
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"pr":{"number":1234,"review_state":"approved"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" == *$'\033[32m'"approved"* ]]
}

@test "PR: pr.review_state=changes_requestedで赤色のテキストが表示されること" {
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"pr":{"number":1234,"review_state":"changes_requested"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" == *$'\033[31m'"changes_requested"* ]]
}

@test "PR: pr.review_state=pendingで黄色のテキストが表示されること" {
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"pr":{"number":1234,"review_state":"pending"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" == *$'\033[33m'"pending"* ]]
}

@test "PR: pr.review_state=draftでグレー(38;5;245)のテキストが表示されること" {
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"pr":{"number":1234,"review_state":"draft"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" == *$'\033[38;5;245m'"draft"* ]]
}

@test "PR: pr.review_stateが空の場合は何も表示しないこと" {
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" != *"approved"* ]]
  [[ "$result" != *"pending"* ]]
}

@test "PR: PR番号(#)は表示しないこと — Claude Code 組み込みフッターと住み分け" {
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"pr":{"number":1234,"url":"https://github.com/acme/widgets/pull/1234","review_state":"approved"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" != *"#1234"* ]]
}

@test "Git: workspace.repoのgitlab.comがコールドスタートでもgl:を表示すること" {
  # **`!= *"gh:"*` だけでは pin にならない** — case arm (`gitlab.com) ws_repo_forge="gl"`) を消しても
  # 「何も出ない」で緑になる。GitHub 側にはコールドスタートの pin があるのに GitLab には無かった。
  # 出る値そのものを assert する（コールドスタート = facts キャッシュが空なので stdin 経路だけが働く）。
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"gitlab.com","owner":"acme","name":"widgets"}},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" == *"gl:"*"acme/widgets"* ]]
  [[ "$result" != *"gh:"* ]]
}

# ============================================================================
# vim mode badge — NORMAL は非表示、INSERT/VISUAL/VISUAL LINE は bg 色付きで Line 1 最左に
# ============================================================================
@test "vim: INSERTモードで青バッジが表示されること(gruvbox/airline の流儀)" {
  result=$(echo '{"model":{"id":"t","display_name":"T"},"version":"2.1.146","workspace":{"current_dir":"/tmp"},"vim":{"mode":"INSERT"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  # bg lime-green (48;5;148, gruvbox-ish) + bold + INSERT テキストが含まれること
  # 緑にしない — 緑は gruvbox/airline では NORMAL/COMMAND の色でモードを誤読させる
  [[ "$result" == *$'\033[1;30;48;5;109m INSERT '* ]]
}

@test "vim: VISUALモードで橙バッジが表示されること" {
  result=$(echo '{"model":{"id":"t","display_name":"T"},"version":"2.1.146","workspace":{"current_dir":"/tmp"},"vim":{"mode":"VISUAL"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[1;30;48;5;208m VISUAL '* ]]
}

@test "vim: VISUAL LINEはV-LINEに短縮して同じ橙バッジで表示されること" {
  result=$(echo '{"model":{"id":"t","display_name":"T"},"version":"2.1.146","workspace":{"current_dir":"/tmp"},"vim":{"mode":"VISUAL LINE"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[1;30;48;5;208m V-LINE '* ]]
  [[ "$result" != *"VISUAL LINE"* ]]
}

@test "vim: NORMALモードはバッジを表示しないこと (デフォルト状態でノイズ削減)" {
  result=$(echo '{"model":{"id":"t","display_name":"T"},"version":"2.1.146","workspace":{"current_dir":"/tmp"},"vim":{"mode":"NORMAL"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" != *"NORMAL"* ]]
  [[ "$result" != *"48;5;148"* ]]
  [[ "$result" != *"48;5;214"* ]]
}

@test "vim: vim.mode未設定の場合はバッジを表示しないこと (vim mode無効セッション)" {
  result=$(echo '{"model":{"id":"t","display_name":"T"},"version":"2.1.146","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" != *"INSERT"* ]]
  [[ "$result" != *"48;5;148"* ]]
  [[ "$result" != *"48;5;214"* ]]
}

@test "Git: origin の末尾スラッシュを畳んで gh:owner/repo/ にしないこと" {
  # git は URL を verbatim で持つので `https://github.com/o/r/` が来る。剥がさないと
  # `repo_id="o/r/"` になり、末尾 `/` は「repo 部は真上の行」の標識と衝突して owner に誤読される。
  # tree URL も `//tree/main` になる。**表示は崩れないのでテストでしか気付けない**。
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  local tmp_repo
  tmp_repo=$(mktemp -d)
  ( cd "$tmp_repo" && git init -q \
    && git -c user.name=t -c user.email=t@t commit --allow-empty -q -m init \
    && git remote add origin "https://github.com/acme/widgets/" )
  rm -f "$cache_dir"/* 2>/dev/null
  echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh >/dev/null 2>&1
  _wait_for_cache "$cache_dir"
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  rm -rf "$tmp_repo"
  # 表示要素は空白で終わる（`acme/widgets/` なら空白の前に `/` が残る）。**URL 側にも `acme/widgets/`
  # が現れる**（`/tree/master` の区切り）ので、`!= *"acme/widgets/"*` では偽陽性になる
  [[ "$result" == *"acme/widgets "* ]]
  [[ "$result" != *"widgets//tree"* ]]
}

@test "Git: 許可リストに無い forge(bitbucket等)では略号もリンクも出さないこと" {
  # 旧名は「非GitHub origin(GitLab等)では gh: が出ないこと」だったが、2.1.234 追従で gitlab.com が
  # `gl:` としてサポート対象になったため、**テスト名と実際の挙動が食い違い、許可リスト
  # (「知らない forge にそれっぽいリンクを張らない」) の pin が 0 本になっていた**。
  # 未知ホストに向け直す — ここが緑のままだと `*) forge="gh"` のような穴を検出できない。
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  local tmp_repo
  tmp_repo=$(mktemp -d)
  ( cd "$tmp_repo" && git init -q \
    && git -c user.name=t -c user.email=t@t commit --allow-empty -q -m init \
    && git remote add origin "git@bitbucket.org:acme/widgets.git" )
  rm -f "$cache_dir"/* 2>/dev/null
  echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh >/dev/null 2>&1
  _wait_for_cache "$cache_dir"
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  rm -rf "$tmp_repo"
  [[ "$result" != *"gh:"* ]]
  [[ "$result" != *"gl:"* ]]
  [[ "$result" != *"bitbucket"* ]]
  # **stdin 経路も同じ方針で pin する** — facts 経路だけだと `*) remote="" ;;` と forge の gate の
  # 2 箇所を同時に壊さないと赤くならない（単発 mutation を検出できない）。stdin の host は
  # `ws_repo_forge` の case が直接受けるので、`*) ws_repo_forge="gh" ;;` を足した瞬間ここが赤くなる。
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"bitbucket.org","owner":"acme","name":"widgets"}},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" != *"gh:"* ]]
  [[ "$result" != *"gl:"* ]]
  [[ "$result" != *"acme/widgets"* ]]
}

# ============================================================================
# 統合テスト: セッション表示 — 状態に応じた表示がされること
# ============================================================================
@test "セッション: 名前未設定で(no name)が表示されないこと" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" != *"(no name)"* ]]
}

@test "セッション: ブランチ時にbranchと表示すること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"session_name":"(Branch) my session","version":"2.1.77","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  # 黄色のbranch表記があること (セッション名のresidueではなくインジケータ)
  [[ "$result" == *$'\033[33mbranch'* ]]
}

@test "セッション: 旧フォーク形式でもbranchと表示すること" {
  # 2.1.77 より前の `(Fork)` は現行 `/branch` のエイリアス。fork と出すと意味が逆になる
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"session_name":"(Fork) my session","version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[33mbranch'* ]]
}

@test "セッション: /fork の ⑂ マーカーを fork として黄で表示すること" {
  # 2.1.220 実測: /fork は親の名前を継承して末尾に U+2442 (OCR FORK) だけを足す。(Fork) は付かない
  j=$(jq -nc --arg n "branch と fork のテスト実装 $FORK_GLYPH" \
    '{model:{id:"test",display_name:"Test"},session_name:$n,version:"2.1.220",workspace:{current_dir:"/tmp"},context_window:{used_percentage:10}}')
  result=$(printf '%s' "$j" | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[33mfork'* ]]
  [[ "$result" != *"branch"* ]]        # branch と混同しない
  [[ "$result" != *"$FORK_GLYPH"* ]]   # 生グリフは出さない (語に置き換える)
}

@test "セッション: /branch した会話を /fork したら fork を優先すること" {
  # 両マーカーが付く (`foo (Branch) ⑂`)。「親が並走している」ほうが新しく行動に直結する
  j=$(jq -nc --arg n "my session (Branch) $FORK_GLYPH" \
    '{model:{id:"test",display_name:"Test"},session_name:$n,version:"2.1.220",workspace:{current_dir:"/tmp"},context_window:{used_percentage:10}}')
  result=$(printf '%s' "$j" | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[33mfork'* ]]
  [[ "$result" != *$'\033[33mbranch'* ]]
}

@test "セッション: 元セッションの名前が (Branch) に書き換えられても branch を出さないこと" {
  # 2.1.221 実測: `/branch` は子だけでなく **元セッションの custom-title にも** ` (Branch)` を書く。
  # 元・子・元を resume した実体の 3 つが同名になり、元に戻っても branch が消えなかった。
  # 元の transcript は `forkedFrom` を持たないので、それを裏取りに使って抑止する。
  _t="$BATS_TEST_TMPDIR/origin.jsonl"
  printf '%s\n' '{"type":"custom-title","customTitle":"my session (Branch)"}' > "$_t"
  j=$(jq -nc --arg t "$_t" \
    '{model:{id:"test",display_name:"Test"},session_name:"my session (Branch)",transcript_path:$t,version:"2.1.221",workspace:{current_dir:"/tmp"},context_window:{used_percentage:10}}')
  result=$(printf '%s' "$j" | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" != *$'\033[33mbranch'* ]]
  [[ "$result" == *"v2.1.221"* ]]   # 到達証跡: 行自体は描かれている
}

@test "セッション: forkedFrom が冒頭のヘッダ記録の後ろでも連番 (Branch 2) で branch を出すこと" {
  # 実測 2 点を 1 本で pin: ① forkedFrom は必ずしも 1 行目でない (custom-title/mode/
  # file-history-snapshot が先に積まれ 7 行目に来る transcript が実在。23 件中 1 件) —
  # 先頭 1 行しか見ない実装だと本物の子のバッジが消える ② 2 本目の分岐は `(Branch 2)` の連番
  _t="$BATS_TEST_TMPDIR/child.jsonl"
  {
    printf '%s\n' '{"type":"custom-title","customTitle":"branchとforkのテスト (Branch 2)"}'
    printf '%s\n' '{"type":"mode","mode":"default"}'
    printf '%s\n' '{"type":"permission-mode","permissionMode":"default"}'
    printf '%s\n' '{"type":"file-history-snapshot","snapshot":{}}'
    printf '%s\n' '{"type":"file-history-snapshot","snapshot":{}}'
    printf '%s\n' '{"type":"file-history-snapshot","snapshot":{}}'
    printf '%s\n' '{"type":"user","forkedFrom":{"sessionId":"a8ec6f0b","messageUuid":"241ae17b"}}'
  } > "$_t"
  j=$(jq -nc --arg t "$_t" \
    '{model:{id:"test",display_name:"Test"},session_name:"branchとforkのテスト (Branch 2)",transcript_path:$t,version:"2.1.220",workspace:{current_dir:"/tmp"},context_window:{used_percentage:10}}')
  result=$(printf '%s' "$j" | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[33mbranch'* ]]
}

@test "セッション: 本文に forkedFrom の文字列を含むだけの元セッションを子と誤認しないこと" {
  # JSON 文字列値の中の `"` は必ず `\"` にエスケープされるので、needle `"forkedFrom":{` は
  # 構造上のキーとしてしか現れない。jsonl 断片を最初のプロンプトに貼ったセッションが誤爆しないことを pin
  _t="$BATS_TEST_TMPDIR/pasted.jsonl"
  printf '%s\n' '{"type":"user","message":{"content":"debug: \"forkedFrom\":{\"sessionId\":\"x\"} をパースしたい"}}' > "$_t"
  j=$(jq -nc --arg t "$_t" \
    '{model:{id:"test",display_name:"Test"},session_name:"my session (Branch)",transcript_path:$t,version:"2.1.221",workspace:{current_dir:"/tmp"},context_window:{used_percentage:10}}')
  result=$(printf '%s' "$j" | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" != *$'\033[33mbranch'* ]]
  [[ "$result" == *"v2.1.221"* ]]   # 到達証跡
}

@test "セッション: (Branch を含むだけの名前をマーカーと誤認しないこと (degraded path)" {
  # transcript が読めない環境では名前だけが頼り。マーカーの実測形 `(Branch)` / `(Branch N)` 以外
  # ("(Branch protection rules)" 等) を受けると degraded path で偽バッジが常時点灯する
  j=$(jq -nc '{model:{id:"test",display_name:"Test"},session_name:"meeting notes (Branch protection rules)",version:"2.1.77",workspace:{current_dir:"/tmp"},context_window:{used_percentage:10}}')
  result=$(printf '%s' "$j" | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" != *$'\033[33mbranch'* ]]
  [[ "$result" == *"v2.1.77"* ]]   # 到達証跡
}

@test "セッション: ⑂ は forkedFrom の裏取り無しでも fork を出すこと" {
  # ⑂ は customTitle に書かれず実行時の名前にだけ付く = 元へ伝播しないので gate を掛けない。
  # fork の子が forkedFrom を持つ保証も実測で取れていないため、掛けると出なくなる副作用のほうが重い。
  _t="$BATS_TEST_TMPDIR/forked.jsonl"
  printf '%s\n' '{"type":"custom-title","customTitle":"my session"}' > "$_t"
  j=$(jq -nc --arg n "my session $FORK_GLYPH" --arg t "$_t" \
    '{model:{id:"test",display_name:"Test"},session_name:$n,transcript_path:$t,version:"2.1.221",workspace:{current_dir:"/tmp"},context_window:{used_percentage:10}}')
  result=$(printf '%s' "$j" | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[33mfork'* ]]
}

@test "セッション: transcript_path が読めない旧 Claude Code では名前だけで branch を出すこと" {
  # graceful degradation — フィールドが無い/消えた環境で機能を落とさない
  j=$(jq -nc '{model:{id:"test",display_name:"Test"},session_name:"my session (Branch)",transcript_path:"/nonexistent/x.jsonl",version:"2.1.77",workspace:{current_dir:"/tmp"},context_window:{used_percentage:10}}')
  result=$(printf '%s' "$j" | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[33mbranch'* ]]
}

@test "セッション: branch 先に元セッションの id を full uuid で添えること" {
  # `/branch` の元は別端末で resume されるので、戻るには元の id が要る (コピーして `--resume`)。
  # 裏取りで既に読んでいる forkedFrom.sessionId から抜くので追加 I/O も fork も無い。
  # **切り詰めない** — `--resume` は 8 桁 prefix を受けない (2.1.222 実測) ので短縮すると戻れない
  _t="$BATS_TEST_TMPDIR/child-sid.jsonl"
  printf '%s\n' '{"type":"user","forkedFrom":{"sessionId":"3052272d-8e61-4a0c-a506-bfd8d3206d73","messageUuid":"c75c65fa-5030-4058-9b07-d4ca25f83f27"}}' > "$_t"
  j=$(jq -nc --arg t "$_t" \
    '{model:{id:"test",display_name:"Test"},session_name:"my session (Branch)",transcript_path:$t,version:"2.1.222",workspace:{current_dir:"/tmp"},context_window:{used_percentage:10}}')
  result=$(printf '%s' "$j" | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  # ラベル側 (黄) に `:` まで含め、値は通常輝度 — `gh:` と同じ「値が一次情報」の作法
  [[ "$result" == *$'\033[33mbranch:\033[0m3052272d-8e61-4a0c-a506-bfd8d3206d73'* ]]
  # messageUuid を混ぜて拾っていないこと (forkedFrom は 2 つの uuid を持つ)
  [[ "$result" != *"c75c65fa"* ]]
}

@test "セッション: forkedFrom の外にある別の sessionId を元の id と誤認しないこと" {
  # 抽出は `}` まででスコープを閉じる。閉じないと forkedFrom が sessionId を持たない形 (将来の
  # スキーマ変更) で同じ行の後続キー (自分自身の sessionId 等) を拾い、「元へ戻る id」が自分に
  # なって往復が成立しなくなる。`#*` は最短一致なので、forkedFrom 内に sessionId がある通常形は
  # スコープ切り無しでも正しく取れる — このケースだけが `}` の存在を検出できる
  _t="$BATS_TEST_TMPDIR/scoped.jsonl"
  printf '%s\n' '{"type":"user","forkedFrom":{"messageUuid":"x"},"sessionId":"bbbbbbbb-5555-6666-7777-888888888888"}' > "$_t"
  j=$(jq -nc --arg t "$_t" \
    '{model:{id:"test",display_name:"Test"},session_name:"my session (Branch)",transcript_path:$t,version:"2.1.222",workspace:{current_dir:"/tmp"},context_window:{used_percentage:10}}')
  result=$(printf '%s' "$j" | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" != *"bbbbbbbb"* ]]
  [[ "$result" == *$'\033[33mbranch\033[0m'* ]]   # 語だけに落ちる (到達証跡も兼ねる)
}

@test "セッション: uuid の形でない sessionId は添えず branch の語だけにすること" {
  # 許可リストで 8-4-4-4-12 の hex だけ受ける (拒否リストは持たない方針) — 壊れた記録や別形式の
  # id (`agent-*` 等) が来ても表示を汚さず、語だけの従来表示に落ちる。
  # 2 つの arm を別々に pin する — 配置 arm だけだと非 hex が素通りする (mutation で確認済み)
  _t="$BATS_TEST_TMPDIR/badsid.jsonl"
  printf '%s\n' '{"type":"user","forkedFrom":{"sessionId":"../../etc/passwd","messageUuid":"x"}}' > "$_t"
  j=$(jq -nc --arg t "$_t" \
    '{model:{id:"test",display_name:"Test"},session_name:"my session (Branch)",transcript_path:$t,version:"2.1.222",workspace:{current_dir:"/tmp"},context_window:{used_percentage:10}}')
  result=$(printf '%s' "$j" | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[33mbranch\033[0m'* ]]   # 配置 arm が弾く
  [[ "$result" != *"passwd"* ]]
  # uuid の**配置は正しいが hex でない** — こちらは字種 arm だけが弾ける
  printf '%s\n' '{"type":"user","forkedFrom":{"sessionId":"zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz","messageUuid":"x"}}' > "$_t"
  result=$(printf '%s' "$j" | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[33mbranch\033[0m'* ]]
  [[ "$result" != *"zzzz"* ]]
}

@test "セッション: fork には元の id を添えないこと" {
  # fork の元は同じ端末に残り detach (`←`) で戻れるので id が要らない。かつ fork の子は
  # forkedFrom を持たない (2.1.222 実測: `/fork` 子 transcript の全 47 行に 0 件) ので抜き元も無い
  _t="$BATS_TEST_TMPDIR/fork-nosid.jsonl"
  printf '%s\n' '{"type":"custom-title","customTitle":"my session"}' > "$_t"
  j=$(jq -nc --arg n "my session $FORK_GLYPH" --arg t "$_t" \
    '{model:{id:"test",display_name:"Test"},session_name:$n,transcript_path:$t,version:"2.1.222",workspace:{current_dir:"/tmp"},context_window:{used_percentage:10}}')
  result=$(printf '%s' "$j" | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[33mfork\033[0m'* ]]
}

@test "セッション: マーカーが無ければ出自バッジを出さないこと" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"session_name":"ふつうの名前","version":"2.1.220","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" != *"branch"* ]]
  [[ "$result" != *"fork"* ]]
}

# ============================================================================
# 宛名 — cross-session messaging のアドレス (`~/.claude/sessions/<pid>.json` の derived name)。
# 表記の判断と却下案は docs/internals.md の「宛名」節を参照
# ============================================================================

# _peer_home SID NAME [EXTRA_JSON] [NAMESOURCE_JSON] [KIND] — 偽 HOME に sessions ファイルを 1 個置き、
# _peer_pre を組む。NAMESOURCE_JSON は `,"nameSource":…` 相当を丸ごと差し替える (既定 derived、
# 空文字を渡すとフィールドごと消えて背景セッション / `/rename` 相当になる)。KIND は既定 `interactive`。
# **末尾に改行を付けない** — 実物 (2.1.229) が改行なしで、`read` が rc=1 を返す罠をここで常に踏ませる
_peer_home() {
  local sid=$1 name=$2 extra=${3:-} ns=${4-',"nameSource":"derived"'} kind=${5:-interactive}
  _ph="$BATS_TEST_TMPDIR/peer-home"
  mkdir -p "$_ph/.claude/sessions"
  printf '{"pid":54642,"sessionId":"%s","cwd":"/tmp","version":"2.1.229","kind":"%s",%s"name":"%s"%s,"status":"busy"}' \
    "$sid" "$kind" "$extra" "$name" "$ns" > "$_ph/.claude/sessions/54642.json"
  # 上書きが要るのは HOME だけ — `CLAUDE_STATUSLINE_NO_NET` と `CLAUDE_STATUSLINE_CACHE_DIR` は
  # `setup()` が export 済みで、`env -i` ではないので継承される (`BATS_TEST_TMPDIR` もテスト毎に別)
  _peer_pre=(env "HOME=$_ph")
}

_peer_json() {
  jq -nc --arg s "$1" \
    '{model:{id:"test",display_name:"Test"},session_id:$s,workspace:{current_dir:"/tmp"},context_window:{used_percentage:10}}'
}

@test "宛名: session_id に一致する sessions ファイルから宛名を出すこと" {
  # `SendMessage` のアドレスは derived name。session id でも custom title でもないので、
  # これを出さないと「宛名がどこにも表示されない」状態が続く (2.1.229 実測)
  _peer_home "aaaaaaaa-1111-2222-3333-444444444444" "claude-code-statusline-74"
  result=$(_peer_json "aaaaaaaa-1111-2222-3333-444444444444" \
    | "${_peer_pre[@]}" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" 2>/dev/null | head -1)
  # **記号も囲みも付けない**ので名前の直前は必ずスペース = ダブルクリックで丸ごと取れる。
  # この 1 本で `@name` / `<name>` / `[name]` への逆戻りも同時に弾ける (どれも直前がスペースでない)
  [[ "$result" == *" claude-code-statusline-74"* ]]
  # ラベル形は空白を挟んで書けてしまい上の assert を通りうるので、別に弾く
  [[ "$result" != *"peer:"* ]]
}

@test "宛名: 別セッションの sessions ファイルから宛名を拾わないこと" {
  # 同じ HOME に全セッションのファイルが並ぶので、id 照合を外すと**他セッションの宛名**を出す。
  # 宛名は「この端末は誰か」を答えるものなので、取り違えると連携の指示が丸ごと誤配になる
  _peer_home "bbbbbbbb-1111-2222-3333-444444444444" "someone-elses-session-99"
  result=$(_peer_json "aaaaaaaa-1111-2222-3333-444444444444" \
    | "${_peer_pre[@]}" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" 2>/dev/null | head -1)
  [[ "$result" != *"someone-elses-session-99"* ]]
  [[ "$result" == *"Test"* ]]   # 到達証跡 — 描画自体は続いている
}

@test "宛名: nameSource を宛名と誤認しないこと" {
  # needle は `"name":"` で、`"nameSource":"` には一致しない (`"name` の次が `S`)。
  # 実物は name → nameSource の順だが、逆順でも最初の `"name":"` を正しく選ぶことを pin する
  # `nameSource` を `name` より**前**に置いた形 (実物は name → nameSource の順) で、
  # 最初の `"name":"` を正しく選ぶことを見る。4 引数目を空にして既定の重複挿入を止める
  _peer_home "aaaaaaaa-1111-2222-3333-444444444444" "real-name-12" '"nameSource":"derived",' ""
  result=$(_peer_json "aaaaaaaa-1111-2222-3333-444444444444" \
    | "${_peer_pre[@]}" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" 2>/dev/null | head -1)
  [[ "$result" == *" real-name-12"* ]]
  [[ "$result" != *"derived"* ]]
}

@test "宛名: sessions ディレクトリが無くても描画を続け stderr を汚さないこと" {
  # `~/.claude/sessions/` は undocumented な内部ファイル (docs にも CHANGELOG にも無い) なので、
  # 消えても形が変わっても宛名だけ落ちて他は出る = subscription と同じ graceful degradation.
  # glob が展開されないまま `read` に渡る経路もここで踏む。
  # **stderr の空を必ず assert する** — `2>/dev/null` で捨てると、`-r` gate を外しても緑のままになり
  # 「毎レンダー stderr に No such file or directory」を検出できない (リダイレクトは左から
  #  適用されるので `< "$_sf" 2>/dev/null` では黙らない。gate でしか消せない)
  _ph="$BATS_TEST_TMPDIR/peer-nodir"
  mkdir -p "$_ph/.claude"
  _errf="$BATS_TEST_TMPDIR/peer-nodir-stderr"
  result=$(_peer_json "aaaaaaaa-1111-2222-3333-444444444444" \
    | env "HOME=$_ph" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" 2>"$_errf")
  [[ ! -s "$_errf" ]]
  # glob が展開されないまま漏れていないこと (`*.json` のリテラルや sessions パスが出ない)
  [[ "$result" != *".json"* ]]
  [[ "$result" != *"sessions"* ]]
  [[ "$result" == *"Test"* ]]                    # Line 1 は出ている
  [[ "$(printf '%s' "$result" | grep -c .)" -ge 3 ]]   # 行数も崩れていない
}

@test "宛名: nameSource キーが無い背景セッションでも出すこと" {
  # **v1.69.0 の回帰**: `derived` の明示だけを受ける gate を入れたところ、`kind:bg`（`claude agents`
  # 経由）のセッションが `nameSource` キーを持たないため宛名が丸ごと消えた（2.1.229 実測。
  # `name` は AI 生成タイトルで、日本語と空白を含む）。`name` は生成規則にかかわらず
  # `SendMessage` のアドレスなので、出さないと「送れる宛先が画面に無い」状態になる。
  # fixture は**実物どおりキーを丸ごと落とす** — `"nameSource":null` は実在しない形
  # （`jq` が欠損フィールドにも null を返すので、そう誤読しやすい）。
  # 併せて**空白と日本語を含む名前**でも抽出が壊れないことを見る
  _peer_home "aaaaaaaa-1111-2222-3333-444444444444" "statuslineに session id を常に表示" "" "" "bg"
  result=$(_peer_json "aaaaaaaa-1111-2222-3333-444444444444" \
    | "${_peer_pre[@]}" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" 2>/dev/null | head -1)
  [[ "$result" == *" statuslineに session id を常に表示"* ]]
}

@test "宛名: 名前に含まれる引用符で切らないこと (誤配防止)" {
  # 値の中の `"` は JSON では `\"` なので、素朴に `%%'"'*` で切ると `fix \"foo\" bug` が
  # `fix \` になり **誤った宛名**を出す = `SendMessage` の誤配。名前が cwd 由来の slug だけだった
  # 頃は `"` が入らず踏まなかったが、AI 生成タイトルや `/branch <名前>` の任意文字列を受ける
  # ようになって常用経路に乗った。この機能で唯一「無表示」でなく「誤情報」になる経路なので pin する。
  # `\\` も見る — `\\"` を「`\` + エスケープされた `"`」と誤読すると同じく切る位置を間違える
  _peer_home "aaaaaaaa-1111-2222-3333-444444444444" 'fix \"foo\" bug' "" ""
  result=$(_peer_json "aaaaaaaa-1111-2222-3333-444444444444" \
    | "${_peer_pre[@]}" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" 2>/dev/null | head -1)
  [[ "$result" == *'fix "foo" bug'* ]]
  [[ "$result" != *'fix \'* ]]
}

@test "宛名: 制御文字の escape は decode せず行数契約を守ること" {
  # **`\n` を実文字へ decode してはいけない** — 単一 printf で書き出す行数契約が壊れ、Claude Code の
  # パースが崩れる。ESC の escape なら AI 生成タイトルからの ANSI 注入になる。`\"`/`\\` の 2 つだけを
  # 扱うのは「7 つのうち 2 つ」ではなく **decode してよい上限**（JSON は非 ASCII を escape しないので
  # 日本語は生で来る）。将来 `//` を足して「完成」させると全緑のまま行数契約を破るのでここで pin する。
  # needle は **ASCII エスケープから組み立てる** — 生の ESC をソースに置くと Write/Edit で化ける
  # (US 区切りと同じ方針。実際に一度混入させた)
  _needle="a\\nb\\u001b[31m"
  _peer_home "aaaaaaaa-1111-2222-3333-444444444444" "$_needle" "" ""
  result=$(_peer_json "aaaaaaaa-1111-2222-3333-444444444444" \
    | "${_peer_pre[@]}" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" 2>/dev/null)
  # 行数は**ちょうど 4** — `/tmp` は git リポではないので Line 3 は `no git` のプレースホルダ。
  # `-ge` にしないのが要点で、名前由来の改行が混ざって行が増えたら落ちる
  [[ "$(printf '%s' "$result" | grep -c .)" -eq 4 ]]
  # `\n` も ESC の escape も文字列のまま（実文字・実 ESC に化けていない）
  [[ "$result" == *"$_needle"* ]]
  # 実 ESC が名前経由で出力に現れていないこと（色コードは 1 行目に必ずあるので、
  # 名前の直後に ESC が来ていないかを見る）
  [[ "$result" != *"a"$'\033'* ]]
}

@test "宛名: nameSource が derived 以外の値でも出すこと" {
  # 値で絞らない — 上流が新しい `nameSource` 値を増やしても宛名が消えないこと。
  # 「非 derived = ユーザー由来 = 右上に出ている」という推論は bg セッションで外れた実績がある
  _peer_home "aaaaaaaa-1111-2222-3333-444444444444" "explicit-name-55" "" ',"nameSource":"custom"'
  result=$(_peer_json "aaaaaaaa-1111-2222-3333-444444444444" \
    | "${_peer_pre[@]}" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" 2>/dev/null | head -1)
  [[ "$result" == *" explicit-name-55"* ]]
}

@test "宛名: CLAUDE_CONFIG_DIR で切り替えた config dir から読むこと" {
  # docs (env-vars): 「All settings, session history, and plugins are stored under this path」。
  # `$HOME/.claude` をハードコードすると、別 config dir で走るセッション (複数アカウント併用や
  # 案件ごとの切り替え) で sessions が 1 件も見つからず**宛名が丸ごと消える**。
  # 実測: `CLAUDE_CONFIG_DIR=~/.claude-work` のセッションのファイルはそちらにしか無かった。
  # 偽 HOME 側には**別名のファイルを置いて**、そちらを読んでいたら落ちるようにする
  _peer_home "bbbbbbbb-9999-9999-9999-999999999999" "wrong-home-side"
  _alt="$BATS_TEST_TMPDIR/alt-config"
  mkdir -p "$_alt/sessions"
  printf '{"pid":777,"sessionId":"aaaaaaaa-1111-2222-3333-444444444444","cwd":"/tmp","kind":"bg","name":"alt-config-session"}' \
    > "$_alt/sessions/777.json"
  result=$(_peer_json "aaaaaaaa-1111-2222-3333-444444444444" \
    | "${_peer_pre[@]}" "CLAUDE_CONFIG_DIR=$_alt" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" 2>/dev/null | head -1)
  [[ "$result" == *" alt-config-session"* ]]
  [[ "$result" != *"wrong-home-side"* ]]
}

@test "宛名: formerNames の過去の名前を宛名として出さないこと" {
  # 2.1.235 実測: `/rename` 済みセッションのファイルは `"formerNames":[{"name":…,"until":…},…]` を持つ。
  # つまり **`name` キーを持つネストしたオブジェクトが実在する**ようになった（この機能の唯一の
  # 誤情報経路として警告していた形そのもの）。実物の並びは `name` → `formerNames` なので最短一致は
  # 正しい方を選ぶが、それは**並び順だけが支えの安全**。逆順で置いて「過去の名前を出さない」ことを pin する。
  _ph="$BATS_TEST_TMPDIR/peer-former"
  mkdir -p "$_ph/.claude/sessions"
  printf '{"pid":54642,"sessionId":"%s","cwd":"/tmp","formerNames":[{"name":"old-name-77","until":1787137476612}],"name":"current-name-88","status":"busy"}' \
    "aaaaaaaa-1111-2222-3333-444444444444" > "$_ph/.claude/sessions/54642.json"
  result=$(_peer_json "aaaaaaaa-1111-2222-3333-444444444444" \
    | env "HOME=$_ph" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" 2>/dev/null | head -1)
  # 逆順では宛名ごと落ちる（無表示 < 誤読）。**過去の名前を出さない**ことが本体の assert
  [[ "$result" != *"old-name-77"* ]]
  [[ "$result" == *"Test"* ]]   # 到達証跡 — 描画自体は続いている
}

@test "宛名: formerNames を持つ実物の並びでは今の名前を出すこと" {
  # 上のテストと対で見る — `formerNames` から先を捨てる処理が行き過ぎて、実物の並び
  # (`name` → `formerNames`) でも宛名が消えたら「常に無表示」で上のテストだけ緑になる
  _ph="$BATS_TEST_TMPDIR/peer-former-ok"
  mkdir -p "$_ph/.claude/sessions"
  printf '{"pid":54642,"sessionId":"%s","cwd":"/tmp","name":"current-name-88","formerNames":[{"name":"old-name-77","until":1787137476612}],"status":"busy"}' \
    "aaaaaaaa-1111-2222-3333-444444444444" > "$_ph/.claude/sessions/54642.json"
  result=$(_peer_json "aaaaaaaa-1111-2222-3333-444444444444" \
    | env "HOME=$_ph" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" 2>/dev/null | head -1)
  [[ "$result" == *" current-name-88"* ]]
  [[ "$result" != *"old-name-77"* ]]
}

@test "宛名: session_id が来ない旧 Claude Code では宛名を出さないこと" {
  # graceful degradation — フィールドが無い環境でも他の要素は出す。
  # 併せて「id 無しで sessions ファイルを漫然と読んで先頭の名前を出す」実装でないことを pin する
  _peer_home "aaaaaaaa-1111-2222-3333-444444444444" "should-not-appear-11"
  result=$(jq -nc '{model:{id:"test",display_name:"Test"},workspace:{current_dir:"/tmp"},context_window:{used_percentage:10}}' \
    | "${_peer_pre[@]}" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" 2>/dev/null | head -1)
  [[ "$result" != *"should-not-appear-11"* ]]
  [[ "$result" == *"Test"* ]]
}

# ============================================================================
# Worktree — stdin JSONからworktree情報を表示
# ============================================================================
@test "Worktree: worktreeセッションで🌲とfrom:元ブランチが表示されること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.84","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10},"worktree":{"name":"my-feature","branch":"worktree-my-feature","original_branch":"main"}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" == *"🌲"* ]]
  [[ "$result" == *"from:main"* ]]
}

@test "Worktree: workspace.git_worktreeがtrueのとき🌲が表示されること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.97","workspace":{"current_dir":"/tmp","git_worktree":true},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" == *"🌲"* ]]
}

@test "Worktree: worktree未使用時は🌲が表示されないこと" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.84","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" != *"🌲"* ]]
}

@test "Worktree: original_branchがないhookベースworktreeでも🌲だけ表示されること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.84","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10},"worktree":{"name":"hook-wt","path":"/tmp/wt"}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" == *"🌲"* ]]
  [[ "$result" != *"from:"* ]]
}

@test "Worktree: worktree.pathがある場合はcurrent_dirの代わりにworktreeパスが表示されること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.84","workspace":{"current_dir":"/home/user/original-repo","project_dir":""},"context_window":{"used_percentage":10},"worktree":{"name":"my-feature","path":"/home/user/worktree-dir","original_branch":"main"}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '2p')
  # worktree path should appear, not original repo path
  [[ "$result" == *"worktree-dir"* ]]
  [[ "$result" != *"original-repo"* ]]
}

@test "Worktree: .claude/worktrees配下のパスがリポroot+🌲worktree名に分割表示されること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.84","workspace":{"current_dir":"/home/user/myrepo","project_dir":""},"context_window":{"used_percentage":10},"worktree":{"name":"melody","path":"/home/user/myrepo/.claude/worktrees/melody","original_branch":"main"}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '2p')
  # 🌲 より左（パス本文とそのリンク URL）はリポ root まで — marker が現れない
  pre="${result%%🌲*}"
  [[ "$pre" == *"/home/user/myrepo"* ]]
  [[ "$pre" != *".claude/worktrees"* ]]
  # worktree 名は 🌲 直後に dim で表示
  [[ "$result" == *"🌲${DIM}"*"melody"* ]]
  [[ "$result" == *"from:main"* ]]
}

@test "Worktree: original_branchがHEAD(detached)でもfrom:HEADを表示すること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.84","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10},"worktree":{"name":"wt","original_branch":"HEAD"}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" == *"🌲"* ]]
  [[ "$result" == *"from:HEAD"* ]]
}

@test "Worktree: worktree配下のサブディレクトリでは分割せずフルパス表示されること" {
  # /cd で worktree 内サブディレクトリへ移動した git linked worktree — leaf に / が含まれるため分割しない
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.97","workspace":{"current_dir":"/home/user/myrepo/.claude/worktrees/melody/src","git_worktree":true},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '2p')
  # 🌲 が無いと ${result%%🌲*} は全文になり vacuous pass するので、先に 🌲 の存在を assert する
  [[ "$result" == *"🌲"* ]]
  pre="${result%%🌲*}"
  [[ "$pre" == *".claude/worktrees/melody/src"* ]]
}

# ============================================================================
# エラー耐性 — 不正入力でもクラッシュしないこと
# ============================================================================
@test "エラー耐性: 壊れたJSONでjq errorを表示してexit 0すること" {
  result=$(echo 'NOT_JSON' | /bin/bash statusline-command.sh 2>/dev/null)
  [[ "$result" == *"jq error"* ]]
}

@test "エラー耐性: braille_barが非数値で空バーを返すこと" {
  braille_bar "abc" result
  [[ "$result" == "     " ]]
}

@test "エラー耐性: format_tokensが非数値で?を返すこと" {
  format_tokens "bad" result
  [[ "$result" == "?" ]]
}

@test "エラー耐性: color_by_thresholdが非数値でDIMを返すこと" {
  color_by_threshold "xyz" 90 80 result
  [[ "$result" == "$DIM" ]]
}

# ============================================================================
# Opus 4.7 — モデル検出
# ============================================================================
@test "モデル色: Opus 4.7がコーラルで表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-7","display_name":"Opus 4.7"},"version":"2.1.112","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"38;5;173"*"Opus 4.7"* ]]
}

@test "モデル色: Opus 4.7 は括弧を剥がしてコーラルで表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-7","display_name":"Opus 4.7 (1M context)"},"version":"2.1.220","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"38;5;173"*"Opus 4.7"* ]]
  [[ "$result" != *"1M context"* ]]
}

# ============================================================================
# 統合テスト: 全体 — 正常に動作すること
# ============================================================================
@test "全体: exit code 0で終了すること" {
  echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null
}

@test "全体: コンテキストバーにパーセンテージが表示されること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" == *"48%"* ]]
}

# ============================================================================
# 版 — 最新版から遅れている間だけアラーム色で立てること
# ============================================================================
# `_ver_run VERSION LATEST` — 偽 config dir に「最新は LATEST」の changelog を置いて Line 1 を出す。
# LATEST を空にすると changelog 自体を置かない (読めないケース)。色を見るので ANSI は剥がさない。
_ver_run() {
  local _cd="$BATS_TEST_TMPDIR/cfg-$1-$2"
  mkdir -p "$_cd/cache"
  [[ -n "$2" ]] && printf '# Changelog\n\n## %s\n\n- x\n' "$2" > "$_cd/cache/changelog.md"
  printf '%s' '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"'"$1"'","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | CLAUDE_CONFIG_DIR="$_cd" /bin/bash statusline-command.sh 2>/dev/null | sed -n '1p'
}

@test "版: 最新版と同じなら弱め表示のままであること" {
  # 色は**生のリテラル**で assert する (定数で書くとどんな値でも通り、無断の再調整を検出できない)
  local result
  result=$(_ver_run 2.1.240 2.1.240)
  [[ "$result" == *'38;5;248m'*"v2.1.240"* ]]
  [[ "$result" != *$'\033[31m'* ]]
}

@test "版: 最新版から遅れているとアラーム色(赤)で立つこと" {
  # 最新は Claude Code 自身が置く changelog キャッシュの冒頭 `## X.Y.Z` から読む
  # (ネットワークもキャッシュ書き込みも fork もゼロ)
  local result
  result=$(_ver_run 2.1.232 2.1.240)
  # アラーム色 = 既存の赤 (ANSI 31)。**生のリテラル**で assert する
  [[ "$result" == *$'\033[31m'"v2.1.232"* ]]
}

@test "版: 最新版が読めないときは立てずに弱め表示に落ちること" {
  # changelog は未文書の内部ファイルなので、無ければ黙って dim (無表示 < 誤読させる表示)
  local result
  result=$(_ver_run 2.1.232 "")
  [[ "$result" == *'38;5;248m'*"v2.1.232"* ]]
  [[ "$result" != *$'\033[31m'* ]]
}

@test "版: 何も書き込まないこと(状態を持たない)" {
  # 前の実装は「前回見た版」をキャッシュに書いていた。今は今の版と最新版だけで決まるので
  # 書き込みが 1 つも無い = 並走ペインの競合も無い。
  # **キャッシュ一覧の前後比較で見る** — 特定のファイル名を grep する形は、その名前を作る
  # コードが無くなった時点で「どう壊しても緑」になる (`/simplify` 指摘)
  # 版だけ違う 2 回の描画でキャッシュの中身（一覧）が変わらない = 版のための書き込みが無い。
  # 描画自体は他のキャッシュ（git 等）を書きうるので、**版を変えても増えないこと**で見る
  mkdir -p "$CLAUDE_STATUSLINE_CACHE_DIR"
  local a b
  _ver_run 2.1.232 2.1.240 >/dev/null
  a=$(ls -1 "$CLAUDE_STATUSLINE_CACHE_DIR" 2>/dev/null)
  _ver_run 2.1.240 2.1.240 >/dev/null
  b=$(ls -1 "$CLAUDE_STATUSLINE_CACHE_DIR" 2>/dev/null)
  [[ "$a" == "$b" ]]
}

@test "ver_older: 版を数値として比較すること(文字列比較では逆になる)" {
  # `2.1.9` と `2.1.10` は辞書順だと大小が逆になる
  ver_older 2.1.9 2.1.10
  ! ver_older 2.1.10 2.1.9
  ver_older 2.0.999 2.1.0
  ! ver_older 2.1.240 2.1.240
  ! ver_older 2.1.241 2.1.240
  # 成分が足りない側は 0 扱い (`2.1` == `2.1.0`)
  ! ver_older 2.1 2.1.0
}

@test "ver_older: ゼロ埋めの成分でも 8 進数エラーを出さないこと" {
  # `2.1.08` を `((08 < 10))` に渡すと `value too great for base` が stderr に漏れる
  # (regex `^[0-9]+$` は `08` を通すので防げない)。`10#` で明示基数にする (`/code-review` 指摘)。
  local err
  err=$( { ver_older 2.1.08 2.1.10 && echo OLDER; } 2>&1 >/dev/null )
  [[ -z "$err" ]] || { echo "stderr: $err" >&3; false; }
  ver_older 2.1.08 2.1.10          # 08 < 10 として正しく比較される
  ! ver_older 2.1.10 2.1.08
}

@test "ver_older: 数値でない成分や空では古いと判定しないこと" {
  # 上流が `2.2.0-rc.1` のような形を出したときに誤って立てるより、無表示に落ちる側へ倒す
  ! ver_older "2.2.0-rc.1" 2.2.1
  ! ver_older "" 2.1.240
  ! ver_older 2.1.240 ""
  ! ver_older "abc" "def"
}

# ============================================================================
# output style — 常に出し、default だけ dim にすること
# ============================================================================
_os_run() {
  printf '%s' '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.240","workspace":{"current_dir":"/tmp"},"output_style":{"name":"'"$1"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '1p'
}

@test "output style: default 以外の名前を Line 1 に出すこと" {
  local result
  result=$(_os_run "explanatory")
  [[ "$result" == *'38;5;231m'"explanatory"* ]]
  # **Agent 名のピンク (213) と被らないこと** — 最初この色にして実機で見分けが付かなかった
  [[ "$result" != *'38;5;213m'"explanatory"* ]]
  [[ "$result" != *'38;5;176m'"explanatory"* ]]
}

@test "output style: default でも出すこと(ただし dim)" {
  # v1.76.0 でユーザー選択: 「default のときも default と出してほしい」。
  # 既定値は「特に設定していない」を示すプレースホルダ側なので dim（`no git` と同じ扱い）で、
  # 非既定の白 231 との差で「違う」が読める
  local result
  result=$(_os_run "default")
  [[ "$result" == *$'\033[2m'"default"* ]]
  [[ "$result" != *'38;5;231m'"default"* ]]
}

@test "output style: フィールドが無い旧 Claude Code では出さないこと" {
  # `// ""` の既定値で空になるだけ (graceful degradation)
  local result
  result=$(printf '%s' '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.240","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '1p')
  [[ -n "$result" ]]
  [[ "$result" == *"v2.1.240"* ]]
}

# ============================================================================
# 端末幅非依存 — 幅に関係なく4行かつexit 0で完走すること
# ============================================================================
@test "全体: COLUMNS=40でもバージョンは常時表示されること" {
  result=$(COLUMNS=40 /bin/bash -c 'echo "{\"model\":{\"id\":\"claude-opus-4-6\",\"display_name\":\"Opus 4.6\"},\"version\":\"2.1.80\",\"workspace\":{\"current_dir\":\"/tmp\"},\"context_window\":{\"used_percentage\":48}}" | /bin/bash statusline-command.sh 2>/dev/null | head -1')
  [[ "$result" == *"v2.1.80"* ]]
}

@test "全体: COLUMNS=40でも4行出力されること" {
  result=$(COLUMNS=40 /bin/bash -c 'echo "{\"model\":{\"id\":\"test\",\"display_name\":\"Test\"},\"version\":\"2.1.76\",\"workspace\":{\"current_dir\":\"/tmp\"},\"context_window\":{\"used_percentage\":10}}" | /bin/bash statusline-command.sh 2>/dev/null')
  status=$?
  [[ "$status" -eq 0 ]]
  line_count=$(echo "$result" | grep -c . || echo 0)
  [[ "$line_count" -eq 4 ]]
}

@test "全体: COLUMNS=30でもモデル名がフルで表示されること" {
  result=$(COLUMNS=30 /bin/bash -c 'echo "{\"model\":{\"id\":\"claude-opus-4-6\",\"display_name\":\"Opus 4.6\"},\"version\":\"2.1.80\",\"workspace\":{\"current_dir\":\"/tmp\"},\"context_window\":{\"used_percentage\":48}}" | /bin/bash statusline-command.sh 2>/dev/null | head -1')
  [[ "$result" == *"Opus 4.6"* ]]
}

# ============================================================================
# added_dirs — /add-dirで追加されたディレクトリの表示
# ============================================================================
@test "added_dirs: 追加ディレクトリ数を(+N dirs)で集約表示すること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.78","workspace":{"current_dir":"/tmp","added_dirs":["/tmp/foo","/Users/me/bar"]},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" == *"(+2 dirs)"* ]]
}

@test "added_dirs: 追加ディレクトリがないとき(+N dirs)は表示されないこと" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.78","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" != *"dirs"* ]]
}

@test "added_dirs: 空配列のとき(+N dirs)は表示されないこと" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.78","workspace":{"current_dir":"/tmp","added_dirs":[]},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" != *"dirs"* ]]
}

# ============================================================================
# パス表示 — current_dir を表示し project_dir には依存しないこと
# ============================================================================
@test "パス表示: current_dirとproject_dirが異なるときcurrent_dirを表示すること" {
  # /cd 後など current_dir != project_dir のとき、launch 時の project_dir ではなく
  # 現在地 current_dir を表示する (v1.32.0 で project_dir 優先をやめた)
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"/tmp/moved-here","project_dir":"/tmp/launched-here"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" == *"/tmp/moved-here"* ]]
  [[ "$result" != *"launched-here"* ]]
}

# ============================================================================
# Line 4順番 — 5h limit, context, weekly の順であること
# ============================================================================
@test "行分割: セッションが4行目・制限が5行目に分かれること" {
  # スコープで行を割る (v1.74.0)。1 行に混ぜていた頃は「どこまでが制限の話で、どこからが
  # このセッションの話か」が読めなかった。**同じ行に混在しないこと**を pin する —
  # これが崩れると、以前のように弱め表示の時間が並んで属し先が消える症状に戻る。
  out=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.80","workspace":{"current_dir":"/tmp"},"cost":{"total_duration_ms":7200000,"total_cost_usd":1.5},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":4070908800},"seven_day":{"used_percentage":12,"resets_at":4071427200}}}' \
    | /bin/bash statusline-command.sh 2>/dev/null)
  sess=$(printf '%s' "$out" | sed -n '4p')
  lim=$(printf '%s' "$out" | sed -n '5p')
  # セッション行: context / 経過 / コスト
  [[ "$sess" == *"48%"* ]]
  [[ "$sess" == *"2h"* ]]
  [[ "$sess" == *'$1.50'* ]]
  # 制限行: 5h / week
  [[ "$lim" == *"35%"* ]]
  [[ "$lim" == *"week:12%"* ]]
  # **混在しないこと** — 制限行に context/経過/コストが無く、セッション行に制限が無い
  [[ "$lim" != *"48%"* ]]
  [[ "$lim" != *'$1.50'* ]]
  [[ "$sess" != *"week:"* ]]
  [[ "$sess" != *"35%"* ]]
}

@test "行分割: 制限行の順序が 5h → week → モデル別枠 であること" {
  # 「% → リセット」の並びが繰り返されるので、リセット時刻がどの制限のものか対比で読める。
  mkdir -p $CLAUDE_STATUSLINE_CACHE_DIR
  printf 'cents,limits\0370\nFable\03739\037Sat 16:00' > $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.80","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":4070908800},"seven_day":{"used_percentage":12,"resets_at":4071427200}}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '5p' | _strip)
  rm -f $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  five_pos="${result%%35%*}"
  week_pos="${result%%week:*}"
  scoped_pos="${result%%Fable*}"
  [[ ${#five_pos} -lt ${#week_pos} ]]
  [[ ${#week_pos} -lt ${#scoped_pos} ]]
}

# ============================================================================
# OSC 8リンク — file://でクリック可能であること
# ============================================================================
@test "OSC8: パスがfile://リンクとして生成されること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" == *"file:///tmp"* ]]
}

@test "端末幅: 長いパスがCOLUMNS=50でも省略されないこと" {
  result=$(COLUMNS=50 /bin/bash -c 'echo "{\"model\":{\"id\":\"test\",\"display_name\":\"Test\"},\"version\":\"2.1.76\",\"workspace\":{\"current_dir\":\"/Users/user/very/long/path/to/some/deep/project\"},\"context_window\":{\"used_percentage\":10}}" | /bin/bash statusline-command.sh 2>/dev/null | sed -n "2p"')
  [[ "$result" != *"…"* ]]
}

# ============================================================================
# Subagent statusline — subagent-statusline-command.sh (agent panel の行描画, v1.51.0 デザイン)
#   行 = 説明 + モデル(pretty・tier色) + [effort] + [status語] + [🌲wt]
#   (v1.51.0 で context%/経過を撤去、v1.61.0 で effort を追加)。
#   「実行中」表示は Claude Code 側 chrome に委ね、独自グリフ(↑/▪/✓)は出さない。
# ============================================================================
@test "Subagent: id付きJSON行が説明先頭+モデルpretty(tier色)だけになること" {
  result=$(echo '{"columns":120,"tasks":[{"id":"t1","label":"reviewing the diff","model":"claude-opus-4-8[1m]","status":"running","tokenCount":40000,"contextWindowSize":200000}]}' \
    | /bin/bash subagent-statusline-command.sh)
  [[ "$(echo "$result" | jq -r .id)" == "t1" ]]
  local c; c=$(echo "$result" | jq -r .content)
  [[ "$c" == *"reviewing the diff"* ]]
  [[ "$c" == *$'\033[38;5;173m'"Opus 4.8"* ]]   # pretty-name + coral
  # context% と braille バーは撤去済み (並走 subagent で差が出ず判断に効かなかった)
  [[ "$c" != *"20%"* ]]; [[ "$c" != *"⣀"* ]]; [[ "$c" != *"⣤"* ]]
}

@test "Subagent: ⚡や独自の実行中グリフ(↑/▪/✓)を出さないこと(CC の chrome に委ねる)" {
  c=$(echo '{"columns":120,"tasks":[{"id":"t","label":"x","model":"claude-opus-4-8","status":"running","tokenCount":1,"contextWindowSize":200000,"tokenSamples":[1,2,9]}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content)
  [[ "$c" != *"⚡"* ]]; [[ "$c" != *"↑"* ]]; [[ "$c" != *"▪"* ]]; [[ "$c" != *"✓"* ]]
}

@test "Subagent: Bedrock inference-profile id(jp.anthropic.claude-opus-4-8)がOpus 4.8になること" {
  c=$(echo '{"columns":120,"tasks":[{"id":"t","label":"x","model":"jp.anthropic.claude-opus-4-8"}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content)
  [[ "$c" == *$'\033[38;5;173m'"Opus 4.8"* ]]   # prefix 剥がして pretty + coral
  [[ "$c" != *"anthropic"* ]]
}

@test "Subagent: 旧形式 model id(claude-3-5-sonnet-…)を文字化けさせないこと" {
  c=$(echo '{"columns":120,"tasks":[{"id":"a","label":"x","model":"claude-3-5-sonnet-20241022"}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content)
  [[ "$c" == *"3-5-sonnet-20241022"* ]]   # cleaned id のまま
  [[ "$c" != *"3 5.sonnet"* ]]
}

@test "Subagent: effortはレベル文字列をレベル毎の色でモデルの直後に出すこと" {
  # 位置まで pin する — 部分一致だけだと effort の add を status/worktree の後ろに動かしても緑のままで、
  # docs の「モデル → effort → 状態 → 🌲」の順序が固定されない
  c=$(echo '{"columns":120,"tasks":[{"id":"t","label":"x","model":"claude-sonnet-4-6","effort":"low","status":"needs_input","cwd":"/r/.claude/worktrees/wt"}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content | _strip)
  [[ "$c" == "x  Sonnet 4.6  low  needs_input  🌲wt" ]]
  # 色は Line 1 の effort と同じ light purple
  c2=$(echo '{"columns":120,"tasks":[{"id":"t","label":"x","model":"claude-sonnet-4-6","effort":"low"}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content)
  [[ "$c2" == *$'\033[38;5;178m'"low"* ]]   # low = gold (effort ランプ)
}

@test "Subagent: effortのゼロ埋め数値を8進数と誤解釈しないこと" {
  # ((08)) は bash で "value too great for base" になり 0 が出る → 10# で明示基数にする
  c=$(echo '{"columns":120,"tasks":[{"id":"t","label":"x","model":"claude-sonnet-4-6","effort":"08000"}]}' \
    | /bin/bash subagent-statusline-command.sh 2>/dev/null | jq -r .content)
  [[ "$c" == *"8k"* ]]
  [[ "$c" != *"0k"[^0-9]* ]]
}

@test "Subagent: effortだけの行は既定描画に委ねること(row を非空にしない)" {
  # 説明も名前もモデルも無い task で effort だけ出すと「effort 語だけの行」になり、
  # Claude Code 既定の「名前 · 説明 · トークン数」より情報が減る
  out=$(echo '{"columns":120,"tasks":[{"id":"d","effort":"medium"}]}' \
    | /bin/bash subagent-statusline-command.sh)
  [[ -z "$out" ]]
}

@test "Subagent: effortの数値トークン予算は k 表記に畳むこと" {
  c=$(echo '{"columns":120,"tasks":[{"id":"t","label":"x","model":"claude-opus-5","effort":8000}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content)
  [[ "$c" == *$'\033[38;5;105m'"8k"* ]]    # docs: 値はレベル文字列か数値のトークン予算
  [[ "$c" != *"8000"* ]]
}

@test "Subagent: effortはセッション継承時(absent)には出さないこと" {
  # 継承時 absent = 出るのは「この subagent だけ effort が違う」時だけ (差分シグナル)
  c=$(echo '{"columns":120,"tasks":[{"id":"t","label":"x","model":"claude-opus-5"}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content)
  [[ "$c" != *"38;5;105"* ]]
  # Opus 5 は gradient で 1 文字ずつ着色されるのでリテラル一致には ANSI 剥がしが要る
  [[ "$(printf '%s' "$c" | _strip)" == *"Opus 5"* ]]   # モデルは出たまま
}

@test "Subagent: effortが非スカラーなら出さず全行も消えないこと(型ガード)" {
  # 全 task を 1 個の jq で処理するので 1 task の型不正で abort すると全行が既定描画に戻る。
  # 型ガードで非スカラーは空に倒す — 生 JSON を行に出さない (出すと "Sonnet 4.6" 一致では気付けない)
  _c() { echo "{\"columns\":120,\"tasks\":[{\"id\":\"t\",\"label\":\"x\",\"model\":\"claude-sonnet-4-6\",\"effort\":$1}]}" \
    | /bin/bash subagent-statusline-command.sh | jq -r .content; }
  for bad in '["a","b"]' 'true' 'false'; do
    c=$(_c "$bad")
    [[ "$c" == *"Sonnet 4.6"* ]]     # 行は生きている
    [[ "$c" != *"38;5;105"* ]]       # effort 区間は出ていない
    # 生 JSON が漏れていないこと。ANSI 自体が "[" を含むので剥がしてから見る
    plain=$(printf '%s' "$c" | _strip)
    [[ "$plain" == "x  Sonnet 4.6" ]]
  done
  # ネストした {"level":..} 形で来ても level を拾う (主 statusline の effort.level と同形)
  c=$(_c '{"level":"low"}')
  [[ "$c" == *$'\033[38;5;178m'"low"* ]]   # low = gold (effort ランプ)
  [[ "$c" != *'{'* ]]
}

@test "Subagent: 未知status(入力待ち等)は黄で生の値を表示すること" {
  c=$(echo '{"columns":120,"tasks":[{"id":"t","label":"x","status":"needs_input"}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content)
  [[ "$c" == *$'\033[33m'"needs_input"* ]]
}

@test "Subagent: running/completed どちらも経過時間を出さないこと" {
  now=$(date +%s); st=$(( (now - 7200) * 1000 ))
  for s in completed running; do
    c=$(echo '{"columns":120,"tasks":[{"id":"c","label":"x","status":"'"$s"'","startTime":'"$st"'}]}' \
      | /bin/bash subagent-statusline-command.sh | jq -r .content)
    # 経過は撤去済み。行本文は説明だけ (実行中表示は CC ネイティブの ○/スピナーに委ねる)
    [[ "$c" == "x" ]]
  done
}

@test "Subagent: モデル pretty-name と tier 色(Sonnet 4.5=amber / Fable=rainbow / Opus 5=卵スイープ)" {
  s45=$(echo '{"columns":120,"tasks":[{"id":"t","label":"x","model":"claude-sonnet-4-5"}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content)
  [[ "$s45" == *$'\033[38;5;214m'"Sonnet 4.5"* ]]
  fab=$(echo '{"columns":120,"tasks":[{"id":"t","label":"x","model":"claude-fable-5"}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content)
  [[ "$fab" == *$'\033[38;5;178m'"F"* ]]
  # id 形式 "claude-opus-5[1m]" → "Opus 5" に整形の上で卵パレットのスイープ (coral 起点)
  o5=$(echo '{"columns":120,"tasks":[{"id":"t","label":"x","model":"claude-opus-5[1m]"}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content)
  [[ "$o5" == *$'\033[38;5;130m'"O"* ]]; [[ "$o5" == *$'\033[38;5;215m'"5"* ]]
  # 同 tier の旧版は flat coral のまま (誤マッチ防止)
  o48=$(echo '{"columns":120,"tasks":[{"id":"t","label":"x","model":"claude-opus-4-8"}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content)
  [[ "$o48" == *$'\033[38;5;173m'"Opus 4.8"* ]]
}

@test "Subagent: cwdが.claude/worktrees配下のとき🌲名を出すこと(Line2と協調)" {
  c=$(echo '{"columns":120,"tasks":[{"id":"t","label":"x","cwd":"/Users/u/repo/.claude/worktrees/fix-bug/src"}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content)
  [[ "$c" == *"🌲fix-bug"* ]]
}

@test "Subagent: labelがnameより優先されること" {
  c=$(echo '{"columns":120,"tasks":[{"id":"t4","name":"raw-name","label":"Pretty Label"}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content)
  [[ "$c" == *"Pretty Label"* ]]; [[ "$c" != *"raw-name"* ]]
}

@test "Subagent: 旧CC(model/status/ctx/startTime欠落)でも説明を出しバーは出さないこと" {
  c=$(echo '{"columns":120,"tasks":[{"id":"t3","name":"agent-x","description":"doing work"}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content)
  [[ "$c" == *"doing work"* ]]; [[ "$c" != *"%"* ]]
}

@test "Subagent: 未使用/型不正フィールドが混ざっても全行が出力されること(jq abort 回帰)" {
  ids=$(echo '{"columns":120,"tasks":[{"id":"good","label":"ok"},{"id":"bad","label":"y","tokenSamples":5}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -rc .id | sort | tr '\n' ',')
  [[ "$ids" == "bad,good," ]]
}

@test "Subagent: label 空でも content 先頭に空白が付かないこと" {
  c=$(echo '{"columns":120,"tasks":[{"id":"e","label":"","model":"claude-opus-4-8","tokenCount":1,"contextWindowSize":200000}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content)
  [[ "$c" != " "* ]]
}

@test "Subagent: tasksが空/idなしなら何も出力しないこと" {
  [[ -z "$(echo '{"columns":120,"tasks":[]}' | /bin/bash subagent-statusline-command.sh)" ]]
  [[ -z "$(echo '{"columns":120,"tasks":[{"label":"noid"}]}' | /bin/bash subagent-statusline-command.sh)" ]]
}

@test "Subagent: 空入力/tasks欠落/不正JSONでもクラッシュせずexit 0すること" {
  echo '' | /bin/bash subagent-statusline-command.sh; [[ $? -eq 0 ]]
  echo '{}' | /bin/bash subagent-statusline-command.sh; [[ $? -eq 0 ]]
  echo 'not json' | /bin/bash subagent-statusline-command.sh; [[ $? -eq 0 ]]
}

# ============================================================================
# install.sh — ユーザーの入口なので登録結果を pin する
# ============================================================================
@test "install: settings.json が無ければ作って絶対パスで両statuslineを登録すること" {
  s="$BATS_TEST_TMPDIR/new/settings.json"
  # `CLAUDE_CONFIG_DIR` も同時に渡して**罠**にする — `CLAUDE_SETTINGS` の明示指定が
  # 外側の既定であり続けることを、起動を増やさずに pin する（優先が入れ替わると罠側に書かれる）
  local trap_="$BATS_TEST_TMPDIR/trapcfg"
  CLAUDE_SETTINGS="$s" CLAUDE_CONFIG_DIR="$trap_" /bin/bash "$BATS_TEST_DIRNAME/install.sh" --yes >/dev/null
  [[ ! -e "$trap_/settings.json" ]]
  [[ "$(jq -r .statusLine.command "$s")" == "/bin/bash $BATS_TEST_DIRNAME/statusline-command.sh" ]]
  [[ "$(jq -r .subagentStatusLine.command "$s")" == "/bin/bash $BATS_TEST_DIRNAME/subagent-statusline-command.sh" ]]
  # 未設定なら推奨値が入る
  [[ "$(jq -r .statusLine.refreshInterval "$s")" == "30" ]]
  [[ "$(jq -r .statusLine.hideVimModeIndicator "$s")" == "true" ]]
}

@test "install: CLAUDE_CONFIG_DIR を既定の書き込み先にすること" {
  # ハードコードすると、この変数を使っている人は**登録は成功したのに statusline が出ず、
  # 理由も出ない**状態になる（Claude Code が別の settings.json を読むため）。
  # `CLAUDE_SETTINGS` の優先は下の `install: settings.json が無ければ…` が罠ディレクトリで見る。
  # 偽 HOME 側に作られない assert が要点 — 書き先を間違えても「ファイルはできた」で緑になりうる
  local cd_="$BATS_TEST_TMPDIR/altcfg" home_="$BATS_TEST_TMPDIR/althome"
  mkdir -p "$home_/.claude"          # `$cd_` は install.sh 自身が作る
  env "HOME=$home_" "CLAUDE_CONFIG_DIR=$cd_" /bin/bash "$BATS_TEST_DIRNAME/install.sh" --yes >/dev/null
  [[ "$(jq -r .statusLine.command "$cd_/settings.json")" == "/bin/bash $BATS_TEST_DIRNAME/statusline-command.sh" ]]
  [[ ! -e "$home_/.claude/settings.json" ]]
}

@test "install: 既存の他キーとユーザー設定値を壊さないこと(.bakも残る)" {
  s="$BATS_TEST_TMPDIR/settings.json"
  printf '%s' '{"model":"opus","statusLine":{"command":"/old.sh","padding":2,"refreshInterval":5},"permissions":{"defaultMode":"auto"}}' > "$s"
  CLAUDE_SETTINGS="$s" /bin/bash "$BATS_TEST_DIRNAME/install.sh" --yes >/dev/null
  [[ "$(jq -r .model "$s")" == "opus" ]]                          # 無関係キーは温存
  [[ "$(jq -r .permissions.defaultMode "$s")" == "auto" ]]
  [[ "$(jq -r .statusLine.padding "$s")" == "2" ]]                # statusLine 内の他キーも温存
  [[ "$(jq -r .statusLine.refreshInterval "$s")" == "5" ]]        # ユーザーが決めた値を上書きしない
  [[ "$(jq -r .statusLine.command "$s")" == *"statusline-command.sh" ]]
  [[ -n "$(echo "$s".bak.*)" ]] && [[ -f $(echo "$s".bak.*) ]]
}

@test "install: --main-only ならsubagentStatusLineを触らないこと" {
  s="$BATS_TEST_TMPDIR/main-only.json"
  echo '{}' > "$s"
  CLAUDE_SETTINGS="$s" /bin/bash "$BATS_TEST_DIRNAME/install.sh" --yes --main-only >/dev/null
  [[ "$(jq -r '.subagentStatusLine // "absent"' "$s")" == "absent" ]]
}

@test "install: 不正JSONのsettings.jsonは書き換えず非0で止まること" {
  s="$BATS_TEST_TMPDIR/broken.json"
  echo '{ oops' > "$s"
  run env CLAUDE_SETTINGS="$s" /bin/bash "$BATS_TEST_DIRNAME/install.sh" --yes
  [[ "$status" -ne 0 ]]
  [[ "$(cat "$s")" == '{ oops' ]]
}

@test "install: --dry-run と非対話(--yes無し)はファイルを書き換えないこと" {
  s="$BATS_TEST_TMPDIR/safe.json"
  orig='{"statusLine":{"command":"/other/tool.sh"}}'
  printf '%s' "$orig" > "$s"
  CLAUDE_SETTINGS="$s" /bin/bash "$BATS_TEST_DIRNAME/install.sh" --dry-run >/dev/null
  [[ "$(cat "$s")" == "$orig" ]]
  # 非対話 (stdin が tty でない) では --yes 無しは中止する — 確認を飛ばして書かない
  run env CLAUDE_SETTINGS="$s" /bin/bash "$BATS_TEST_DIRNAME/install.sh" </dev/null
  [[ "$status" -ne 0 ]]
  [[ "$(cat "$s")" == "$orig" ]]
}

@test "install: --dry-run が settings.json もその親ディレクトリも作らないこと" {
  # 「差分を見せるまで一切書かない」は --dry-run 自身にも掛かる。以前は未初期化のときに
  # 親ディレクトリと `{}` を作ってから「書き込みませんでした」と表示していた
  s="$BATS_TEST_TMPDIR/nodir/fresh.json"
  run env CLAUDE_SETTINGS="$s" /bin/bash "$BATS_TEST_DIRNAME/install.sh" --dry-run
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"statusLine"* ]]   # 差分は出ていること (何もせず抜けたのではない)
  [[ ! -e "$s" ]]
  [[ ! -d "$BATS_TEST_TMPDIR/nodir" ]]
}

@test "install: 2回実行しても最初のバックアップを潰さないこと" {
  s="$BATS_TEST_TMPDIR/twice.json"
  printf '%s' '{"keep":"ORIGINAL"}' > "$s"
  CLAUDE_SETTINGS="$s" /bin/bash "$BATS_TEST_DIRNAME/install.sh" --yes >/dev/null
  # 2 回目は変更なしなのでバックアップも増えない (冪等)
  run env CLAUDE_SETTINGS="$s" /bin/bash "$BATS_TEST_DIRNAME/install.sh" --yes
  [[ "$output" == *"既に登録済み"* ]]
  # 最初のバックアップに元の内容が残っている (.bak 固定名なら 2 回目で潰れていた)
  local b; b=$(echo "$s".bak.*)
  [[ "$(jq -r .keep "$b")" == "ORIGINAL" ]]
  [[ "$(jq -r '.statusLine // "absent"' "$b")" == "absent" ]]
}

@test "install: settings.jsonがsymlinkでもリンクを壊さず実体に書くこと" {
  real="$BATS_TEST_TMPDIR/dotfiles/settings.json"
  mkdir -p "${real%/*}"; printf '%s' '{"managed":"by-dotfiles"}' > "$real"
  link="$BATS_TEST_TMPDIR/link.json"; ln -sf "$real" "$link"
  CLAUDE_SETTINGS="$link" /bin/bash "$BATS_TEST_DIRNAME/install.sh" --yes >/dev/null
  [[ -L "$link" ]]                                        # リンクのまま
  [[ "$(jq -r .managed "$real")" == "by-dotfiles" ]]      # 実体が生きている
  [[ "$(jq -r .statusLine.type "$real")" == "command" ]]  # 実体に書けた
}

@test "install: slash無し起動(/bin/bash install.sh)でも動くこと" {
  s="$BATS_TEST_TMPDIR/slashless.json"
  ( cd "$BATS_TEST_DIRNAME" && CLAUDE_SETTINGS="$s" /bin/bash install.sh --yes >/dev/null )
  [[ "$(jq -r .statusLine.type "$s")" == "command" ]]
}

@test "install: 元のパーミッションと末尾改行を保つこと" {
  s="$BATS_TEST_TMPDIR/mode.json"
  echo '{}' > "$s"; chmod 600 "$s"
  CLAUDE_SETTINGS="$s" /bin/bash "$BATS_TEST_DIRNAME/install.sh" --yes >/dev/null
  [[ "$(stat -f '%Lp' "$s")" == "600" ]]        # settings.json は env の API キーを持ちうる
  # 末尾は改行で終わる ($() が末尾改行を落とすので空になる)。dotfiles の git diff を汚さないため
  [[ -z "$(tail -c 1 "$s")" ]]
}

@test "install: 空ファイルのsettings.jsonを初期化できること" {
  s="$BATS_TEST_TMPDIR/empty.json"; : > "$s"
  CLAUDE_SETTINGS="$s" /bin/bash "$BATS_TEST_DIRNAME/install.sh" --yes >/dev/null
  [[ "$(jq -r .statusLine.type "$s")" == "command" ]]
}

@test "install: 登録するスクリプトが欠けていたら書かずに止まること" {
  d="$BATS_TEST_TMPDIR/partial"; mkdir -p "$d"
  cp "$BATS_TEST_DIRNAME"/{statusline-command.sh,lib.sh,install.sh} "$d/"   # subagent 版だけ無い
  s="$BATS_TEST_TMPDIR/partial.json"
  run env CLAUDE_SETTINGS="$s" /bin/bash "$d/install.sh" --yes
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"subagent-statusline-command.sh"* ]]
  [[ ! -f "$s" ]]
  # --main-only なら subagent 版が無くても通る
  CLAUDE_SETTINGS="$s" /bin/bash "$d/install.sh" --yes --main-only >/dev/null
  [[ "$(jq -r '.subagentStatusLine // "absent"' "$s")" == "absent" ]]
}

@test "install: 空白やシェルメタ文字を含むパスでも登録し、シェル経由で実行できること" {
  # `command` はシェル経由で実行される。以前は空白を拒否し brace/glob は素通りさせていたため
  # 「試走は通るのに登録すると真っ白」になった。今は printf %q で引用するので全部通る。
  # `br{x,y}z` は引用が無いと 3 語に brace 展開され、bash が存在しないスクリプトを叩いて空白になる
  for name in "my repo" "Projects (old)" "br{x,y}z" "glob*dir"; do
    d="$BATS_TEST_TMPDIR/$name"; mkdir -p "$d"
    cp "$BATS_TEST_DIRNAME"/{statusline-command.sh,lib.sh,subagent-statusline-command.sh,install.sh} "$d/"
    s="$d/settings.json"; echo '{}' > "$s"
    CLAUDE_SETTINGS="$s" /bin/bash "$d/install.sh" --yes >/dev/null
    cmd=$(jq -r .statusLine.command "$s")
    # Claude Code と同じくシェル経由で起動して、実際に描画されること
    out=$(printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":5}}' \
      | CLAUDE_STATUSLINE_NO_NET=1 CLAUDE_STATUSLINE_CACHE_DIR="$d/cache" sh -c "$cmd" 2>/dev/null | head -1)
    [[ -n "$out" ]] || { echo "空白になった: $name / cmd=$cmd" >&3; return 1; }
  done
}

@test "install: 自分の ~ 形の登録を「別のツール」と誤警告しないこと" {
  # README の主経路は `~/.claude/statusline/...` を手で貼る形。$HOME 展開後で突き合わせないと
  # install.sh が自分自身の登録に対して「注意: 別のコマンドを指しています」を出す
  s="$BATS_TEST_TMPDIR/tilde.json"
  rel="${BATS_TEST_DIRNAME#$HOME/}"
  jq -nc --arg c "/bin/bash ~/$rel/statusline-command.sh" \
    '{statusLine:{type:"command",command:$c}}' > "$s"
  run env CLAUDE_SETTINGS="$s" /bin/bash "$BATS_TEST_DIRNAME/install.sh" --dry-run
  [[ "$output" != *"別のコマンドを指しています"* ]]
}

@test "install: 空パレットでも色ヘルパーが statusline を空白にしないこと" {
  # bash 3.2 の set -u は空配列の "${a[@]}" 展開で即死する → ${a[@]+"${a[@]}"} で degrade まで届くこと
  run /bin/bash -c 'set -uo pipefail; source "'"$BATS_TEST_DIRNAME"'/lib.sh"; E=(); gradient o "Opus 9" ${E[@]+"${E[@]}"}; printf "%s" "$o"'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "Opus 9" ]]
}

@test "Subagent: Bedrockの実id形(-v1:0)から版接尾辞を剥がすこと" {
  # モデル名は 1 文字ずつ着色されるので、色を落としてから語として突き合わせる
  c=$(echo '{"columns":120,"tasks":[{"id":"t","label":"x","model":"global.anthropic.claude-opus-5-v1:0"}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content | _strip)
  [[ "$c" == *"Opus 5"* ]]
  [[ "$c" != *"v1"* ]]; [[ "$c" != *":0"* ]]   # "Opus 5.v1:0" と出ていた退行を防ぐ
}

@test "bash3.2: line_gitが空(.gitはあるがHEAD読めない)でも空白にならず3行出ること" {
  # 親リポが消えた stale worktree。空配列の [*] 展開が set -u で即死し statusline 丸ごと空白になっていた
  d="$BATS_TEST_TMPDIR/stale-wt"; mkdir -p "$d"
  echo 'gitdir: /nonexistent/repo/.git/worktrees/gone' > "$d/.git"
  run /bin/bash -c 'printf "%s" "{\"model\":{\"id\":\"claude-opus-5\",\"display_name\":\"Opus 5\"},\"workspace\":{\"current_dir\":\"'"$d"'\"}}" | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"'
  [[ "$status" -eq 0 ]]
  [[ "$(printf '%s' "$output" | grep -c .)" -eq 3 ]]
  [[ "$output" == *"Opus 5"* ]] || [[ "$output" == *"O"* ]]
}

@test "bash3.2: 壊れたJSONでもjq errorを出してexit 0すること(空配列展開の即死回帰)" {
  run /bin/bash -c 'echo NOT_JSON | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"'
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"jq error"* ]]
}

@test "bash3.2: スクリプト起動が全て /bin/bash であること(制約を検証しないテストの混入を防ぐ)" {
  # PATH の `bash` は homebrew 5.x なので、`/bin/` を付けずにスクリプトを起動すると
  # このリポの最重要制約「bash 3.2 互換」を**一切検証しない**テストになる。
  # v1.51.0 まで 120 箇所超がこの形で、3.2 だけで即死するバグ 3 件が全緑のまま出荷された。
  # 判定は「`bash` の次の語が `.sh` を含む / `-c` / `"$` で始まる」= 起動している行だけ。
  # 散在する散文 (「bash 3.2 の set -u は…」「bash ${BASH_VERSION}」等) は次の語がどれにも
  # 当たらないので誤検出しない。`"$` を入れているのは install.sh の試走が
  # `/bin/bash "$repo/$1"` の形で、引数から `.sh` が見えないため。
  local bad
  bad=$(grep -noE '[^[:space:]]*bash[[:space:]]+("\$|[^[:space:]]*(\.sh|-c))[^[:space:]]*' \
          "$BATS_TEST_DIRNAME/test.bats" "$BATS_TEST_DIRNAME/install.sh" \
        | grep -v '/bin/bash ' || true)
  [ -z "$bad" ] || { printf 'PATH の bash で起動している箇所:\n%s\n' "$bad" >&2; false; }
}

@test "cache: 形式タグの定義と、タグ違いを使わない振る舞いテストが揃っていること" {
  # 形式を変えたのに旧キャッシュを読むと、**既存ユーザーだけが壊れる**（新規インストールでは
  # 正しいので気づけない）。v1.74.0 で 2 つ踏んだ。
  # **コードの形を grep するのはやめた** — 「読み側の比較が在るか」を grep で見ようとしたが、
  # 書き込み側や延命判定の参照にも当たってしまい、読み側の比較を消す mutation を検出できなかった
  # (`/code-review` 指摘)。**pin は振る舞いテスト側が持つ**ので、ここはその存在と、
  # タグ定数の定義／ファイル名に版が残っていないことだけを見る。
  local sl="$BATS_TEST_DIRNAME/statusline-command.sh" tb="$BATS_TEST_DIRNAME/test.bats" bad="" v t
  for v in GIT_FMT SUB_FMT USAGE_FMT RESET_FMT; do
    grep -qE "^readonly ${v}='" "$sl" || bad+="${v}(未定義) "
  done
  # 各キャッシュに「タグ違い/旧形式を使わない」テストが在ること（消したら赤くなる）
  for t in "Git facts: タグの違うキャッシュを使わず作り直すこと" \
           "plan: タグだけ違う subscription キャッシュを読まないこと" \
           "週間枠: タグの無いキャッシュ(旧形式)を使わないこと" \
           "週間枠: タグ不一致なら TTL を待たずに取り直すこと(アップグレード経路)"; do
    grep -qF "$t" "$tb" || bad+="振る舞いテスト欠落[$t] "
  done
  # ファイル名に版を持たせない（名前は安定させ、判定はタグに寄せる）
  grep -qE 'CACHE_BASE\}/[a-z_]+-v[0-9]+' "$sl" && bad+="ファイル名に版が残っている "
  [ -z "$bad" ] || { printf 'タグ方式の不備: %s\n' "$bad" >&2; false; }
}

@test "config dir: ~/.claude を直に書いた箇所が無いこと(CLAUDE_CONFIG_DIR の取りこぼし防止)" {
  # `CLAUDE_CONFIG_DIR` は設定ディレクトリ全体を移すので、`$HOME/.claude` をハードコードすると
  # その変数を使っている人の環境で**静かに動かなくなる** — sessions が見つからず宛名が消え、
  # credentials が読めず subscription と extra-usage が消え、install は書いても読まれない。
  # 3 箇所を 1 つずつ踏んでから直す形になったので、prose ではなく grep で強制する
  # (CLAUDE.md の記述は「新規コードを足さない」= forward-only で、既存のハードコードを拾えなかった)。
  # **コメント行は除外する** — 散文は `~/.claude/sessions/...` のように直接書くので、
  # `/bin/bash` メタテストの「隣の語で絞る」手が使えない。`path:行番号:` の後が `#` で
  # 始まる行を落とす (行末コメントだけの言及は拾ってしまうが、そこは実コードと同居する形なので許容)。
  # 許可するのは **top-level の `readonly` で `CLAUDE_*CONFIG_DIR:-` の既定値として書いた形だけ**。
  # 変数名では絞らない（`CLAUDE_SECURESTORAGE_CONFIG_DIR` も正当な env seam なので）が、**`readonly` を
  # 要求する**ことで「関数の中でインラインに展開し直す」複製を弾く。以前は `:-` の形だけを見ていたため、
  # `get_credentials_blob` の中に 2 つ目の展開が入っても緑だった（v1.83.0 のレビュー指摘）。
  local bad sl_bad inst_bad
  # 被験体 3 本には **`readonly` を要求する**（関数内のインライン展開を弾く）。
  sl_bad=$(grep -nE '(\$\{?HOME\}?|~)/\.claude' \
          "$BATS_TEST_DIRNAME/statusline-command.sh" "$BATS_TEST_DIRNAME/lib.sh" \
          "$BATS_TEST_DIRNAME/subagent-statusline-command.sh" \
        | grep -vE ':[0-9]+:[[:space:]]*#' \
        | grep -vE ':[0-9]+:[[:space:]]*readonly [A-Z_]+=.*CLAUDE_[A-Z_]*CONFIG_DIR:-' || true)
  # `install.sh` は settings のパスを組む都合で `readonly` にできない（usage 文と代入）ので
  # 従来どおり「`CLAUDE_*CONFIG_DIR:-` の既定値として書いてあること」だけを要求する。
  # **`-H` を必ず付ける** — 単一ファイルだと grep が `path:` を省き、下の `:行:#` フィルタが素通りする
  inst_bad=$(grep -nHE '(\$\{?HOME\}?|~)/\.claude' "$BATS_TEST_DIRNAME/install.sh" \
        | grep -vE ':[0-9]+:[[:space:]]*#' \
        | grep -vE 'CLAUDE_[A-Z_]*CONFIG_DIR:-' || true)
  bad="${sl_bad}${inst_bad}"
  [ -z "$bad" ] || {
    printf '~/.claude を直書きしている箇所 (${CLAUDE_CONFIG_DIR:-$HOME/.claude} を使うこと):\n%s\n' "$bad" >&2; false; }
}

@test "env seam: スクリプトが読む CLAUDE_* を setup で必ず落としていること" {
  # `unset` の列挙は放置すると腐る（このリポは拒否リストを嫌う方針）。スクリプト側が新しい
  # env seam を読み始めたら、それを setup で export か unset するまでここが赤くなるようにして
  # 列挙を自己保守にする。**偽の緑が本番の危険** — ambient な `CLAUDE_CODE_USE_BEDROCK` は
  # 「Bedrock では extra-usage を出さない」を検出が壊れていても通してしまう。
  local v missing=""
  for v in $(grep -hoE '\$\{?CLAUDE_[A-Z_]+' \
               "$BATS_TEST_DIRNAME/statusline-command.sh" "$BATS_TEST_DIRNAME/lib.sh" \
               "$BATS_TEST_DIRNAME/subagent-statusline-command.sh" \
             | tr -d '${' | sort -u); do
    grep -qE "(export|unset)[^#]*\b$v\b" "$BATS_TEST_DIRNAME/test.bats" || missing="$missing $v"
  done
  [ -z "$missing" ] || {
    printf 'setup() で export も unset もしていない env seam:%s\n' "$missing" >&2; false; }
}

# ============================================================================
# セッション経過時間 (cost.total_duration_ms) — Line 4
# ============================================================================
@test "fmt_elapsed: 単位が常に1つで m/h 帯は commit age と同表記になること" {
  # 完全一致で pin する — 部分一致 (*"1h"*) だと旧実装の "1h01m" も通ってしまう
  fmt_elapsed 90    r; [[ "$r" == "1m" ]]     # 1分30秒 → 秒は切り捨て
  fmt_elapsed 3599  r; [[ "$r" == "59m" ]]    # 境界の直下 — この変更の本体は s<3600 の 1 条件
  fmt_elapsed 3600  r; [[ "$r" == "1h" ]]     # 境界ちょうど ((s<=3600) だと 60m に化ける)
  fmt_elapsed 3660  r; [[ "$r" == "1h" ]]     # 1時間1分 → 時のみ (旧: 1h01m、H:MM でも 1:01 でない)
  fmt_elapsed 16200 r; [[ "$r" == "4h" ]]     # 4時間30分 → 分は落とす
  fmt_elapsed 97200 r; [[ "$r" == "27h" ]]    # 27時間 → 日には丸めない (commit age は 1d に丸めるのでここだけ分かれる)
  fmt_elapsed x     r; [[ "$r" == "" ]]       # 非数値は空 (呼び出し側で非表示に倒れる)
}

@test "経過時間: 60秒未満とフィールド欠落では出さないこと" {
  # ANSI の reset (\033[0m) が "0m"/"m" に当たるので色を剥がしてから語で判定する
  short=$(printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"cost":{"total_duration_ms":45000}}' \
    | /bin/bash statusline-command.sh | tail -1 | _strip)
  [[ "$short" != *"m"* ]]
  # 旧 Claude Code (cost.total_duration_ms 無し) — jq default 0 で非表示に倒れる
  none=$(printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"cost":{"total_cost_usd":1.5}}' \
    | /bin/bash statusline-command.sh | tail -1 | _strip)
  [[ "$none" == *'$1.50'* ]]; [[ "$none" != *"m"* ]]
}

@test "経過時間: コストの直前に置かれること(順序)" {
  l4=$(printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"cost":{"total_cost_usd":18.07,"total_duration_ms":12240000}}' \
    | /bin/bash statusline-command.sh | tail -1 | _strip)
  # 区切りごと pin する — *"3h"* だと 13h/23h/3h24m も通る緩い部分一致になる
  [[ "$l4" == *" 3h "*'$18.07'* ]]
}

@test "経過時間: 1時間未満もLine 4に届くこと(60秒ゲートの統合確認)" {
  # fmt_elapsed の単体テストだけだと、Line 4 側のゲートが >= 60 から >= 3600 に退行しても緑のまま。
  # m 帯が実際に描画に乗ることはフルスクリプトで押さえる
  l4=$(printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"cost":{"total_cost_usd":0.42,"total_duration_ms":2460000}}' \
    | /bin/bash statusline-command.sh | tail -1 | _strip)
  [[ "$l4" == *" 41m "*'$0.42'* ]]
}

@test "キャッシュ: CLAUDE_STATUSLINE_CACHE_DIR で置き場を差し替えられること(テスト密閉の seam)" {
  d="$BATS_TEST_TMPDIR/altcache"
  CLAUDE_STATUSLINE_CACHE_DIR="$d" /bin/bash -c 'printf "%s" "{\"model\":{\"id\":\"claude-opus-5\",\"display_name\":\"Opus 5\"},\"workspace\":{\"current_dir\":\"'"$BATS_TEST_DIRNAME"'\"}}" | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"' >/dev/null
  sleep 1
  [[ -d "$d" ]]
  # Security: cache dir は owner-only。mkdir -p -m 700 は BSD では最後のディレクトリにしか
  # mode を当てないので、親 (CACHE_BASE) も operand に並べないと 755 で残る
  [[ "$(stat -f '%Lp' "$d")" == "700" ]]
  [[ "$(stat -f '%Lp' "$d/git")" == "700" ]]
}

@test "subscription: credentials が読めなくてもキャッシュを書き、毎レンダーの再取得を起こさないこと" {
  # NO_NET を外して実際に fetch 経路へ入れる。実ユーザーの資格情報は読ませない —
  # security を必ず失敗する偽物に差し替え、ファイル fallback も空の HOME へ向ける
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/fakehome"
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/security"
  chmod +x "$BATS_TEST_TMPDIR/bin/security"
  d="$BATS_TEST_TMPDIR/subcache"
  run env -u CLAUDE_STATUSLINE_NO_NET HOME="$BATS_TEST_TMPDIR/fakehome" \
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" CLAUDE_STATUSLINE_CACHE_DIR="$d" \
    /bin/bash -c 'printf "%s" "{\"model\":{\"id\":\"claude-opus-5\",\"display_name\":\"Opus 5\"},\"workspace\":{\"current_dir\":\"'"$BATS_TEST_DIRNAME"'\"}}" | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"'
  for i in {1..20}; do [[ -f "$d/subscription" ]] && break; sleep 0.1; done
  # ファイルを書かないと cache_stale が「不在=stale」で毎レンダー背景 fetch を起こし、
  # Keychain 読みの storm になる (extra-usage が 0 でも必ず書くのと同じ理由)
  [[ -f "$d/subscription" ]]
  # タグ + 空値が入る（storm を防ぐために「書く」ことが要件。値は空でよく display は非表示に倒れる）
  [[ "$(< "$d/subscription")" == "type,tier"$'\037'$'\037'* || "$(< "$d/subscription")" == "type,tier"$'\037' ]]
  [[ "$output" == *"Anthropic"* ]]    # 種別が無くても provider 表示は出る
  [[ "$output" != *"Anthropic("* ]]   # 空の括弧は出さない
}

@test "背景更新: 遅い curl と遅い git がレンダーをブロックしないこと(継承stdoutでEOFが遅れる回帰)" {
  # `( ... ) & disown` だけでは背景化にならない — subshell が親の stdout を継承したまま生き、
  # statusline を**捕捉する側**は最後の fd 保持者が終わるまで EOF を見ない。
  # `>/dev/null 2>&1` を落とすと 3 秒の curl でレンダーが 3 秒止まる (実測 3.1s → 50ms)。
  # curl 側と git 側の**両方**を見る — curl だけだと `current_dir` が非 git のとき
  # build_git が即 return するので、git の背景ブロックから redirect を外しても緑のままになる。
  # 偽コマンドは固定 sleep ではなく**解放ファイル待ち**にする — 固定 sleep だと bats が
  # 実行終了時に孤児プロセスを待って 1 テストあたり数秒余計にかかる。
  _stub_env block "$(printf 'touch "%s/curl-called"\nfor i in $(seq 40); do [[ -e "%s/release" ]] && exit 0; sleep 0.1; done' \
    "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR")"
  # git も遅くする (背景の build_git が最初に呼ぶのは `git branch --show-current`)。
  # `_stub_env` が張った symlink を先に外す — 残すと実 git バイナリへ書き込もうとして失敗する
  rm -f "$_stub_bin/git"
  printf '#!/bin/bash\ntouch "%s/git-called"\nfor i in $(seq 40); do [[ -e "%s/release" ]] && exit 1; sleep 0.1; done\nexit 1\n' \
    "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" > "$_stub_bin/git"
  chmod +x "$_stub_bin/git"
  # current_dir は .git を持つ実リポにする = cold-start で build_git を必ず起こす
  s=$SECONDS
  # command substitution で捕捉する = Claude Code と同じ読み方
  out=$(printf '%s' "$(jq -nc --arg d "$BATS_TEST_DIRNAME" \
        '{model:{id:"claude-opus-5",display_name:"Opus 5"},workspace:{current_dir:$d},context_window:{used_percentage:42}}')" \
    | "${_stub_pre[@]}" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh")
  elapsed=$((SECONDS - s))
  [[ -n "$out" ]]
  (( elapsed < 2 )) || { echo "レンダーが ${elapsed}s ブロックした (背景 subshell が stdout を保持している)" >&3; return 1; }
  # **偽コマンドまで到達していることを確認する** — credentials が読めない / 非 git dir だと
  # 背景処理が起きず、このテストは「何もしていないから速い」で無条件に緑になる (実際に一度そうなった)
  _wait_for_file "$BATS_TEST_TMPDIR/curl-called" || { echo "curl に到達していない = テストが無意味" >&3; return 1; }
  _wait_for_file "$BATS_TEST_TMPDIR/git-called" || { echo "git に到達していない = git 側が未被覆" >&3; return 1; }
  touch "$BATS_TEST_TMPDIR/release"   # 偽コマンドを解放して孤児待ちを避ける
}

@test "credentials: Keychain 不在でもファイルから読めてサブスク種別が出ること" {
  # `$(<file 2>/dev/null)` は bash 3.2 で**常に空文字**になる (bash 5 では動くので手元で気付けない)。
  # これを踏むと subscription と extra-usage が丸ごと死ぬが、キャッシュは空で書かれるので
  # 「ファイルはある」系の assert だけでは検出できない → 表示まで見る
  _stub_env cred 'exit 1'    # ネットは失敗させる (種別は Keychain/ファイル由来なので影響しない)
  printf '%s' '{"claudeAiOauth":{"accessToken":"AAAAtest","subscriptionType":"enterprise"}}' \
    > "$_stub_home/.claude/.credentials.json"
  local j
  j=$(jq -nc '{model:{id:"claude-opus-5",display_name:"Opus 5"},workspace:{current_dir:"/tmp"},context_window:{used_percentage:5}}')
  printf '%s' "$j" | "${_stub_pre[@]}" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" >/dev/null
  _wait_for_file "$_stub_cache/subscription" -s
  # キャッシュは `形式タグ US 契約種別 US レート枠` (この fixture は rateLimitTier を持たないので枠は空)
  local _cached _st
  _cached=$(<"$_stub_cache/subscription")
  _st="${_cached#*$'\037'}"; _st="${_st%%$'\037'*}"
  [[ "$_st" == "enterprise" ]]
  # 2 回目のレンダーでキャッシュから読んで表示に載ること。表記は公式名 (`Enterprise`)
  run env "${_stub_pre[@]:1}" /bin/bash -c \
    'printf "%s" "$1" | /bin/bash "$2"' _ "$j" "$BATS_TEST_DIRNAME/statusline-command.sh"
  [[ "$output" == *"Anthropic(Enterprise)"* ]]
}

@test "credentials: CLAUDE_CONFIG_DIR 側の credentials から読むこと" {
  # ハードコードすると別 config dir で **subscription と extra-usage が無言で消える**
  # (macOS は Keychain が主経路なので気づきにくい)。詳細は docs/internals.md の「宛名」節。
  # **alt 側に helper の既定と違う種別を置く** — 同じ値にすると、偽 HOME 側の書き込みを
  # 後から誰かが消したときに両方一致して**無条件に緑**になる
  _stub_env credcd 'exit 1'          # 偽 HOME 側は helper の既定 (max) のまま
  local alt="$BATS_TEST_TMPDIR/credcd-alt"
  mkdir -p "$alt"
  printf '%s' '{"claudeAiOauth":{"accessToken":"AAAAtest","subscriptionType":"pro"}}' \
    > "$alt/.credentials.json"
  local j
  j=$(jq -nc '{model:{id:"claude-opus-5",display_name:"Opus 5"},workspace:{current_dir:"/tmp"},context_window:{used_percentage:5}}')
  printf '%s' "$j" | "${_stub_pre[@]}" "CLAUDE_CONFIG_DIR=$alt" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" >/dev/null
  _wait_for_file "$_stub_cache/subscription" -s
  # `pro` = CLAUDE_CONFIG_DIR 側。`max` なら偽 HOME 側を読んでいる
  # (レコードは `形式タグ US 契約種別 US レート枠` なので 2 番目を見る)
  local _cached _st2
  _cached=$(<"$_stub_cache/subscription")
  _st2="${_cached#*$'\037'}"; _st2="${_st2%%$'\037'*}"
  [[ "$_st2" == "pro" ]]
}

@test "Keychain: config dir 未指定なら suffix 無しのサービス名で引くこと" {
  # 上の対のテストと 2 本セットで見る。こちらが無いと「Keychain を常に飛ばす」実装でも
  # 「別アカウントを読まない」側だけが緑になる（既定ユーザー全員の subscription が消える回帰）。
  _stub_env kcplain 'exit 1'
  local log="$BATS_TEST_TMPDIR/kcplain-security.log"
  ln -sf "$(command -v shasum)" "$_stub_bin/" 2>/dev/null || true
  printf '%s\n' '#!/bin/bash' "echo \"svc=\$3\" >> $(printf %q "$log")" \
    '[[ "$3" == "Claude Code-credentials" ]] || exit 44' \
    "printf '%s' '{\"claudeAiOauth\":{\"accessToken\":\"AAAAtest\",\"subscriptionType\":\"team\"}}'" \
    > "$_stub_bin/security"
  chmod +x "$_stub_bin/security"
  local j
  j=$(jq -nc '{model:{id:"claude-opus-5",display_name:"Opus 5"},workspace:{current_dir:"/tmp"},context_window:{used_percentage:5}}')
  printf '%s' "$j" | "${_stub_pre[@]}" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" >/dev/null
  _wait_for_file "$_stub_cache/subscription" -s
  local _cached _st
  _cached=$(<"$_stub_cache/subscription")
  _st="${_cached#*$'\037'}"; _st="${_st%%$'\037'*}"
  # Keychain 由来の `team`。偽 HOME のファイル側は helper 既定の `max` なので、値で経路が分かる
  [[ "$_st" == "team" ]]
  # 引いた名前そのものを pin する（suffix が付いてしまう回帰を値だけでは検出できない）
  [[ "$(cat "$log")" == *"svc=Claude Code-credentials"* ]]
  [[ "$(cat "$log")" != *"svc=Claude Code-credentials-"* ]]
}

@test "Keychain: config dir を指定したセッションで既定アカウントの blob を読まないこと" {
  # Keychain のサービス名は config dir ごとに `-<sha256[0:8]>` が付く（2.1.233 のバイナリで実測。
  # docs にも CHANGELOG にも無い）。`Claude Code-credentials` を決め打ちで引くと、別 config dir の
  # セッションで**既定アカウントの blob**を読む = 別アカウントのプラン名と credits:$ を出す誤情報になる。
  _stub_env kcsuffix 'exit 1'
  local log="$BATS_TEST_TMPDIR/kcsuffix-security.log"
  local alt="$BATS_TEST_TMPDIR/kcsuffix-alt"
  mkdir -p "$alt"
  ln -sf "$(command -v shasum)" "$_stub_bin/" 2>/dev/null || true
  printf '%s\n' '#!/bin/bash' "echo \"svc=\$3\" >> $(printf %q "$log")" \
    '[[ "$3" == "Claude Code-credentials" ]] || exit 44' \
    "printf '%s' '{\"claudeAiOauth\":{\"accessToken\":\"AAAAtest\",\"subscriptionType\":\"team\"}}'" \
    > "$_stub_bin/security"
  chmod +x "$_stub_bin/security"
  local j
  j=$(jq -nc '{model:{id:"claude-opus-5",display_name:"Opus 5"},workspace:{current_dir:"/tmp"},context_window:{used_percentage:5}}')
  printf '%s' "$j" | "${_stub_pre[@]}" "CLAUDE_CONFIG_DIR=$alt" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" >/dev/null
  _wait_for_file "$_stub_cache/subscription" -s
  local _cached _st
  _cached=$(<"$_stub_cache/subscription")
  _st="${_cached#*$'\037'}"; _st="${_st%%$'\037'*}"
  # `team` なら既定アカウントの Keychain を読んでいる = 誤情報。alt 側には credentials が無いので空が正解
  [[ "$_st" != "team" ]]
  # **到達証跡** — `security` に一度も触らずに空になったのでは何も pin できない。
  # suffix 付きの名前で引いていること（16 進 8 桁）を見る
  [[ "$(cat "$log")" =~ svc=Claude\ Code-credentials-[0-9a-f]{8} ]]
}

@test "Keychain: suffix を算出できないときは決め打ち名に落ちず Keychain ごと飛ばすこと" {
  # suffix が必要（config dir 指定あり）なのに `shasum` が無い場合、`Claude Code-credentials` を
  # 決め打ちで引くと**既定アカウントの blob**を読む = 別アカウントのプラン名を出す。
  # **この経路は他の 2 本では構造的に踏めない**（どちらも偽 PATH に shasum を張っている）ので、
  # `_keychain_ok=1` を無条件にする mutant がテストをすり抜けていた。
  _stub_env kcskip 'exit 1'
  local log="$BATS_TEST_TMPDIR/kcskip-security.log"
  local alt="$BATS_TEST_TMPDIR/kcskip-alt"
  mkdir -p "$alt"
  # **shasum は張らない**（`_stub_env` の既定 PATH に無い）= suffix を算出できない状況を作る
  [[ ! -x "$_stub_bin/shasum" ]]
  # `security` は存在するが**一度も呼ばれない**のが正解。呼ばれたら log ができる
  printf '%s\n' '#!/bin/bash' "echo \"svc=\$3\" >> $(printf %q "$log")" \
    "printf '%s' '{\"claudeAiOauth\":{\"accessToken\":\"AAAAtest\",\"subscriptionType\":\"team\"}}'" \
    > "$_stub_bin/security"
  chmod +x "$_stub_bin/security"
  # 到達証跡 — alt 側のファイル fallback だけが情報源になる（値で経路が分かる）
  printf '%s' '{"claudeAiOauth":{"subscriptionType":"enterprise"}}' > "$alt/.credentials.json"
  local j
  j=$(jq -nc '{model:{id:"claude-opus-5",display_name:"Opus 5"},workspace:{current_dir:"/tmp"},context_window:{used_percentage:5}}')
  printf '%s' "$j" | "${_stub_pre[@]}" "CLAUDE_CONFIG_DIR=$alt" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" >/dev/null
  _wait_for_file "$_stub_cache/subscription" -s
  local _cached _st
  _cached=$(<"$_stub_cache/subscription")
  _st="${_cached#*$'\037'}"; _st="${_st%%$'\037'*}"
  # ファイル fallback 側の値。`team` なら Keychain を決め打ち名で引いてしまっている
  [[ "$_st" == "enterprise" ]]
  [[ ! -f "$log" ]] || { printf 'Keychain を飛ばさず引いている: %s\n' "$(cat "$log")" >&2; false; }
}

@test "Keychain: account 属性(-a)を付けて引くこと" {
  # 上流は読み書き両方で `-a <USER>` 込みで識別する（2.1.238 の `Tkd()`/`hYT()`）。service だけで
  # 引くと、同名 item が 2 つある keychain で**別アカウントの blob**を読む = suffix 対応で閉じた
  # はずの誤読が残る。**argv そのものを pin する** — 値だけ見ても `-a` の有無は分からない。
  _stub_env kcacct 'exit 1'
  local log="$BATS_TEST_TMPDIR/kcacct-security.log"
  ln -sf "$(command -v shasum)" "$_stub_bin/" 2>/dev/null || true
  printf '%s\n' '#!/bin/bash' "echo \"args=\$*\" >> $(printf %q "$log")" \
    '[[ "$3" == "Claude Code-credentials" ]] || exit 44' \
    "printf '%s' '{\"claudeAiOauth\":{\"accessToken\":\"AAAAtest\",\"subscriptionType\":\"team\"}}'" \
    > "$_stub_bin/security"
  chmod +x "$_stub_bin/security"
  local j
  j=$(jq -nc '{model:{id:"claude-opus-5",display_name:"Opus 5"},workspace:{current_dir:"/tmp"},context_window:{used_percentage:5}}')
  printf '%s' "$j" | "${_stub_pre[@]}" "USER=testuser" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" >/dev/null
  _wait_for_file "$_stub_cache/subscription" -s
  local _cached _st
  _cached=$(<"$_stub_cache/subscription")
  _st="${_cached#*$'\037'}"; _st="${_st%%$'\037'*}"
  [[ "$_st" == "team" ]]
  # `-s <名前>` の後に `-a <USER>` が来ること（順序は `$3` で名前を pin する既存 2 本と両立させるため）
  [[ "$(cat "$log")" == *"-s Claude Code-credentials -a testuser"* ]]
}

@test "plan: subscriptionType が公式表記に畳まれること" {
  # 公式プラン名は Free / Pro / Max 5x / Max 20x / Team / Enterprise (claude.com/pricing)。
  # 生値は小文字なので畳む。**リテラルで assert する** — 定数で書くとどんな値でも通る。
  plan_label out "pro" ""        ; [[ "$out" == "Pro" ]]
  plan_label out "max" ""        ; [[ "$out" == "Max" ]]
  plan_label out "team" ""       ; [[ "$out" == "Team" ]]
  plan_label out "enterprise" "" ; [[ "$out" == "Enterprise" ]]
  plan_label out "free" ""       ; [[ "$out" == "Free" ]]
  # 未知の契約種別は生のまま出す (旧/新 Claude Code の graceful degradation)
  plan_label out "someday_plan" "" ; [[ "$out" == "someday_plan" ]]
}

@test "plan: レート枠を rateLimitTier の suffix から取り、値を列挙しないこと" {
  # 未文書フィールドなので許可リストを持たない。suffix が `Nx` の形かだけを見る。
  plan_label out "max" "default_claude_max_5x"        ; [[ "$out" == "Max 5x" ]]
  plan_label out "max" "default_claude_max_20x"       ; [[ "$out" == "Max 20x" ]]
  # `default_claude_ai` (Pro 相当、上流 issue #43639 で実在) は Nx を持たないので枠を出さない
  plan_label out "pro" "default_claude_ai"            ; [[ "$out" == "Pro" ]]
  # 枠は契約種別と独立 — 実測で Enterprise 契約が max_5x を持つ
  plan_label out "enterprise" "default_claude_max_5x" ; [[ "$out" == "Enterprise 5x" ]]
  plan_label out "team" "default_claude_max_5x"       ; [[ "$out" == "Team 5x" ]]
  # **未知の枠でも prefix が変わっても動く** — ここが許可リストとの差
  plan_label out "max" "brand_new_prefix_50x"         ; [[ "$out" == "Max 50x" ]]
  # **桁数に上限を置かない** — `[0-9]x|[0-9][0-9]x` の頃は 3 桁が枠なしに落ちていた
  # (列挙の粒度が値から桁数に移っただけ。`/code-review` 指摘)
  plan_label out "max" "default_claude_max_100x"      ; [[ "$out" == "Max 100x" ]]
  # `x` で終わっても数値でなければ枠にしない
  plan_label out "max" "default_claude_max_prefix"    ; [[ "$out" == "Max" ]]
  # 枠が空 / null 相当でも契約名は出す
  plan_label out "enterprise" ""                      ; [[ "$out" == "Enterprise" ]]
  plan_label out "enterprise" "null"                  ; [[ "$out" == "Enterprise" ]]
}

@test "plan: タグだけ違う subscription キャッシュを読まないこと" {
  # タグ無し（`max` 単体）はフィールドが空になるので値の捨て忘れを検出できない。
  # **タグだけ違って中身は現行の形**のファイルで pin する（捨て忘れると枠まで出てしまう）。
  local d="$BATS_TEST_TMPDIR/wrongfmtsub"
  mkdir -p -m 700 "$d"
  printf 'OLD_FMT\037max\037default_claude_max_5x' > "$d/subscription"
  local j out
  j=$(jq -nc '{model:{id:"claude-opus-5",display_name:"Opus 5"},workspace:{current_dir:"/tmp"},context_window:{used_percentage:5}}')
  # **NO_NET は使わない** — あれは Keychain 読みごと止めるので、タグ検証を外しても契約名が
  # 出ず「常に緑」になる（実際にこの形で書いて pin できていなかった）。偽 HOME で
  # credentials を読めなくし、**キャッシュだけが情報源**の状態にする
  out=$(printf '%s' "$j" | env -u CLAUDE_STATUSLINE_NO_NET CLAUDE_STATUSLINE_CACHE_DIR="$d" \
    HOME="$BATS_TEST_TMPDIR/nohome-wrongfmt" /bin/bash statusline-command.sh 2>/dev/null | sed -n '1p' | _strip)
  [[ "$out" != *"Max"* ]]
  [[ "$out" != *"5x"* ]]
  [[ "$out" == *"Anthropic"* ]]
}

@test "plan: タグの無い subscription キャッシュを読まないこと(アップグレード経路)" {
  # v1.73.0 が書く単一値 `max` を新コードが読むと、契約名は出るが**レート枠が空**になり
  # `Anthropic(Max 5x)` が `Anthropic(Max)` に退化する。この状態が 3600s 続いていた。
  # 形式タグを見るようにしたので、タグの無い中身は使わない（`max` はタグ位置で不一致になる）。
  local d="$BATS_TEST_TMPDIR/upgradesub"
  mkdir -p -m 700 "$d"
  printf 'max' > "$d/subscription"          # v1.73.0 の形式（タグ無し）
  local j out
  j=$(jq -nc '{model:{id:"claude-opus-5",display_name:"Opus 5"},workspace:{current_dir:"/tmp"},context_window:{used_percentage:5}}')
  # 偽 HOME で Keychain も credentials も読めない状態にし、「旧ファイルだけが情報源」にする
  out=$(printf '%s' "$j" | env CLAUDE_STATUSLINE_NO_NET=1 CLAUDE_STATUSLINE_CACHE_DIR="$d" \
    HOME="$BATS_TEST_TMPDIR/nohome-upgrade" /bin/bash statusline-command.sh 2>/dev/null | sed -n '1p' | _strip)
  [[ "$out" != *"Max"* ]]                   # 旧ファイルは読まれない
  [[ "$out" == *"Anthropic"* ]]             # 行そのものは出る (provider は stdin 由来)
  [[ -f "$d/subscription" ]]                # ファイル自体は残る（NO_NET なので取り直しは走らない）
}

@test "plan: タグの無いキャッシュを読んでも stderr が汚れないこと" {
  # 使わないだけで、エラーも警告も出さないこと（読み手に見えるのは「枠が出ない」だけ）。
  local d="$BATS_TEST_TMPDIR/oldsubcache"
  mkdir -p -m 700 "$d"
  printf 'max' > "$d/subscription"          # 旧形式: US 区切りが無い
  local j
  j=$(jq -nc '{model:{id:"claude-opus-5",display_name:"Opus 5"},workspace:{current_dir:"/tmp"},context_window:{used_percentage:5}}')
  # NO_NET だと種別を空に倒す経路に入ってしまうので、**キャッシュを読む経路を通すため
  # NO_NET を外して**確認する (偽 HOME で Keychain/credentials も読めない状態にする)
  run env -u CLAUDE_STATUSLINE_NO_NET CLAUDE_STATUSLINE_CACHE_DIR="$d" HOME="$BATS_TEST_TMPDIR/nohome" /bin/bash -c \
    'printf "%s" "$1" | /bin/bash "$2"' _ "$j" "$BATS_TEST_DIRNAME/statusline-command.sh"
  # タグが無いので**契約名も出ない**（誤った枠を出すより出さない）。行そのものは出る
  [[ "$output" == *"Anthropic"* ]]
  [[ "$output" != *"Anthropic("* ]]
  # stderr が空であること — `2>/dev/null` で捨てると gate を外しても緑のままになる
  run env -u CLAUDE_STATUSLINE_NO_NET CLAUDE_STATUSLINE_CACHE_DIR="$d" HOME="$BATS_TEST_TMPDIR/nohome" /bin/bash -c \
    'printf "%s" "$1" | /bin/bash "$2" 2>&1 >/dev/null' _ "$j" "$BATS_TEST_DIRNAME/statusline-command.sh"
  [[ -z "$output" ]]
}

@test "credentials: 読めない credentials で stderr を汚さないこと" {
  # 背景 subshell の stderr は閉じてあるが、gate 自体も `-r` で readability を見る
  h="$BATS_TEST_TMPDIR/nrhome"; mkdir -p "$h/.claude"
  c="$h/.claude/.credentials.json"
  printf '%s' '{"claudeAiOauth":{"subscriptionType":"max"}}' > "$c"; chmod 000 "$c"
  run env -u CLAUDE_STATUSLINE_NO_NET HOME="$h" CLAUDE_STATUSLINE_CACHE_DIR="$BATS_TEST_TMPDIR/nrcache" \
    /bin/bash -c 'printf "%s" "{\"model\":{\"id\":\"claude-opus-5\",\"display_name\":\"Opus 5\"},\"workspace\":{\"current_dir\":\"/tmp\"},\"context_window\":{\"used_percentage\":5}}" | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh" 2>&1 >/dev/null'
  chmod 644 "$c"
  [[ -z "$output" ]] || { echo "stderr に出力: $output" >&3; return 1; }
}

@test "セキュリティ: トークンが curl のオプションに化けないこと(argv 露出も無いこと)" {
  # `--config -` を使っていた頃は各行が**設定ディレクティブ**だったので、改行入りトークンが
  # `output = <path>` の注入になりえた。`-H @-` なら各行は必ずヘッダなので構造的に化けない。
  # 字種の拒否リストで守る形に戻すと、この 1 本が「注入されないこと」を保証しなくなる。
  _stub_env inject "$(printf 'printf "%%s\\n" "$@" > "%s/argv.txt"\ncat > "%s/stdin.txt"' \
    "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR")"
  ln -s "$(command -v cat)" "$_stub_bin/" 2>/dev/null || true
  # トークンに curl ディレクティブを仕込む
  jq -nc --arg t "$(printf 'AAAA\noutput = %s/pwned' "$BATS_TEST_TMPDIR")" \
    '{claudeAiOauth:{accessToken:$t,subscriptionType:"max"}}' > "$_stub_home/.claude/.credentials.json"
  printf '%s' "$(jq -nc '{model:{id:"claude-opus-5",display_name:"Opus 5"},workspace:{current_dir:"/tmp"},context_window:{used_percentage:5}}')" \
    | "${_stub_pre[@]}" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh" >/dev/null
  _wait_for_file "$BATS_TEST_TMPDIR/argv.txt" -s
  # ① 注入したパスにファイルが作られていないこと
  [[ ! -e "$BATS_TEST_TMPDIR/pwned" ]]
  # ② argv にトークンが出ていないこと (ps 漏れ防止)。ヘッダは stdin から渡る
  ! grep -q 'AAAA' "$BATS_TEST_TMPDIR/argv.txt"
  grep -qF -- '-H' "$BATS_TEST_TMPDIR/argv.txt"
  grep -qF -- '@-' "$BATS_TEST_TMPDIR/argv.txt"
  # ③ Authorization ヘッダは stdin 経由で実際に渡っていること
  grep -q '^Authorization: Bearer AAAA' "$BATS_TEST_TMPDIR/stdin.txt"
}

@test "install: 試走が実キャッシュディレクトリを汚さないこと" {
  s="$BATS_TEST_TMPDIR/probe.json"
  echo '{}' > "$s"
  d="$BATS_TEST_TMPDIR/probe-realcache"
  mkdir -p "$d"
  CLAUDE_SETTINGS="$s" CLAUDE_STATUSLINE_CACHE_DIR="$d" \
    /bin/bash "$BATS_TEST_DIRNAME/install.sh" --yes >/dev/null
  sleep 0.5
  # 試走は自前の mktemp -d に隔離する。NO_NET は git キャッシュには効かないので、
  # この隔離が無いとインストールがユーザーの本物のキャッシュにエントリを作る
  [[ -z "$(ls -A "$d")" ]]
}

# ============================================================================
# build_git のデータ/表示分離 (v1.53.0) — 3 パス問題と cross-session 汚染の構造的解消
# ============================================================================
@test "Git facts: 非 git ディレクトリで背景 build を毎レンダー起こさないこと" {
  # `build_git` は非 git では何も出さないので **0 バイトのキャッシュ**が残る。タグ不一致と
  # 同じ扱いにすると `cache_stale` の 5s 抑止を通らず**毎レンダー背景 build が spawn される**
  # (storm。表示は正常なので沈黙する。`/code-review` が実測で捕まえた)。
  # **偽 `git` の起動回数で見る** — mtime は秒精度なので「書き込みが起きないこと」を表せず、
  # 秒を跨がせる固定 sleep も要る（実測 1.5s でスイート最遅だった。`/simplify` 指摘）。
  local bin="$BATS_TEST_TMPDIR/nogitbin" log="$BATS_TEST_TMPDIR/nogitlog" d="$BATS_TEST_TMPDIR/nogitcache"
  mkdir -p "$bin" "$d"
  _count_cmd "$bin" git "$log"
  local j='{"model":{"id":"test","display_name":"Test"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}'
  _render() { printf '%s' "$j" | env "PATH=$bin:$PATH" \
    "CLAUDE_STATUSLINE_CACHE_DIR=$d" /bin/bash statusline-command.sh >/dev/null 2>&1; }
  : > "$log"; _render
  _wait_for_file "$d/git/$(md5 -q -s /tmp)" \
    || { echo "キャッシュが書かれていない = テストが無意味" >&3; return 1; }
  (( $(grep -c . "$log") > 0 )) || { echo "1 回目で git に到達していない = テストが無意味" >&3; return 1; }
  # 2 回目: 5s 以内なので背景 build は起きない（起きるなら偽 git が呼ばれる）
  : > "$log"; _render; sleep 0.3
  [[ "$(grep -c . "$log")" == "0" ]] || { echo "5s 以内に再 spawn した" >&3; false; }
}

@test "Git facts: git am 中は rebase ではなく am と出すこと" {
  # `rebase-apply/` は `git am` でも作られる。`applying` の有無で分けないと、
  # `git rebase --abort` を打とうとして「am には無い」と気づく手戻りになる (`/code-review` 指摘)。
  local d="$BATS_TEST_TMPDIR/amrepo" plain
  _repo_at "$d"
  mkdir -p "$d/.git/rebase-apply"
  : > "$d/.git/rebase-apply/applying"     # am の印
  printf '2\n' > "$d/.git/rebase-apply/next"
  printf '5\n' > "$d/.git/rebase-apply/last"
  plain=$(_line3_of "{\"model\":{\"id\":\"test\",\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"$d\"},\"context_window\":{\"used_percentage\":10}}" | _strip)
  [[ "$plain" == "am 2/5"* ]]
  [[ "$plain" != *"rebase"* ]]
}

@test "キャッシュ: mtime をまとめて 1 回の stat で取ること" {
  # 3 つの stale 判定で個別に `stat` を呼ぶと fork が 3 個になる（実測 9.802ms、暖まった描画の
  # 16%）。**1 回のまとめ取り**に寄せた（`/simplify` の効率担当が計測）。
  # 偽 `stat` の**起動回数**で見る（時間で測ると環境差で flaky になる）。
  # **`NO_NET` を使わない** — あれは subscription と usage の stale 判定ごと短絡するので、
  # まとめ取りを外しても stat が 1 回のままになり「常に緑」になる（実際にこの形で書いて
  # pin できていなかった）。`_stub_env` で偽 PATH/HOME と失敗する curl を用意し、
  # **3 つの判定が全部走る**状態にする。
  _stub_env statcnt 'exit 1'
  local log="$BATS_TEST_TMPDIR/statlog"
  _count_cmd "$_stub_bin" stat "$log"
  mkdir -p "$_stub_cache/git"
  printf 'type,tier\037max\037default_claude_max_5x' > "$_stub_cache/subscription"
  printf 'cents,limits\0370\n' > "$_stub_cache/usage_spend"
  : > "$_stub_cache/git/$(md5 -q -s /tmp)"
  : > "$log"
  printf '%s' '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | "${_stub_pre[@]}" /bin/bash statusline-command.sh >/dev/null 2>&1
  # 1 回であることの assert が到達証跡も兼ねる（0 なら「stat に到達していない」= テストが無意味）
  local n; n=$(grep -c . "$log")
  [[ "$n" == "1" ]] || { echo "stat の起動が $n 回（0 なら stat に到達していない = テストが無意味）" >&3; false; }
}

@test "キャッシュ: まとめ取りで欠損ファイルがあっても別ファイルの mtime を読まないこと" {
  # `stat -f '%m' f1 f2 f3` は**欠損があると行がずれる**ので、パスも出して名前で
  # 突き合わせないと別ファイルの mtime を読む（実測で確認済みの罠）。
  # **観測対象は「欠損の直後にある引数」にする** — 欠損行は stdout に出ないので、ずれは
  # 「後ろの値が前のスロットに入る」方向にしか起きない。prefetch の引数順は
  # subscription, usage, git なので、**最後の git は構造的に誤った mtime を受け取れず**、
  # git で assert すると位置引きの実装でも緑になる（この形で書いて pin できていなかった）。
  # subscription を欠損 → usage は現行タグだが古い（取り直すべき）→ git は新鮮な実ファイル。
  # 位置引きだと usage のスロットに git の新鮮な mtime が入り、300s の抑止が誤って効いて
  # curl に到達しない。**3 つ目の git を置くのが load-bearing** — 無いと usage が map から
  # 落ちて個別 `stat` の正しい値に戻り、mutation が緑に戻る。
  # `NO_NET` も使えない（usage の取得ごと止まり唯一の観測窓が塞がる）。
  _stub_env candmix ': > "$HOME/curl-called"; exit 1'
  # subscription は**置かない** = 欠損（`stat` の先頭の引数。`_stub_env` はキャッシュ dir を作らない）
  mkdir -p "$_stub_cache/git"
  printf 'cents,limits\0370\n' > "$_stub_cache/usage_spend"
  touch -t 202001010000 "$_stub_cache/usage_spend"      # 現行タグだが古い
  : > "$_stub_cache/git/$(md5 -q -s /tmp)"              # 新鮮
  printf '%s' '{"model":{"id":"test","display_name":"Test"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | "${_stub_pre[@]}" /bin/bash statusline-command.sh >/dev/null 2>&1
  _wait_for_file "$_stub_home/curl-called" \
    || { echo "古い usage キャッシュが取り直されていない = 別ファイルの mtime を読んだ" >&3; false; }
}

@test "Git facts: タグの違うキャッシュを使わず作り直すこと" {
  # レコードは位置で読むので、形式が変わった旧キャッシュをそのまま解釈すると**別の値が
  # 別のフィールドとして表示される**（v1.74.0 の subscription と同じクラスの破綻で、
  # あちらは「枠が空」で済んだがこちらは誤表示になりうる）。タグ不一致は捨てて作り直す。
  local d="$BATS_TEST_TMPDIR/gitfmt" w="$BATS_TEST_TMPDIR/gitfmtrepo"
  _repo_at "$w"
  mkdir -p "$d/git"
  # 新鮮（TTL 内）だがタグが違うレコードを置く。TTL だけを見る実装なら fakebranch が出てしまう
  printf 'OLD_FMT\037fakebranch\0370\037\037\0370\0370\0370\0370\0370\037\037\037\n' \
    > "$d/git/$(md5 -q -s "$w")"
  local out
  out=$(printf '%s' "{\"model\":{\"id\":\"test\",\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"$w\"},\"context_window\":{\"used_percentage\":10}}" \
    | CLAUDE_STATUSLINE_CACHE_DIR="$d" /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p' | _strip)
  [[ "$out" != *"fakebranch"* ]]        # タグ不一致のレコードは使わない
  [[ -n "$out" ]]                       # cold-start に落ちて行は出る
}

@test "Git facts: キャッシュにANSIもstdin由来値も入らないこと" {
  d="$BATS_TEST_TMPDIR/factcache"
  p='{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$BATS_TEST_DIRNAME"'"},"pr":{"review_state":"approved"},"context_window":{"used_percentage":48}}'
  CLAUDE_STATUSLINE_CACHE_DIR="$d" /bin/bash -c 'printf "%s" '"'$p'"' | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"' >/dev/null
  _wait_for_cache "$d/git"
  # 決定形で開く（`cat "$d"/git/*` は並走の中間ファイルを拾いうる）
  local facts; facts=$(< "$d/git/$(md5 -q -s "$BATS_TEST_DIRNAME")")
  [[ "$facts" != *$'\033'* ]]        # レンダリング済み ANSI を置かない
  [[ "$facts" != *"approved"* ]]     # stdin 由来値 (PR state) を置かない = 別セッションに漏れない
  [[ "$facts" == *$'\037'* ]]        # US 区切りの facts である
  # 先頭は形式タグ (フィールド一覧)。一致しないレコードは読み側が捨てて取り直す
  [[ "$facts" == "branch,detached,repo,remote,ins,del,conf,ahead,behind,age,msg,op"$'\037'* ]]
}

@test "dirty state: 行数の増減が +N -N で出ること" {
  # Claude Desktop の code 画面と同じ単位 (行数) と色 (緑/赤)。旧 `A3 M2 ?1` の
  # ファイル状態ごとの件数は出さない (v1.74.0、ユーザー選択)。
  local w="$BATS_TEST_TMPDIR/ins1" c="$BATS_TEST_TMPDIR/insc1"
  mkdir -p "$w"; git -C "$w" init -q
  printf 'a\nb\nc\nd\ne\n' > "$w/f"
  git -C "$w" add f
  git -C "$w" -c user.email=a@b -c user.name=a commit -qm base
  # 2 行消して 3 行足す → +3 -2
  printf 'a\nX\nY\nZ\nd\ne\nF\n' > "$w/f"   # b,c を消し X,Y,Z,F を足す
  _l3() { CLAUDE_STATUSLINE_CACHE_DIR="$c" /bin/bash -c 'printf "%s" '"'"'{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$w"'"}}'"'"' | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"' | sed -n 3p; }
  _l3 >/dev/null
  _wait_for_cache "$c/git"
  local raw plain want
  raw=$(_l3)
  plain=$(printf '%s' "$raw" | _strip)
  # git の実値と突き合わせる (リテラルの数字を書くと git の差分判定に依存して脆くなる)
  want=$(git -C "$w" diff HEAD --numstat | awk -F'\t' '$1 ~ /^[0-9]+$/ {i+=$1; d+=$2} END {print "+"i" -"d}')
  [[ "$plain" == *"$want"* ]]
  # 色は**生のリテラル**で assert — 定数で書くとどんな値でも通る。
  # **ANSI 31/32 ではなく 256 色を明示する** — ANSI は端末テーマがマップし直すので、
  # 実測で olive / brick に化けて「緑と赤」に見えなかった。値は GitHub Primer の diff トークン
  # (ダーク) `#3fb950` / `#f85149` の 256 色最近傍 = 71 / 203
  [[ "$raw" == *$'\033[38;5;71m+'* ]]
  [[ "$raw" == *$'\033[38;5;203m-'* ]]
  # アラームの赤 (ANSI 31) と混ざっていないこと — あちらは !N / detached / 90%+ / 遅れた版の色
  [[ "$raw" != *$'\033[31m-'* ]]
  # 旧形式のファイル件数は出さない
  [[ "$plain" != *"M1"* ]]
  [[ "$plain" != *"A1"* ]]
}

@test "dirty state: untrackedの行が追加側に畳まれること" {
  # Desktop は untracked を `added` として扱い専用の記号を持たない。`git diff` は untracked を
  # 含まないので別途数えて足す。**空白入りパス**も落とさない (`-z` / `xargs -0`)。
  local w="$BATS_TEST_TMPDIR/ut1" c="$BATS_TEST_TMPDIR/utc1"
  mkdir -p "$w"; git -C "$w" init -q
  echo x > "$w/f"; git -C "$w" add f
  git -C "$w" -c user.email=a@b -c user.name=a commit -qm base
  printf '1\n2\n3\n' > "$w/new.txt"                    # untracked 3 行
  mkdir -p "$w/sub dir"; printf '4\n5\n' > "$w/sub dir/with space.txt"   # untracked 2 行
  CLAUDE_STATUSLINE_CACHE_DIR="$c" /bin/bash -c 'printf "%s" '"'"'{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$w"'"}}'"'"' | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"' >/dev/null
  _wait_for_cache "$c/git"
  local plain
  plain=$(CLAUDE_STATUSLINE_CACHE_DIR="$c" /bin/bash -c 'printf "%s" '"'"'{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$w"'"}}'"'"' | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"' | sed -n 3p | _strip)
  # tracked の変更は無いので +5 (untracked 3+2) だけになる
  [[ "$plain" == *"+5"* ]]
  # 旧 `?N` (untracked 件数) は出さない
  [[ "$plain" != *"?2"* ]]
}

@test "dirty state: untrackedの罠(ハイフン名/バイナリ/symlink)で数が狂わないこと" {
  # 素朴な `xargs -0 cat | grep -c` は 3 つとも stderr も出さずに黙って壊れる:
  #  ① `-n` という名のファイルは `cat -n` に化けてその分の行が消える (実測 5 → 3)
  #  ② `--bogus` は illegal option で untracked 全体が 0 になる (実測 4 → 0)
  #  ③ FIFO を指す symlink で読み込みが永久にブロックし、背景 job が毎レンダー積む
  local w="$BATS_TEST_TMPDIR/utrap" c="$BATS_TEST_TMPDIR/utrapc"
  _repo_at "$w"
  echo base > "$w/f"; git -C "$w" add f
  git -C "$w" -c user.email=a@b -c user.name=a commit -qm base
  printf 'a\nb\nc\n'   > "$w/plain.txt"      # 3 行
  printf 'x\ny\n'      > "$w/-n"             # 2 行（①）
  printf 'z\n'         > "$w/--bogus"        # 1 行（②）
  printf '\x00\x01\n\n\n' > "$w/blob.bin"    # バイナリ = 数えない
  mkfifo "$w/thefifo"; ln -sf thefifo "$w/link-to-fifo"   # ③
  mkdir -p "$w/sub dir"; printf 'p\nq\n' > "$w/sub dir/with space.txt"   # 2 行（空白入り）
  # **タイムアウト付きで実行する** — ③ が再発するとここで固まる。`timeout` は macOS に無いので python で
  run python3 -c '
import subprocess, sys
cwd, cache, script = sys.argv[1], sys.argv[2], sys.argv[3]
j = "{\"model\":{\"id\":\"claude-opus-5\",\"display_name\":\"Opus 5\"},\"workspace\":{\"current_dir\":\"%s\"}}" % cwd
env = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/tmp", "CLAUDE_STATUSLINE_CACHE_DIR": cache}
subprocess.run(["/bin/bash", script], input=j, capture_output=True, text=True, env=env, timeout=20)
# 背景の build_git 完走を待つ（cache が書かれるまで）
import glob, time
for _ in range(200):
    # 名前は md5 のみ（形式判定はレコード先頭のタグ）。**`.tmp-<pid>` を完成と誤認しない**
    if [g for g in glob.glob(cache + "/git/*") if ".tmp" not in g]: break
    time.sleep(0.05)
else:
    print("CACHE_NEVER_WRITTEN"); sys.exit(1)
r = subprocess.run(["/bin/bash", script], input=j, capture_output=True, text=True, env=env, timeout=20)
print(r.stdout.split(chr(10))[2])
' "$w" "$c" "$BATS_TEST_DIRNAME/statusline-command.sh"
  [[ "$status" -eq 0 ]]
  local plain
  plain=$(printf '%s' "$output" | sed $'s/\033\\[[0-9;]*h//g;s/\033\\[[0-9;]*m//g')
  # 3 + 2 + 1 + 2 = 8。バイナリ(改行3)と symlink は数えない
  [[ "$plain" == *"+8"* ]]
  rm -f "$w/thefifo" "$w/link-to-fifo"
}

@test "dirty state: 0の側を出さないこと" {
  # 追加だけの作業で `-0` が出るとノイズ。
  local w="$BATS_TEST_TMPDIR/z1" c="$BATS_TEST_TMPDIR/zc1"
  mkdir -p "$w"; git -C "$w" init -q
  printf 'a\n' > "$w/f"; git -C "$w" add f
  git -C "$w" -c user.email=a@b -c user.name=a commit -qm base
  printf 'a\nb\nc\n' > "$w/f"      # 2 行追加、削除 0
  CLAUDE_STATUSLINE_CACHE_DIR="$c" /bin/bash -c 'printf "%s" '"'"'{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$w"'"}}'"'"' | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"' >/dev/null
  _wait_for_cache "$c/git"
  local plain
  plain=$(CLAUDE_STATUSLINE_CACHE_DIR="$c" /bin/bash -c 'printf "%s" '"'"'{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$w"'"}}'"'"' | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"' | sed -n 3p | _strip)
  [[ "$plain" == *"+2"* ]]
  [[ "$plain" != *"-0"* ]]
}

@test "dirty state: コンフリクトが !N (赤) で出ること" {
  # 記号は Desktop の状態一覧に無いので自前で決めた。**`+`/`-` と同じ ASCII の 1 桁**が選定条件
  # (`×` は East Asian Ambiguous 幅で ambiguous-width=2 の端末だと桁が崩れる)。
  # マージ中は最優先の情報なので、行数の増減とは独立して残す。
  local w="$BATS_TEST_TMPDIR/cf1" c="$BATS_TEST_TMPDIR/cfc1"
  mkdir -p "$w"; git -C "$w" init -q
  printf 'base\n' > "$w/f"; git -C "$w" add f
  git -C "$w" -c user.email=a@b -c user.name=a commit -qm base
  git -C "$w" checkout -qb other
  printf 'other\n' > "$w/f"; git -C "$w" -c user.email=a@b -c user.name=a commit -qam other
  git -C "$w" checkout -q -    # 元のブランチへ (master/main どちらでも)
  printf 'mine\n' > "$w/f"; git -C "$w" -c user.email=a@b -c user.name=a commit -qam mine
  git -C "$w" merge other -q 2>/dev/null || true    # 衝突させる (rc は非 0)
  CLAUDE_STATUSLINE_CACHE_DIR="$c" /bin/bash -c 'printf "%s" '"'"'{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$w"'"}}'"'"' | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"' >/dev/null
  _wait_for_cache "$c/git"
  local raw plain
  raw=$(CLAUDE_STATUSLINE_CACHE_DIR="$c" /bin/bash -c 'printf "%s" '"'"'{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$w"'"}}'"'"' | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"' | sed -n 3p)
  plain=$(printf '%s' "$raw" | _strip)
  [[ "$plain" == *"!1"* ]]
  # 色は**生のリテラル**で assert (赤 31)
  [[ "$raw" == *$'\033[31m!'* ]]
  # 旧記号 `U` と、幅が環境依存の `×` は使わない
  [[ "$plain" != *"U1"* ]]
  [[ "$plain" != *"×"* ]]
}

@test "dirty state: binaryを行数に数えないこと" {
  # `numstat` は binary に `-` を出す。**このテストは型ガードを pin していない** —
  # ガードを外しても `((ins += -))` は rc=1 の非致死エラーで、ループも Line 3 も生き、
  # 加算もされないので数値まで同じになる（mutation で確認済み）。ガードの実益は
  # 「stderr を汚さない」と「将来 numstat が数値に見える別値を出したときの防御」で、
  # ここで pin できるのは **binary が混ざっても Line 3 が出て行数に混ざらない**ことだけ。
  local w="$BATS_TEST_TMPDIR/bin1" c="$BATS_TEST_TMPDIR/binc1"
  mkdir -p "$w"; git -C "$w" init -q
  printf 'a\n' > "$w/f"; git -C "$w" add f
  git -C "$w" -c user.email=a@b -c user.name=a commit -qm base
  printf '\x00\x01\x02\x03' > "$w/blob.bin"; git -C "$w" add blob.bin
  printf 'a\nb\n' > "$w/f"        # tracked は +1
  CLAUDE_STATUSLINE_CACHE_DIR="$c" /bin/bash -c 'printf "%s" '"'"'{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$w"'"}}'"'"' | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"' >/dev/null
  _wait_for_cache "$c/git"
  local plain
  plain=$(CLAUDE_STATUSLINE_CACHE_DIR="$c" /bin/bash -c 'printf "%s" '"'"'{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$w"'"}}'"'"' | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"' | sed -n 3p | _strip)
  # binary が混ざっても Line 3 が出る (ブランチ名が残っている) こと自体が要点
  [[ "$plain" == *"master"* || "$plain" == *"main"* ]]
  [[ "$plain" == *"+1"* ]]
}

@test "Git facts: 何日前のコミットでも時刻と msg の両方を出すこと" {
  # 7 日超で age を空にしていた頃は render_git の gate (`-n age && -n msg` / `elif -n age`) を
  # どちらも通らず **msg も連鎖して落ち Line 3 がブランチ名だけ**になっていた。
  # v1.78.0 で相対表記 (`2d`) → **ISO 8601 風の絶対時刻**に変更（ユーザー選択）。
  # 180 日以内は `08-17T13:13`、それより古ければ `2025-08-17`（古いコミットに分単位の意味は無い）。
  # **リテラルの日付を書かない** — 実行日に依存して flaky になるので `date` の出力と突き合わせる。
  _age_of() {  # $1=何日前
    local w="$BATS_TEST_TMPDIR/age$1" c="$BATS_TEST_TMPDIR/agec$1" e
    mkdir -p "$w"; git -C "$w" init -q
    e=$(( $(date +%s) - $1 * 86400 ))
    echo x > "$w/f"; git -C "$w" add f
    GIT_AUTHOR_DATE="$e +0000" GIT_COMMITTER_DATE="$e +0000" \
      git -C "$w" -c user.email=a@b -c user.name=a commit -qm "msg-marker"
    CLAUDE_STATUSLINE_CACHE_DIR="$c" /bin/bash -c 'printf "%s" '"'"'{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$w"'"}}'"'"' | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"' >/dev/null
    _wait_for_cache "$c/git"
    CLAUDE_STATUSLINE_CACHE_DIR="$c" /bin/bash -c 'printf "%s" '"'"'{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$w"'"}}'"'"' | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"' \
      | sed -n 3p | _strip
  }
  # **境界の 2 件だけ見る** — arm は 180 日で 2 つしかないので、同じ arm の中を複数試しても
  # pin は増えず repo 構築が 1 件 660ms 乗るだけ（`/simplify` 実測）。179/181 は境界値なので
  # 「どちらの arm に落ちるか」を直接押さえる
  local now want l
  now=$(date +%s)
  want=$(date -j -r $(( now - 179 * 86400 )) +"%m-%dT%H:%M")   # 180 日以内 = ISO 風・時刻つき
  l=$(_age_of 179); [[ "$l" == *"$want msg-marker"* ]] || { echo "179d want=$want got=$l" >&3; false; }
  want=$(date -j -r $(( now - 181 * 86400 )) +"%Y-%m-%d")      # 180 日超 = 年つき・時刻なし
  l=$(_age_of 181); [[ "$l" == *"$want msg-marker"* ]]         # 旧実装はここで msg ごと消えた
}

@test "Git facts: 同一dirの別セッションが相手のPR stateを表示しないこと(cross-session汚染)" {
  d="$BATS_TEST_TMPDIR/xsess"
  _run_pr() { CLAUDE_STATUSLINE_CACHE_DIR="$d" /bin/bash -c 'printf "%s" '"'"'{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$BATS_TEST_DIRNAME"'"}'"$1"',"context_window":{"used_percentage":48}}'"'"' | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"' | sed -n 3p; }
  _run_pr ',"pr":{"review_state":"approved"}' >/dev/null
  _wait_for_cache "$d/git"
  [[ "$(_run_pr ',"pr":{"review_state":"changes_requested"}')" == *"changes_requested"* ]]
  [[ "$(_run_pr ',"pr":{"review_state":"changes_requested"}')" != *"approved"* ]]
  [[ "$(_run_pr '')" != *"approved"* ]]            # PR 無しセッションに前セッションの値が出ない
  [[ "$(_run_pr '')" != *"changes_requested"* ]]
}

@test "Git facts: detached HEADでcold/warmのgateが一致すること(3パス問題)" {
  w="$BATS_TEST_TMPDIR/detached"; mkdir -p "$w"
  git -C "$w" init -q
  git -C "$w" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$w" checkout -q --detach
  d="$BATS_TEST_TMPDIR/detcache"
  _run() { CLAUDE_STATUSLINE_CACHE_DIR="$d" /bin/bash -c 'printf "%s" '"'"'{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$w"'","repo":{"host":"github.com","owner":"o","name":"r"}},"pr":{"review_state":"approved"},"context_window":{"used_percentage":48}}'"'"' | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"' | sed -n 3p | _strip; }
  cold=$(_run); _wait_for_cache "$d/git"; warm=$(_run)
  # detached ではどちらの経路でも gh: / PR state を出さない (gate が presenter 1 箇所にある)
  [[ "$cold" == *"HEAD@"* ]]; [[ "$warm" == *"HEAD@"* ]]
  [[ "$cold" != *"gh:"* ]];   [[ "$warm" != *"gh:"* ]]
  [[ "$cold" != *"approved"* ]]; [[ "$warm" != *"approved"* ]]
}

@test "Git facts: 非detachedならcold/warmどちらもgh:とPR stateを出すこと" {
  d="$BATS_TEST_TMPDIR/nondet"
  _run() { CLAUDE_STATUSLINE_CACHE_DIR="$d" /bin/bash -c 'printf "%s" '"'"'{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$BATS_TEST_DIRNAME"'","repo":{"host":"github.com","owner":"ist-j-ichikawa","name":"claude-code-statusline"}},"pr":{"review_state":"approved"},"context_window":{"used_percentage":48}}'"'"' | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"' | sed -n 3p; }
  cold=$(_run); _wait_for_cache "$d/git"; warm=$(_run)
  for o in "$cold" "$warm"; do
    # このリポ自身は dir 名 = repo 名なので repo 部は畳まれる (owner は残る)
    [[ "$o" == *"gh:"*"ist-j-ichikawa/"* ]]
    [[ "$o" == *"approved"* ]]
  done
}

@test "コンテキスト分母: 値が来ていれば常に%の直後に分母を出すこと" {
  _l4() { printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48,"context_window_size":'"$1"'}}' \
    | /bin/bash statusline-command.sh | tail -1 | _strip; }
  [[ "$(_l4 200000)"  == *"48%/200k"* ]]   # 既定値も出す (読み手が既定を記憶している前提にしない)
  [[ "$(_l4 1000000)" == *"48%/1M"* ]]     # ".0" を落として 1M (1.0M ではない)
  # 将来 1M 以外の拡張値が来ても黙って間違えないこと (旧実装は 500k=非表示 / 1.5M=/1M の誤表示)
  [[ "$(_l4 500000)"  == *"48%/500k"* ]]
  [[ "$(_l4 1500000)" == *"48%/1.5M"* ]]
  [[ "$(_l4 2000000)" == *"48%/2M"* ]]
  # 値が来ていない (旧 Claude Code) ときだけ無印
  [[ "$(_l4 0)"       != *"/"* ]]
}

@test "コンテキスト分母: 分母が%と同じ色になること(dimではない)" {
  # dim だと「% を修飾する分母」ではなく「別の補助情報」に見えるため一体化させている
  l4=$(printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48,"context_window_size":1000000}}' \
    | /bin/bash statusline-command.sh | tail -1)
  [[ "$l4" == *"38;5;82m"*"48%/1M"* ]]   # 使用率の色 (<80% = lime green) が %/分母を一括で包む
  [[ "$l4" != *$'\033[2m/1M'* ]]
}

@test "コンテキスト分母: display_name空(Bedrock)でも1Mが出ること(provider差の解消)" {
  l4=$(printf '%s' '{"model":{"id":"global.anthropic.claude-opus-5-v1:0","display_name":""},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48,"context_window_size":1000000}}' \
    | /bin/bash statusline-command.sh | tail -1 | _strip)
  [[ "$l4" == *"48%/1M"* ]]
}

@test "モデル色: contextを含まない括弧付きdisplay_nameは剥がさないこと" {
  result=$(echo '{"model":{"id":"claude-opus-5","display_name":"Opus 5 (preview)"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1 | _strip)
  [[ "$result" == *"Opus 5 (preview)"* ]]
}

# ============================================================================
# リセット時刻の整形 (format_reset + _memo_reset)
# main script 内の関数なので統合テストで pin する
# ============================================================================
@test "リセット時刻: 2回目以降はdateを叩かずメモから出すこと" {
  # リセットの epoch はリセットまで動かないのに、毎レンダー `date` を 2 回叩いていた
  # (実測 `date -j` 1 回 4.15ms、warm render の 15%)。epoch が一致する限り `date` を呼ばない。
  # **偽 `date` を PATH に置いて呼び出し回数を数える** — 表示だけ見ても「メモが効いているか」は
  # 分からず、fork が戻っても緑のままになる。
  local bin="$BATS_TEST_TMPDIR/rbin" log="$BATS_TEST_TMPDIR/rlog" c="$BATS_TEST_TMPDIR/rcache"
  _count_cmd "$bin" date "$log"
  local now j
  now=$(date +%s)
  j=$(jq -nc --argjson f $((now + 7200)) --argjson w $((now + 300000)) \
    '{model:{id:"claude-opus-5",display_name:"Opus 5"},workspace:{current_dir:"/tmp"},context_window:{used_percentage:48},rate_limits:{five_hour:{used_percentage:45,resets_at:$f},seven_day:{used_percentage:9,resets_at:$w}}}')
  _render() { printf '%s' "$j" | env PATH="$bin:$PATH" \
    CLAUDE_STATUSLINE_CACHE_DIR="$c" /bin/bash "$BATS_TEST_DIRNAME/statusline-command.sh"; }
  # 1 回目: 5h + 週間 の 2 回だけ (`_NOW` は v1.82.0 で jq 由来になったので `date` を使わない)
  : > "$log"; _render >/dev/null
  [[ "$(grep -c . "$log")" == "2" ]]
  [[ "$(grep -c -- '-j -r' "$log")" == "2" ]]
  # 2 回目: **1 度も叩かない** (メモが効き、時刻も jq から来る)
  : > "$log"; local out2; out2=$(_render)
  [[ "$(grep -c . "$log")" == "0" ]]
  [[ "$(grep -c -- '-j -r' "$log")" == "0" ]]
  # メモから出しても表示は同じであること (fork を消して値まで消えていないか)
  local want plain
  want=$(date -j -r $((now + 7200)) +"%H:%M")
  plain=$(printf '%s' "$out2" | _strip)
  [[ "$plain" == *"$want"* ]]
  # epoch が変われば再取得すること (リセットを跨いだ場合)
  j=$(jq -nc --argjson f $((now + 99999)) --argjson w $((now + 300000)) \
    '{model:{id:"claude-opus-5",display_name:"Opus 5"},workspace:{current_dir:"/tmp"},context_window:{used_percentage:48},rate_limits:{five_hour:{used_percentage:45,resets_at:$f},seven_day:{used_percentage:9,resets_at:$w}}}')
  : > "$log"; _render >/dev/null
  [[ "$(grep -c -- '-j -r' "$log")" == "1" ]]   # 5h だけ再取得、週間はメモ命中
}

@test "リセット時刻: 5h制限が絶対時刻(曜日なし)で出ること" {
  # **残り時間ではなく「何時まで」を出す** (v1.74.0、ユーザー選択)。曜日を付けないのが
  # 週間制限 (`土 16:00`) との区別になる。窓が最大 5 時間なので曜日は要らない。
  # `date -j` の出力と突き合わせる — リテラルの時刻を書くとテスト実行時刻に依存して flaky になる。
  now=$(date +%s)
  _lim() { printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":45,"resets_at":'"$1"'}}}' \
    | /bin/bash statusline-command.sh | tail -1 | _strip; }
  ep=$((now + 3750))
  want=$(date -j -r "$ep" +"%H:%M")
  [[ "$(_lim "$ep")" == *"$want"* ]]
  # 曜日は付かない (週間制限との区別)
  wday=$(date -j -r "$ep" +"%a")
  [[ "$(_lim "$ep")" != *"$wday"* ]]
}

@test "リセット時刻: タイムゾーン名を出さないこと(全部ローカル TZ なので冗長)" {
  # v1.78.0 で `JST 19:31` と出していたのをやめた（ユーザー選択）— 画面の時刻は例外なく
  # このマシンのローカル TZ なので、ゾーン名は情報を増やさない。どのゾーンかは docs に書く。
  # **リテラルの `JST` を書かない** — 実行環境の TZ に依存して flaky になるので `date` と比べる。
  local now fe se out zone
  now=$(date +%s); fe=$(( now + 3600 )); se=$(( now + 200000 ))
  zone=$(date -j -r "$fe" +"%Z")
  out=$(printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":16,"resets_at":'"$fe"'},"seven_day":{"used_percentage":9,"resets_at":'"$se"'}}}' \
    | /bin/bash statusline-command.sh | tail -1 | _strip)
  [[ "$out" == *"$(date -j -r "$fe" +"%H:%M")"* ]]           # 時刻そのものは出る
  [[ "$out" != *"$zone"* ]]                                  # ゾーン名は出ない
}

@test "リセット時刻: 5h制限が既に過ぎていたら now と出すこと" {
  # 過ぎた epoch を絶対時刻だけで出すと `14:03` が「これから 14:03 にリセット」と読めてしまい、
  # 実際は過ぎているのに「あと 23 時間」と誤読させる (残り時間表記だった頃の `now` を引き継ぐ)。
  # **メモには入れない** — 時間で変わる値を覚えると、過ぎた後も古い時刻が出続ける。
  local now past out
  now=$(date +%s); past=$((now - 60))
  _lim() { printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":45,"resets_at":'"$1"'}}}' \
    | /bin/bash statusline-command.sh | tail -1 | _strip; }
  out=$(_lim "$past")
  [[ "$out" == *"now"* ]]
  # 過ぎた時刻そのものは出さない
  [[ "$out" != *"$(date -j -r "$past" +"%H:%M")"* ]]
}

@test "リセット時刻: 週間制限が既に過ぎていても now と出すこと(5h と非対称にしない)" {
  # 曜日つきの `土 16:00` は数日前でも「これから」と読めるので、5h より誤読が強い。
  # arm を複製していた間はここに `now` が入っていなかった (`/simplify` 指摘)。
  local past out
  past=$(( $(date +%s) - 3600 ))
  out=$(printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"seven_day":{"used_percentage":9,"resets_at":'"$past"'}}}' \
    | /bin/bash statusline-command.sh | tail -1 | _strip)
  [[ "$out" == *"week:9%"* ]]
  [[ "$out" == *"now"* ]]
  [[ "$out" != *"$(date -j -r "$past" +"%a %H:%M")"* ]]
}

@test "リセット時刻: resets_at が無い/不正なら何も出さないこと" {
  _l4() { printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":45'"$1"'}}}' \
    | /bin/bash statusline-command.sh | tail -1 | _strip; }
  [[ "$(_l4 '')" == *"45%"* ]]; [[ "$(_l4 '')" != *":"* ]]            # resets_at 欠落
  [[ "$(_l4 ',"resets_at":null')" != *":"* ]]                          # null
}

@test "週間リセット: 曜日+時刻 (date -j) で出ること" {
  ep=$(( $(date +%s) + 200000 ))
  want=$(date -j -r "$ep" +"%a %H:%M")
  l4=$(printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"seven_day":{"used_percentage":9,"resets_at":'"$ep"'}}}' \
    | /bin/bash statusline-command.sh | tail -1 | _strip)
  [[ "$l4" == *"week:9%"* ]]
  [[ "$l4" == *"$want"* ]]
}

@test "install: --uninstall で2キーだけ外し、他のキーは残すこと" {
  s="$BATS_TEST_TMPDIR/uninst.json"
  printf '%s' '{"model":"opus","statusLine":{"type":"command","command":"/x/sl.sh","padding":2},"subagentStatusLine":{"type":"command","command":"/x/sub.sh"},"permissions":{"defaultMode":"auto"}}' > "$s"
  CLAUDE_SETTINGS="$s" /bin/bash "$BATS_TEST_DIRNAME/install.sh" --uninstall --yes >/dev/null
  [[ "$(jq -r '.statusLine // "absent"' "$s")" == "absent" ]]
  [[ "$(jq -r '.subagentStatusLine // "absent"' "$s")" == "absent" ]]
  [[ "$(jq -r .model "$s")" == "opus" ]]                        # 無関係キーは温存
  [[ "$(jq -r .permissions.defaultMode "$s")" == "auto" ]]
  [[ -n "$(echo "$s".bak.*)" ]]                                  # バックアップは取る
  # 冪等: 2 回目は「登録されていません」で終わる
  run env CLAUDE_SETTINGS="$s" /bin/bash "$BATS_TEST_DIRNAME/install.sh" --uninstall --yes
  [[ "$output" == *"登録されていません"* ]]
  # 外した後に再登録できる
  CLAUDE_SETTINGS="$s" /bin/bash "$BATS_TEST_DIRNAME/install.sh" --yes >/dev/null
  [[ "$(jq -r .statusLine.type "$s")" == "command" ]]
}

@test "install: --uninstall はスクリプトが無くても動くこと(clone を消した後の掃除)" {
  d="$BATS_TEST_TMPDIR/empty-repo"; mkdir -p "$d"
  cp "$BATS_TEST_DIRNAME/install.sh" "$d/"          # statusline 本体は置かない
  s="$BATS_TEST_TMPDIR/orphan.json"
  printf '%s' '{"statusLine":{"type":"command","command":"/gone/sl.sh"}}' > "$s"
  CLAUDE_SETTINGS="$s" /bin/bash "$d/install.sh" --uninstall --yes >/dev/null
  [[ "$(jq -r '.statusLine // "absent"' "$s")" == "absent" ]]
}

# ============================================================================
# model_key — tier+版の正規化 (v1.58.0)。model_color は正規形の完全一致で分岐する
# ============================================================================
@test "model_key: 全入力形式が正規形に畳まれること" {
  _k() { model_key k "$1" "${2:-}"; printf '%s' "$k"; }
  [[ "$(_k 'Opus 5 (1M context)' 'claude-opus-5[1m]')" == "opus 5" ]]
  [[ "$(_k 'Opus' 'claude-opus-5')"                    == "opus 5" ]]   # display_name に版が無くても id で拾う
  [[ "$(_k 'OPUS 4.6' 'claude-opus-4-6')"              == "opus 4.6" ]] # 大文字でも正規形は小文字
  [[ "$(_k 'Sonnet' 'claude-sonnet-4-5')"              == "sonnet 4.5" ]]
  [[ "$(_k 'x' 'global.anthropic.claude-opus-5-v1:0')" == "opus 5" ]]   # Bedrock: -v1:0 を版と誤読しない
  [[ "$(_k 'Fable 5' 'claude-fable-5')"                == "fable 5" ]]
  [[ "$(_k 'gpt-5' '')"                                == "" ]]         # 未知は空 → 無色
  [[ "$(_k '' '')"                                     == "" ]]
}

@test "model_key: サポート下限(4.x)未満の旧形式でも tier 色に落ちるだけで壊れないこと" {
  # 3.x 系は全廃止済みなので専用分岐を持たない。版スロットに日付が入るが tier は拾えるので
  # 「無色化」も「文字化け」も起きない (Bedrock で古い inference profile を pin した人向けの保証)
  model_key k 'claude-3-5-sonnet-20241022' ''
  [[ "$k" == sonnet* ]]
  model_color c 'claude-3-5-sonnet-20241022' ''
  [[ "$c" == *"38;5;79m"* ]]    # generic teal
  model_key k 'claude-3-5-haiku-20241022' ''
  [[ "$k" == haiku* ]]
  model_color c 'claude-3-5-haiku-20241022' ''
  [[ "$c" == *"38;5;183m"* ]]   # lavender
  # 空白形の旧 display_name は版スロットごと落ちて素の tier になる (id 形とは畳み方が違う)
  model_key k 'Claude 3.5 Sonnet' ''
  [[ "$k" == "sonnet" ]]
  model_color c 'Claude 3.5 Sonnet' ''
  [[ "$c" == *"38;5;79m"* ]]    # 同じ generic teal に着地する
  # 日付は版スロットに入れない — 正規形は常に `tier N[.N]`。これがあるので arm は完全一致 1 行で足る
  model_key k 'claude-opus-4-20250514' ''
  [[ "$k" == "opus 4" ]]
  model_color c 'claude-opus-4-20250514' ''
  [[ "$c" == *"38;5;173m"* ]]   # coral (Opus 4.x)
  # 同じモデルが display_name 形でも dated id 形でも同一キーに畳まれること
  model_key k2 'Opus 4' 'claude-opus-4-20250514'
  [[ "$k2" == "$k" ]]
  # **dated な 5 系が多色 arm に着地すること** — ここが実在の危険。日付を拾うと generic 単色に落ちる
  model_key k 'claude-opus-5-20260101' ''
  [[ "$k" == "opus 5" ]]
  model_color c 'claude-opus-5-20260101' ''
  [[ "$c" == *"38;5;130m"* ]]   # gradient の先頭ストップ (単色 coral 173 ではない)
  model_key k 'claude-sonnet-5-20260101' ''
  [[ "$k" == "sonnet 5" ]]
  model_color c 'claude-sonnet-5-20260101' ''
  [[ "$c" == *"38;5;28m"* ]]    # gradient の先頭ストップ
  # 本物の minor 版は残ること (日付判定が版を食わない)
  model_key k 'claude-opus-5-1' ''
  [[ "$k" == "opus 5.1" ]]
  # 日付付きの**現行** id は版として正しく畳めること (下限を上げても壊していない)
  model_key k 'claude-haiku-4-5-20251001' ''
  [[ "$k" == "haiku 4.5" ]]
  model_key k 'claude-sonnet-4-5-20250929' ''
  [[ "$k" == "sonnet 4.5" ]]
}

@test "model_key: 版なし tier は generic 色に落ちること" {
  model_key k 'Opus' ''; [[ "$k" == "opus" ]]
  model_color c 'Opus' ''; [[ "$c" == *"38;5;173m"* ]]   # coral (4.x 扱い)
  model_key k 'Sonnet' ''; [[ "$k" == "sonnet" ]]
  model_color c 'Sonnet' ''; [[ "$c" == *"38;5;79m"* ]]  # teal
}

@test "多色描画: 1文字のモデル名でも落ちないこと(bash 3.2 の三項演算子)" {
  # bash 3.2 は ((cond ? a/0 : 0)) で未選択の分岐も評価し division by 0 → set -u で全消えになる
  run /bin/bash -c 'printf "%s" "{\"model\":{\"id\":\"claude-opus-5\",\"display_name\":\"O\"},\"workspace\":{\"current_dir\":\"/tmp\"},\"context_window\":{\"used_percentage\":48}}" | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"'
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"38;5;130mO"* ]]
  [[ "$output" != *"division by 0"* ]]
}
