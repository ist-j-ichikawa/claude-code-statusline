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
}

# build_git の background cache 書き込み完了まで polling (最大 ~2秒)
# 4 テストで `sleep` 固定にすると合計数秒のオーバーヘッドになるため
_wait_for_cache() {
  local cache_dir=$1 i f
  for i in {1..20}; do
    # atomic 書き込みの中間ファイル (.tmp-<pid>) は完成キャッシュではないので無視する
    for f in "$cache_dir"/*; do
      [[ -e "$f" && "$f" != *.tmp* ]] && return 0
    done
    sleep 0.1
  done
  return 1
}

# _wait_for_file PATH [-s] — 背景書き込みの完了を polling で待つ (固定 sleep を置かないため)。
# `-s` を付けると「存在する」ではなく「非空」まで待つ。
_wait_for_file() {
  local f=$1 mode=${2:-} i
  for i in {1..30}; do
    if [[ "$mode" == "-s" ]]; then [[ -s "$f" ]] && return 0
    else                           [[ -e "$f" ]] && return 0; fi
    sleep 0.1
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
  [[ "$(printf '%s' "$l1" | sed $'s/\033\\[[0-9;]*m//g')" == *"Opus 5"* ]]
  # 先頭文字=パレット先頭 (130)、末尾文字=パレット末尾 (215)
  [[ "$l1" == *"38;5;130mO"* ]]
  [[ "$l1" == *"38;5;215m5"* ]]
  # 分母は Line 4 の % の直後に出る
  [[ "$(printf '%s' "$result" | tail -1 | sed $'s/\033\\[[0-9;]*m//g')" == *"48%/1M"* ]]
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
@test "Effort: effortレベル名がlight purple(38;5;105)で表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-7","display_name":"Opus 4.7"},"version":"2.1.128","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"effort":{"level":"high"}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[38;5;105m'"high"* ]]
  [[ "$result" != *"effort:"* ]]
}

@test "Effort: 全レベルで同色(level severityは文字で読み分け)になること" {
  low=$(echo '{"model":{"id":"claude-opus-4-7","display_name":"Opus 4.7"},"version":"2.1.128","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"effort":{"level":"low"}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  max=$(echo '{"model":{"id":"claude-opus-4-7","display_name":"Opus 4.7"},"version":"2.1.128","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"effort":{"level":"max"}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$low" == *$'\033[38;5;105m'"low"* ]]
  [[ "$max" == *$'\033[38;5;105m'"max"* ]]
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

@test "Line4: extra-usage キャッシュがあると extra:\$X.XX が表示されること" {
  mkdir -p $CLAUDE_STATUSLINE_CACHE_DIR
  echo 214 > $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '4p')
  rm -f $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  [[ "$result" == *'extra:$2.14'* ]]
}

@test "Line4: extra-usage データがないとき extra: が表示されないこと" {
  # setup() で usage_spend は削除済み・NO_NET で fetch も走らない
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" != *'extra:'* ]]
}

@test "Line4: Bedrockでは extra-usage を取得も表示もしないこと" {
  mkdir -p $CLAUDE_STATUSLINE_CACHE_DIR
  echo 500 > $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  result=$(echo '{"model":{"id":"global.anthropic.claude-opus-4-6-v1","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '4p')
  rm -f $CLAUDE_STATUSLINE_CACHE_DIR/usage_spend
  [[ "$result" != *'extra:'* ]]
}

@test "Line4: Anthropicでレートリミットが表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.80","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":4070908800},"seven_day":{"used_percentage":12,"resets_at":4071427200}}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" == *"35%"* ]]
  [[ "$result" == *"week:12%"* ]]
}

@test "Line4: rate_limitsがない旧CCでも4行出力されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.79","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null)
  line_count=$(echo "$result" | grep -c . || echo 0)
  [[ "$line_count" -eq 4 ]]
}

@test "Line4: rate_limitsのused_percentageがfloatでもroundされること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.80","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":35.7,"resets_at":4070908800}}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '4p')
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
  # gh: のみ dim、owner/repo は RST 後の通常輝度（ローカル dir 名と origin 名の食い違い判別用）
  [[ "$result" == *"${DIM}gh:${RST}ist-j-ichikawa/claude-code-statusline"* ]]
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

@test "Git: workspace.repo(Claude Code 2.1.145+)がコールドスタートでもgh:を表示すること" {
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  rm -f "$cache_dir"/* 2>/dev/null
  # cache を消して即座に sed -n '3p' する = cold start。git remote get-url を介さず stdin から gh: が出る
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" == *"gh:${RST}acme/widgets"* ]]
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

@test "Git: workspace.repoの非GitHubホスト(gitlab.com等)ではgh:が表示されないこと" {
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"gitlab.com","owner":"acme","name":"widgets"}},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" != *"gh:"* ]]
}

# ============================================================================
# vim mode badge — NORMAL は非表示、INSERT/VISUAL/VISUAL LINE は bg 色付きで Line 1 最左に
# ============================================================================
@test "vim: INSERTモードで緑バッジが表示されること" {
  result=$(echo '{"model":{"id":"t","display_name":"T"},"version":"2.1.146","workspace":{"current_dir":"/tmp"},"vim":{"mode":"INSERT"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  # bg lime-green (48;5;148, gruvbox-ish) + bold + INSERT テキストが含まれること
  [[ "$result" == *$'\033[1;30;48;5;148m INSERT '* ]]
}

@test "vim: VISUALモードで橙バッジが表示されること" {
  result=$(echo '{"model":{"id":"t","display_name":"T"},"version":"2.1.146","workspace":{"current_dir":"/tmp"},"vim":{"mode":"VISUAL"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[1;30;48;5;214m VISUAL '* ]]
}

@test "vim: VISUAL LINEはV-LINEに短縮して同じ橙バッジで表示されること" {
  result=$(echo '{"model":{"id":"t","display_name":"T"},"version":"2.1.146","workspace":{"current_dir":"/tmp"},"vim":{"mode":"VISUAL LINE"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[1;30;48;5;214m V-LINE '* ]]
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

@test "Git: 非GitHub origin(GitLab等)ではgh:が表示されないこと" {
  local cache_dir="$CLAUDE_STATUSLINE_CACHE_DIR/git"
  local tmp_repo
  tmp_repo=$(mktemp -d)
  ( cd "$tmp_repo" && git init -q \
    && git -c user.name=t -c user.email=t@t commit --allow-empty -q -m init \
    && git remote add origin "git@gitlab.com:acme/widgets.git" )
  rm -f "$cache_dir"/* 2>/dev/null
  echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh >/dev/null 2>&1
  _wait_for_cache "$cache_dir"
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '3p')
  rm -rf "$tmp_repo"
  [[ "$result" != *"gh:"* ]]
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

@test "セッション: マーカーが無ければ出自バッジを出さないこと" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"session_name":"ふつうの名前","version":"2.1.220","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" != *"branch"* ]]
  [[ "$result" != *"fork"* ]]
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
@test "Line4順番: 5hリミットがcontextより左に表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.80","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":4070908800}}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '4p')
  # 35% (5h) should appear before 48% (context)
  five_pos="${result%%35%*}"
  ctx_pos="${result%%48%*}"
  [[ ${#five_pos} -lt ${#ctx_pos} ]]
}

@test "Line4順番: weeklyがcontextより右に表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.80","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":4070908800},"seven_day":{"used_percentage":12,"resets_at":4071427200}}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | sed -n '4p')
  ctx_pos="${result%%48%*}"
  week_pos="${result%%week:*}"
  [[ ${#ctx_pos} -lt ${#week_pos} ]]
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

@test "Subagent: effortはレベル文字列をEFFORT色でモデルの直後に出すこと" {
  # 位置まで pin する — 部分一致だけだと effort の add を status/worktree の後ろに動かしても緑のままで、
  # docs の「モデル → effort → 状態 → 🌲」の順序が固定されない
  c=$(echo '{"columns":120,"tasks":[{"id":"t","label":"x","model":"claude-sonnet-4-6","effort":"low","status":"needs_input","cwd":"/r/.claude/worktrees/wt"}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content | sed $'s/\033\\[[0-9;]*m//g')
  [[ "$c" == "x  Sonnet 4.6  low  needs_input  🌲wt" ]]
  # 色は Line 1 の effort と同じ light purple
  c2=$(echo '{"columns":120,"tasks":[{"id":"t","label":"x","model":"claude-sonnet-4-6","effort":"low"}]}' \
    | /bin/bash subagent-statusline-command.sh | jq -r .content)
  [[ "$c2" == *$'\033[38;5;105m'"low"* ]]
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
  [[ "$(printf '%s' "$c" | sed $'s/\033\\[[0-9;]*m//g')" == *"Opus 5"* ]]   # モデルは出たまま
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
    plain=$(printf '%s' "$c" | sed $'s/\033\\[[0-9;]*m//g')
    [[ "$plain" == "x  Sonnet 4.6" ]]
  done
  # ネストした {"level":..} 形で来ても level を拾う (主 statusline の effort.level と同形)
  c=$(_c '{"level":"low"}')
  [[ "$c" == *$'\033[38;5;105m'"low"* ]]
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
  CLAUDE_SETTINGS="$s" /bin/bash "$BATS_TEST_DIRNAME/install.sh" --yes >/dev/null
  [[ "$(jq -r .statusLine.command "$s")" == "/bin/bash $BATS_TEST_DIRNAME/statusline-command.sh" ]]
  [[ "$(jq -r .subagentStatusLine.command "$s")" == "/bin/bash $BATS_TEST_DIRNAME/subagent-statusline-command.sh" ]]
  # 未設定なら推奨値が入る
  [[ "$(jq -r .statusLine.refreshInterval "$s")" == "30" ]]
  [[ "$(jq -r .statusLine.hideVimModeIndicator "$s")" == "true" ]]
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
    | /bin/bash subagent-statusline-command.sh | jq -r .content | sed $'s/\033\\[[0-9;]*m//g')
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
  _strip() { sed $'s/\033\\[[0-9;]*m//g'; }
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
    | /bin/bash statusline-command.sh | tail -1 | sed $'s/\033\\[[0-9;]*m//g')
  # 区切りごと pin する — *"3h"* だと 13h/23h/3h24m も通る緩い部分一致になる
  [[ "$l4" == *" 3h "*'$18.07'* ]]
}

@test "経過時間: 1時間未満もLine 4に届くこと(60秒ゲートの統合確認)" {
  # fmt_elapsed の単体テストだけだと、Line 4 側のゲートが >= 60 から >= 3600 に退行しても緑のまま。
  # m 帯が実際に描画に乗ることはフルスクリプトで押さえる
  l4=$(printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"cost":{"total_cost_usd":0.42,"total_duration_ms":2460000}}' \
    | /bin/bash statusline-command.sh | tail -1 | sed $'s/\033\\[[0-9;]*m//g')
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
  [[ ! -s "$d/subscription" ]]        # 空でよい — display は has_val で非表示に倒れる
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
  [[ "$(<"$_stub_cache/subscription")" == "enterprise" ]]
  # 2 回目のレンダーでキャッシュから読んで表示に載ること
  run env "${_stub_pre[@]:1}" /bin/bash -c \
    'printf "%s" "$1" | /bin/bash "$2"' _ "$j" "$BATS_TEST_DIRNAME/statusline-command.sh"
  [[ "$output" == *"Anthropic(enterprise)"* ]]
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
@test "Git facts: キャッシュにANSIもstdin由来値も入らないこと" {
  d="$BATS_TEST_TMPDIR/factcache"
  p='{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$BATS_TEST_DIRNAME"'"},"pr":{"review_state":"approved"},"context_window":{"used_percentage":48}}'
  CLAUDE_STATUSLINE_CACHE_DIR="$d" /bin/bash -c 'printf "%s" '"'$p'"' | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"' >/dev/null
  _wait_for_cache "$d/git"
  local facts; facts=$(cat "$d"/git/*-v2)
  [[ "$facts" != *$'\033'* ]]        # レンダリング済み ANSI を置かない
  [[ "$facts" != *"approved"* ]]     # stdin 由来値 (PR state) を置かない = 別セッションに漏れない
  [[ "$facts" == *$'\037'* ]]        # US 区切りの facts である
}

@test "Git facts: 何日前のコミットでも age と msg の両方を出すこと" {
  # 7 日超で age を空にしていた頃は render_git の gate (`-n age && -n msg` / `elif -n age`) を
  # どちらも通らず **msg も連鎖して落ち Line 3 がブランチ名だけ**になっていた。
  # 単位は常に 1 つで m/h/d/w/mo/y。
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
      | sed -n 3p | sed $'s/\033\\[[0-9;]*m//g'
  }
  l=$(_age_of 2);   [[ "$l" == *" 2d msg-marker"* ]]
  l=$(_age_of 20);  [[ "$l" == *" 2w msg-marker"* ]]    # 旧実装はここで msg ごと消えた
  l=$(_age_of 60);  [[ "$l" == *" 2mo msg-marker"* ]]
  l=$(_age_of 400); [[ "$l" == *" 1y msg-marker"* ]]
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
  _run() { CLAUDE_STATUSLINE_CACHE_DIR="$d" /bin/bash -c 'printf "%s" '"'"'{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$w"'","repo":{"host":"github.com","owner":"o","name":"r"}},"pr":{"review_state":"approved"},"context_window":{"used_percentage":48}}'"'"' | /bin/bash "'"$BATS_TEST_DIRNAME"'/statusline-command.sh"' | sed -n 3p | sed $'s/\033\\[[0-9;]*m//g'; }
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
    [[ "$o" == *"gh:"*"ist-j-ichikawa/claude-code-statusline"* ]]
    [[ "$o" == *"approved"* ]]
  done
}

@test "コンテキスト分母: 値が来ていれば常に%の直後に分母を出すこと" {
  _l4() { printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48,"context_window_size":'"$1"'}}' \
    | /bin/bash statusline-command.sh | tail -1 | sed $'s/\033\\[[0-9;]*m//g'; }
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
    | /bin/bash statusline-command.sh | tail -1 | sed $'s/\033\\[[0-9;]*m//g')
  [[ "$l4" == *"48%/1M"* ]]
}

@test "モデル色: contextを含まない括弧付きdisplay_nameは剥がさないこと" {
  result=$(echo '{"model":{"id":"claude-opus-5","display_name":"Opus 5 (preview)"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | /bin/bash statusline-command.sh 2>/dev/null | head -1 | sed $'s/\033\\[[0-9;]*m//g')
  [[ "$result" == *"Opus 5 (preview)"* ]]
}

# ============================================================================
# リセット時刻の整形 (format_reset_remaining / format_reset_absolute)
# main script 内の関数なので統合テストで pin する
# ============================================================================
@test "リセット残: 5h制限の残り時間が H:MM で出ること" {
  now=$(date +%s)
  _l4() { printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":45,"resets_at":'"$1"'}}}' \
    | /bin/bash statusline-command.sh | tail -1 | sed $'s/\033\\[[0-9;]*m//g'; }
  # オフセットは**分の中央**に置く。統一秒は 2 回読まれる (テストの date と
  # statusline-command.sh の readonly _NOW) ので、境界ちょうど (+300) だと 1 秒ずれて
  # 0:04 に落ちて flaky になる。format_reset_remaining は切り捨てなので余裕を取る
  [[ "$(_l4 $((now + 3750)))" == *"1:02"* ]]    # 1時間2分30秒後
  [[ "$(_l4 $((now + 330)))"  == *"0:05"* ]]    # 5分30秒後 → 0 埋め
  [[ "$(_l4 $((now - 60)))"   == *"now"* ]]     # 過ぎていたら now
}

@test "リセット残: resets_at が無い/不正なら何も出さないこと" {
  _l4() { printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":45'"$1"'}}}' \
    | /bin/bash statusline-command.sh | tail -1 | sed $'s/\033\\[[0-9;]*m//g'; }
  [[ "$(_l4 '')" == *"45%"* ]]; [[ "$(_l4 '')" != *":"* ]]            # resets_at 欠落
  [[ "$(_l4 ',"resets_at":null')" != *":"* ]]                          # null
}

@test "週間リセット: 曜日+時刻 (date -j) で出ること" {
  ep=$(( $(date +%s) + 200000 ))
  want=$(date -j -r "$ep" +"%a %H:%M")
  l4=$(printf '%s' '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"seven_day":{"used_percentage":9,"resets_at":'"$ep"'}}}' \
    | /bin/bash statusline-command.sh | tail -1 | sed $'s/\033\\[[0-9;]*m//g')
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
