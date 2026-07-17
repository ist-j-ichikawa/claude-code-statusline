#!/usr/bin/env bats
# statusline-command.sh テスト
# 実行: bats test.bats

# --- セットアップ: ヘルパー関数のみを読み込む ---
setup() {
  export COLUMNS=120
  export RST=$'\033[0m' GRN=$'\033[32m' YLW=$'\033[33m' RED=$'\033[31m'
  export CTX_OK=$'\033[38;5;82m'
  export DIM=$'\033[2m'
  export GIT=$'\033[38;5;202m'
  export ANTH=$'\033[38;5;180m' BDCK=$'\033[38;5;72m' VTEX=$'\033[38;5;33m' FNDY=$'\033[38;5;39m'
  export CORAL=$'\033[38;5;173m' TEAL=$'\033[38;5;79m' AMBER=$'\033[38;5;214m' LAVENDER=$'\033[38;5;183m'
  export AGENT=$'\033[38;5;213m' DIMVER=$'\033[38;5;248m'
  export _NOW=$(date +%s)
  # extra-usage の背景 curl を止めてテストを決定的にし、共有キャッシュ汚染も掃除する
  export CLAUDE_STATUSLINE_NO_NET=1
  rm -f /tmp/ist-j-ichikawa-claude-statusline/usage_spend 2>/dev/null || true
  eval "$(sed -n '/^# --- Helpers ---$/,/^# --- Credentials/{ /^# --- Credentials/d; p; }' statusline-command.sh)"
}

# build_git の background cache 書き込み完了まで polling (最大 ~2秒)
# 4 テストで `sleep` 固定にすると合計数秒のオーバーヘッドになるため
_wait_for_cache() {
  local cache_dir=$1 i f
  for i in {1..20}; do
    # atomic 書き込みの中間ファイル (.tmp) は完成キャッシュではないので無視する
    for f in "$cache_dir"/*; do
      [[ -e "$f" && "$f" != *.tmp ]] && return 0
    done
    sleep 0.1
  done
  return 1
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
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"38;5;173"*"Opus 4.6"* ]]
}

@test "モデル色: Sonnet 4.6がティールで表示されること" {
  result=$(echo '{"model":{"id":"claude-sonnet-4-6","display_name":"Sonnet 4.6"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"38;5;79"*"Sonnet 4.6"* ]]
}

@test "モデル色: Sonnet 4.5がアンバーで表示されること" {
  result=$(echo '{"model":{"id":"claude-sonnet-4-5","display_name":"Sonnet 4.5"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"38;5;214"*"Sonnet 4.5"* ]]
}

@test "モデル色: Sonnet 5が緑グラデーション(文字ごとに色が変わる)で表示されること" {
  result=$(echo '{"model":{"id":"claude-sonnet-5","display_name":"Sonnet 5"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  # 緑パレットを1回スイープ: 先頭 28(濃緑) → 末尾 154(黄緑)
  [[ "$result" == *"38;5;28mS"* ]]
  [[ "$result" == *"38;5;154m5"* ]]
}

@test "モデル色: Sonnet 5判定が Sonnet 4.5 に誤マッチしないこと" {
  result=$(echo '{"model":{"id":"claude-sonnet-4-5","display_name":"Sonnet 4.5"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  # amber フラットのままで、グラデーション(28)にならないこと
  [[ "$result" == *"38;5;214"*"Sonnet 4.5"* ]]
  [[ "$result" != *"38;5;28m"* ]]
}

@test "モデル色: Haikuがラベンダーで表示されること" {
  result=$(echo '{"model":{"id":"claude-haiku-4-5","display_name":"Haiku 4.5"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"38;5;183"*"Haiku 4.5"* ]]
}

@test "モデル色: Fableが蝶標本パレット(文字ごとに色が変わる)で表示されること" {
  result=$(echo '{"model":{"id":"claude-fable-5","display_name":"Fable 5"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  # 各文字が蝶標本パレットで着色される: F=178, a=172, b=130 ...
  [[ "$result" == *"38;5;178mF"*"38;5;172ma"*"38;5;130mb"* ]]
}

@test "モデル色: 大文字混在のdisplay_nameでも正しい色になること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"OPUS 4.6"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"38;5;173"*"OPUS 4.6"* ]]
}

@test "モデル色: nocasematchがスクリプト外に漏れないこと" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null; shopt -q nocasematch && echo "LEAKED" || echo "OK")
  [[ "$result" == *"OK" ]]
}

# ============================================================================
# 統合テスト: プロバイダー検出 — 正しいプロバイダーが表示されること
# ============================================================================
@test "プロバイダー: model_idのglobal.プレフィックスでBedrockと検出すること" {
  result=$(echo '{"model":{"id":"global.anthropic.claude-opus-4-6-v1","display_name":""},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"Bedrock"* ]]
}

@test "プロバイダー: model_idのus-gov.プレフィックス(GovCloud)でBedrockと検出すること" {
  result=$(echo '{"model":{"id":"us-gov.anthropic.claude-opus-4-6-v1","display_name":""},"version":"2.1.174","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"Bedrock"* ]]
}

@test "プロバイダー: CLAUDE_CODE_USE_MANTLE環境変数でBedrockと検出すること" {
  result=$(CLAUDE_CODE_USE_MANTLE=1 bash -c 'echo "{\"model\":{\"id\":\"claude-opus\",\"display_name\":\"Opus 4.6\"},\"version\":\"2.1.94\",\"workspace\":{\"current_dir\":\"/tmp\"},\"context_window\":{\"used_percentage\":48}}" | bash statusline-command.sh 2>/dev/null | head -1')
  [[ "$result" == *"Bedrock"* ]]
}

@test "プロバイダー: CLAUDE_CODE_USE_VERTEX環境変数でVertexと検出すること" {
  result=$(CLAUDE_CODE_USE_VERTEX=1 bash -c 'echo "{\"model\":{\"id\":\"claude-opus\",\"display_name\":\"Opus 4.6\"},\"version\":\"2.1.76\",\"workspace\":{\"current_dir\":\"/tmp\"},\"context_window\":{\"used_percentage\":48}}" | bash statusline-command.sh 2>/dev/null | head -1')
  [[ "$result" == *"Vertex"* ]]
}

# ============================================================================
# 統合テスト: Effort & Thinking — 推論努力と拡張思考が正しく表示されること
# ============================================================================
@test "Effort: effortレベル名がlight purple(38;5;105)で表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-7","display_name":"Opus 4.7"},"version":"2.1.128","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"effort":{"level":"high"}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[38;5;105m'"high"* ]]
  [[ "$result" != *"effort:"* ]]
}

@test "Effort: 全レベルで同色(level severityは文字で読み分け)になること" {
  low=$(echo '{"model":{"id":"claude-opus-4-7","display_name":"Opus 4.7"},"version":"2.1.128","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"effort":{"level":"low"}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  max=$(echo '{"model":{"id":"claude-opus-4-7","display_name":"Opus 4.7"},"version":"2.1.128","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"effort":{"level":"max"}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$low" == *$'\033[38;5;105m'"low"* ]]
  [[ "$max" == *$'\033[38;5;105m'"max"* ]]
}

@test "Thinking: thinking.enabled=trueでlight cyan(38;5;117)のthinkが表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-7","display_name":"Opus 4.7"},"version":"2.1.128","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"thinking":{"enabled":true}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[38;5;117m'*"think"* ]]
}

@test "Effort/Thinking: 両方ありで半角スペース区切りで結合されること(中黒なし)" {
  result=$(echo '{"model":{"id":"claude-opus-4-7","display_name":"Opus 4.7"},"version":"2.1.128","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"effort":{"level":"high"},"thinking":{"enabled":true}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"high"*"think"* ]]
  [[ "$result" != *"·"*"think"* ]]
  [[ "$result" != *"effort:"* ]]
}

@test "Effort/Thinking: 旧 Claude Code(両キーなし)でeffort/thinkが表示されないこと" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.118","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" != *"effort:"* ]]
  [[ "$result" != *"think"* ]]
}

@test "Thinking: thinking.enabled=falseでthinkが表示されないこと" {
  result=$(echo '{"model":{"id":"claude-opus-4-7","display_name":"Opus 4.7"},"version":"2.1.128","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"thinking":{"enabled":false}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" != *"think"* ]]
}

# ============================================================================
# 統合テスト: Line 3 — コンテキスト + プロバイダー別表示が正しいこと
# ============================================================================
@test "Line4: トークン数が表示されないこと" {
  result=$(echo '{"model":{"id":"global.anthropic.claude-opus-4-6-v1","display_name":"Opus 4.6"},"version":"2.1.77","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48,"total_input_tokens":125000,"total_output_tokens":8500}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" != *"↑"* ]]
  [[ "$result" != *"↓"* ]]
  [[ "$result" != *"125"* ]]
}

@test "Line4: cost.total_cost_usdがdimの\$表示で出ること" {
  result=$(echo '{"model":{"id":"claude-fable-5","display_name":"Fable 5"},"version":"2.1.173","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"cost":{"total_cost_usd":4.83}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" == *'$4.83'* ]]
}

@test "Line4: コストがセント単位に四捨五入されること" {
  result=$(echo '{"model":{"id":"claude-fable-5","display_name":"Fable 5"},"version":"2.1.173","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"cost":{"total_cost_usd":0.426}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" == *'$0.43'* ]]
}

@test "Line4: コストが0のとき表示されないこと" {
  result=$(echo '{"model":{"id":"claude-fable-5","display_name":"Fable 5"},"version":"2.1.173","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"cost":{"total_cost_usd":0}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" != *'$'* ]]
}

@test "Line4: costフィールドがない旧Claude Codeで\$が表示されないこと" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" != *'$'* ]]
}

@test "Line4: extra-usage キャッシュがあると extra:\$X.XX が表示されること" {
  mkdir -p /tmp/ist-j-ichikawa-claude-statusline
  echo 214 > /tmp/ist-j-ichikawa-claude-statusline/usage_spend
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  rm -f /tmp/ist-j-ichikawa-claude-statusline/usage_spend
  [[ "$result" == *'extra:$2.14'* ]]
}

@test "Line4: extra-usage データがないとき extra: が表示されないこと" {
  # setup() で usage_spend は削除済み・NO_NET で fetch も走らない
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" != *'extra:'* ]]
}

@test "Line4: Bedrockでは extra-usage を取得も表示もしないこと" {
  mkdir -p /tmp/ist-j-ichikawa-claude-statusline
  echo 500 > /tmp/ist-j-ichikawa-claude-statusline/usage_spend
  result=$(echo '{"model":{"id":"global.anthropic.claude-opus-4-6-v1","display_name":"Opus 4.6"},"version":"2.1.198","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  rm -f /tmp/ist-j-ichikawa-claude-statusline/usage_spend
  [[ "$result" != *'extra:'* ]]
}

@test "Line4: Anthropicでレートリミットが表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.80","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":4070908800},"seven_day":{"used_percentage":12,"resets_at":4071427200}}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" == *"35%"* ]]
  [[ "$result" == *"week:12%"* ]]
}

@test "Line4: rate_limitsがない旧CCでも4行出力されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.79","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null)
  line_count=$(echo "$result" | grep -c . || echo 0)
  [[ "$line_count" -eq 4 ]]
}

@test "Line4: rate_limitsのused_percentageがfloatでもroundされること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.80","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":35.7,"resets_at":4070908800}}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" == *"36%"* ]]
}

# ============================================================================
# 統合テスト: Line 3 — Git情報が専用行に表示されること
# ============================================================================
@test "Git: git管理外ディレクトリでno gitと表示すること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" == *"no git"* ]]
}

@test "Git: gitリポジトリのコールドスタートでno gitを表示しないこと" {
  # Clear cache to simulate cold start
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$(pwd)"'"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" != *"no git"* ]]
}

@test "Git: 空リポジトリ(.invalid HEAD)を(empty)に翻訳すること" {
  # ghq get 失敗残骸 / git init 直後 / clone aborted を再現:
  # HEAD は ref: refs/heads/.invalid だが refs/ も objects/ も空
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  local tmp_repo
  tmp_repo=$(mktemp -d)
  mkdir -p "$tmp_repo/.git/refs" "$tmp_repo/.git/objects"
  printf 'ref: refs/heads/.invalid\n' > "$tmp_repo/.git/HEAD"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  rm -rf "$tmp_repo"
  [[ "$result" == *"(empty)"* ]]
  [[ "$result" != *".invalid"* ]]
  # (empty) は dim、Git オレンジでは無いこと
  [[ "$result" == *"${DIM}(empty)${RST}"* ]]
}

@test "Git: コールドスタートでブランチ名を即時表示すること" {
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$(pwd)"'"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" == *"main"* || "$result" == *"master"* || "$result" == *"HEAD@"* ]]
}

@test "Git: ブランチ名がGitオレンジ(38;5;202)で表示されること" {
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$(pwd)"'"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  # ブランチ名が Git オレンジ(38;5;202m)で着色されていること
  [[ "$result" == *$'\033[38;5;202m'* ]]
}

@test "Git: GitHub originでgh:プレフィックスがdim・owner/repoが通常輝度でブランチ前に表示されること" {
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  rm -f "$cache_dir"/* 2>/dev/null
  # cold start: build_git の background が cache を書く
  echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$(pwd)"'"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh >/dev/null 2>&1
  _wait_for_cache "$cache_dir"
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$(pwd)"'"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  # gh: のみ dim、owner/repo は RST 後の通常輝度（ローカル dir 名と origin 名の食い違い判別用）
  [[ "$result" == *"${DIM}gh:${RST}ist-j-ichikawa/claude-code-statusline"* ]]
  # gh: 部分が GIT オレンジのブランチ名より左にあること
  gh_pos="${result%%gh:*}"
  branch_pos="${result%%${GIT}*}"
  [[ ${#gh_pos} -lt ${#branch_pos} ]]
}

@test "Git: origin未設定リポではgh:が表示されないこと" {
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  local tmp_repo
  tmp_repo=$(mktemp -d)
  ( cd "$tmp_repo" && git init -q && git -c user.name=t -c user.email=t@t commit --allow-empty -q -m init )
  rm -f "$cache_dir"/* 2>/dev/null
  echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh >/dev/null 2>&1
  _wait_for_cache "$cache_dir"
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  rm -rf "$tmp_repo"
  [[ "$result" != *"gh:"* ]]
}

@test "Git: SSH形式originがgh:owner/repoに正規化されること" {
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  local tmp_repo
  tmp_repo=$(mktemp -d)
  ( cd "$tmp_repo" && git init -q \
    && git -c user.name=t -c user.email=t@t commit --allow-empty -q -m init \
    && git remote add origin "git@github.com:acme/widgets.git" )
  rm -f "$cache_dir"/* 2>/dev/null
  echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh >/dev/null 2>&1
  _wait_for_cache "$cache_dir"
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  rm -rf "$tmp_repo"
  [[ "$result" == *"gh:${RST}acme/widgets"* ]]
  # .git サフィックスが取れていること
  [[ "$result" != *"acme/widgets.git"* ]]
}

@test "Git: workspace.repo(Claude Code 2.1.145+)がコールドスタートでもgh:を表示すること" {
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  rm -f "$cache_dir"/* 2>/dev/null
  # cache を消して即座に sed -n '3p' する = cold start。git remote get-url を介さず stdin から gh: が出る
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" == *"gh:${RST}acme/widgets"* ]]
}

@test "Git: detached HEADのcold startではgh:を表示しないこと(build_git detachedパスとgate統一)" {
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  local tmp_repo
  tmp_repo=$(mktemp -d)
  ( cd "$tmp_repo" && git init -q \
    && git -c user.name=t -c user.email=t@t commit --allow-empty -q -m init \
    && git checkout -q --detach )
  rm -f "$cache_dir"/* 2>/dev/null
  # cold start: build_git の detached パスは gh: を出さないので、cold start が出すと cache populate 時にフリッカーする
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$tmp_repo"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  rm -rf "$tmp_repo"
  [[ "$result" != *"gh:"* ]]
  [[ "$result" == *"HEAD@"* ]]
}

@test "PR: pr.review_state=approvedで緑色のテキストが表示されること" {
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"pr":{"number":1234,"review_state":"approved"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" == *$'\033[32m'"approved"* ]]
}

@test "PR: pr.review_state=changes_requestedで赤色のテキストが表示されること" {
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"pr":{"number":1234,"review_state":"changes_requested"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" == *$'\033[31m'"changes_requested"* ]]
}

@test "PR: pr.review_state=pendingで黄色のテキストが表示されること" {
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"pr":{"number":1234,"review_state":"pending"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" == *$'\033[33m'"pending"* ]]
}

@test "PR: pr.review_state=draftでグレー(38;5;245)のテキストが表示されること" {
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"pr":{"number":1234,"review_state":"draft"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" == *$'\033[38;5;245m'"draft"* ]]
}

@test "PR: pr.review_stateが空の場合は何も表示しないこと" {
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" != *"approved"* ]]
  [[ "$result" != *"pending"* ]]
}

@test "PR: PR番号(#)は表示しないこと — Claude Code 組み込みフッターと住み分け" {
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"github.com","owner":"acme","name":"widgets"}},"pr":{"number":1234,"url":"https://github.com/acme/widgets/pull/1234","review_state":"approved"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" != *"#1234"* ]]
}

@test "Git: workspace.repoの非GitHubホスト(gitlab.com等)ではgh:が表示されないこと" {
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.146","workspace":{"current_dir":"'"$(pwd)"'","repo":{"host":"gitlab.com","owner":"acme","name":"widgets"}},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" != *"gh:"* ]]
}

# ============================================================================
# vim mode badge — NORMAL は非表示、INSERT/VISUAL/VISUAL LINE は bg 色付きで Line 1 最左に
# ============================================================================
@test "vim: INSERTモードで緑バッジが表示されること" {
  result=$(echo '{"model":{"id":"t","display_name":"T"},"version":"2.1.146","workspace":{"current_dir":"/tmp"},"vim":{"mode":"INSERT"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  # bg lime-green (48;5;148, gruvbox-ish) + bold + INSERT テキストが含まれること
  [[ "$result" == *$'\033[1;30;48;5;148m INSERT '* ]]
}

@test "vim: VISUALモードで橙バッジが表示されること" {
  result=$(echo '{"model":{"id":"t","display_name":"T"},"version":"2.1.146","workspace":{"current_dir":"/tmp"},"vim":{"mode":"VISUAL"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[1;30;48;5;214m VISUAL '* ]]
}

@test "vim: VISUAL LINEはV-LINEに短縮して同じ橙バッジで表示されること" {
  result=$(echo '{"model":{"id":"t","display_name":"T"},"version":"2.1.146","workspace":{"current_dir":"/tmp"},"vim":{"mode":"VISUAL LINE"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[1;30;48;5;214m V-LINE '* ]]
  [[ "$result" != *"VISUAL LINE"* ]]
}

@test "vim: NORMALモードはバッジを表示しないこと (デフォルト状態でノイズ削減)" {
  result=$(echo '{"model":{"id":"t","display_name":"T"},"version":"2.1.146","workspace":{"current_dir":"/tmp"},"vim":{"mode":"NORMAL"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" != *"NORMAL"* ]]
  [[ "$result" != *"48;5;148"* ]]
  [[ "$result" != *"48;5;214"* ]]
}

@test "vim: vim.mode未設定の場合はバッジを表示しないこと (vim mode無効セッション)" {
  result=$(echo '{"model":{"id":"t","display_name":"T"},"version":"2.1.146","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" != *"INSERT"* ]]
  [[ "$result" != *"48;5;148"* ]]
  [[ "$result" != *"48;5;214"* ]]
}

@test "Git: 非GitHub origin(GitLab等)ではgh:が表示されないこと" {
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  local tmp_repo
  tmp_repo=$(mktemp -d)
  ( cd "$tmp_repo" && git init -q \
    && git -c user.name=t -c user.email=t@t commit --allow-empty -q -m init \
    && git remote add origin "git@gitlab.com:acme/widgets.git" )
  rm -f "$cache_dir"/* 2>/dev/null
  echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh >/dev/null 2>&1
  _wait_for_cache "$cache_dir"
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$tmp_repo"'"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  rm -rf "$tmp_repo"
  [[ "$result" != *"gh:"* ]]
}

# ============================================================================
# 統合テスト: セッション表示 — 状態に応じた表示がされること
# ============================================================================
@test "セッション: 名前未設定で(no name)が表示されないこと" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" != *"(no name)"* ]]
}

@test "セッション: ブランチ時にbranchと表示すること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"session_name":"(Branch) my session","version":"2.1.77","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  # 黄色のbranch表記があること (セッション名のresidueではなくインジケータ)
  [[ "$result" == *$'\033[33mbranch'* ]]
}

@test "セッション: 旧フォーク形式でもbranchと表示すること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"session_name":"(Fork) my session","version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *$'\033[33mbranch'* ]]
}

# ============================================================================
# Worktree — stdin JSONからworktree情報を表示
# ============================================================================
@test "Worktree: worktreeセッションで🌲とfrom:元ブランチが表示されること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.84","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10},"worktree":{"name":"my-feature","branch":"worktree-my-feature","original_branch":"main"}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" == *"🌲"* ]]
  [[ "$result" == *"from:main"* ]]
}

@test "Worktree: workspace.git_worktreeがtrueのとき🌲が表示されること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.97","workspace":{"current_dir":"/tmp","git_worktree":true},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" == *"🌲"* ]]
}

@test "Worktree: worktree未使用時は🌲が表示されないこと" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.84","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" != *"🌲"* ]]
}

@test "Worktree: original_branchがないhookベースworktreeでも🌲だけ表示されること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.84","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10},"worktree":{"name":"hook-wt","path":"/tmp/wt"}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" == *"🌲"* ]]
  [[ "$result" != *"from:"* ]]
}

@test "Worktree: worktree.pathがある場合はcurrent_dirの代わりにworktreeパスが表示されること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.84","workspace":{"current_dir":"/home/user/original-repo","project_dir":""},"context_window":{"used_percentage":10},"worktree":{"name":"my-feature","path":"/home/user/worktree-dir","original_branch":"main"}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '2p')
  # worktree path should appear, not original repo path
  [[ "$result" == *"worktree-dir"* ]]
  [[ "$result" != *"original-repo"* ]]
}

@test "Worktree: .claude/worktrees配下のパスがリポroot+🌲worktree名に分割表示されること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.84","workspace":{"current_dir":"/home/user/myrepo","project_dir":""},"context_window":{"used_percentage":10},"worktree":{"name":"melody","path":"/home/user/myrepo/.claude/worktrees/melody","original_branch":"main"}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '2p')
  # 🌲 より左（パス本文とそのリンク URL）はリポ root まで — marker が現れない
  pre="${result%%🌲*}"
  [[ "$pre" == *"/home/user/myrepo"* ]]
  [[ "$pre" != *".claude/worktrees"* ]]
  # worktree 名は 🌲 直後に dim で表示
  [[ "$result" == *"🌲${DIM}"*"melody"* ]]
  [[ "$result" == *"from:main"* ]]
}

@test "Worktree: original_branchがHEADのときfrom:が表示されないこと" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.84","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10},"worktree":{"name":"wt","original_branch":"HEAD"}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" == *"🌲"* ]]
  [[ "$result" != *"from:"* ]]
}

@test "Worktree: worktree配下のサブディレクトリでは分割せずフルパス表示されること" {
  # /cd で worktree 内サブディレクトリへ移動した git linked worktree — leaf に / が含まれるため分割しない
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.97","workspace":{"current_dir":"/home/user/myrepo/.claude/worktrees/melody/src","git_worktree":true},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '2p')
  # 🌲 が無いと ${result%%🌲*} は全文になり vacuous pass するので、先に 🌲 の存在を assert する
  [[ "$result" == *"🌲"* ]]
  pre="${result%%🌲*}"
  [[ "$pre" == *".claude/worktrees/melody/src"* ]]
}

# ============================================================================
# エラー耐性 — 不正入力でもクラッシュしないこと
# ============================================================================
@test "エラー耐性: 壊れたJSONでjq errorを表示してexit 0すること" {
  result=$(echo 'NOT_JSON' | bash statusline-command.sh 2>/dev/null)
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
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"38;5;173"*"Opus 4.7"* ]]
}

@test "モデル色: Opus 4.7 (1M context) でもコーラルで表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-7[1m]","display_name":"Opus 4.7 (1M context)"},"version":"2.1.112","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"38;5;173"*"Opus 4.7 (1M context)"* ]]
}

# ============================================================================
# 統合テスト: 全体 — 正常に動作すること
# ============================================================================
@test "全体: exit code 0で終了すること" {
  echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null
}

@test "全体: コンテキストバーにパーセンテージが表示されること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" == *"48%"* ]]
}

# ============================================================================
# 端末幅非依存 — 幅に関係なく4行かつexit 0で完走すること
# ============================================================================
@test "全体: COLUMNS=40でもバージョンは常時表示されること" {
  result=$(COLUMNS=40 bash -c 'echo "{\"model\":{\"id\":\"claude-opus-4-6\",\"display_name\":\"Opus 4.6\"},\"version\":\"2.1.80\",\"workspace\":{\"current_dir\":\"/tmp\"},\"context_window\":{\"used_percentage\":48}}" | bash statusline-command.sh 2>/dev/null | head -1')
  [[ "$result" == *"v2.1.80"* ]]
}

@test "全体: COLUMNS=40でも4行出力されること" {
  result=$(COLUMNS=40 bash -c 'echo "{\"model\":{\"id\":\"test\",\"display_name\":\"Test\"},\"version\":\"2.1.76\",\"workspace\":{\"current_dir\":\"/tmp\"},\"context_window\":{\"used_percentage\":10}}" | bash statusline-command.sh 2>/dev/null')
  status=$?
  [[ "$status" -eq 0 ]]
  line_count=$(echo "$result" | grep -c . || echo 0)
  [[ "$line_count" -eq 4 ]]
}

@test "全体: COLUMNS=30でもモデル名がフルで表示されること" {
  result=$(COLUMNS=30 bash -c 'echo "{\"model\":{\"id\":\"claude-opus-4-6\",\"display_name\":\"Opus 4.6\"},\"version\":\"2.1.80\",\"workspace\":{\"current_dir\":\"/tmp\"},\"context_window\":{\"used_percentage\":48}}" | bash statusline-command.sh 2>/dev/null | head -1')
  [[ "$result" == *"Opus 4.6"* ]]
}

# ============================================================================
# added_dirs — /add-dirで追加されたディレクトリの表示
# ============================================================================
@test "added_dirs: 追加ディレクトリ数を(+N dirs)で集約表示すること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.78","workspace":{"current_dir":"/tmp","added_dirs":["/tmp/foo","/Users/me/bar"]},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" == *"(+2 dirs)"* ]]
}

@test "added_dirs: 追加ディレクトリがないとき(+N dirs)は表示されないこと" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.78","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" != *"dirs"* ]]
}

@test "added_dirs: 空配列のとき(+N dirs)は表示されないこと" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.78","workspace":{"current_dir":"/tmp","added_dirs":[]},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" != *"dirs"* ]]
}

# ============================================================================
# パス表示 — current_dir を表示し project_dir には依存しないこと
# ============================================================================
@test "パス表示: current_dirとproject_dirが異なるときcurrent_dirを表示すること" {
  # /cd 後など current_dir != project_dir のとき、launch 時の project_dir ではなく
  # 現在地 current_dir を表示する (v1.32.0 で project_dir 優先をやめた)
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"/tmp/moved-here","project_dir":"/tmp/launched-here"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" == *"/tmp/moved-here"* ]]
  [[ "$result" != *"launched-here"* ]]
}

# ============================================================================
# Line 4順番 — 5h limit, context, weekly の順であること
# ============================================================================
@test "Line4順番: 5hリミットがcontextより左に表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.80","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":4070908800}}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  # 35% (5h) should appear before 48% (context)
  five_pos="${result%%35%*}"
  ctx_pos="${result%%48%*}"
  [[ ${#five_pos} -lt ${#ctx_pos} ]]
}

@test "Line4順番: weeklyがcontextより右に表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.80","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":4070908800},"seven_day":{"used_percentage":12,"resets_at":4071427200}}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  ctx_pos="${result%%48%*}"
  week_pos="${result%%week:*}"
  [[ ${#ctx_pos} -lt ${#week_pos} ]]
}

# ============================================================================
# OSC 8リンク — file://でクリック可能であること
# ============================================================================
@test "OSC8: パスがfile://リンクとして生成されること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" == *"file:///tmp"* ]]
}

@test "端末幅: 長いパスがCOLUMNS=50でも省略されないこと" {
  result=$(COLUMNS=50 bash -c 'echo "{\"model\":{\"id\":\"test\",\"display_name\":\"Test\"},\"version\":\"2.1.76\",\"workspace\":{\"current_dir\":\"/Users/user/very/long/path/to/some/deep/project\"},\"context_window\":{\"used_percentage\":10}}" | bash statusline-command.sh 2>/dev/null | sed -n "2p"')
  [[ "$result" != *"…"* ]]
}
