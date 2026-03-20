#!/usr/bin/env bats
# statusline-command.sh テスト
# 実行: bats test.bats

# --- セットアップ: ヘルパー関数のみを読み込む ---
setup() {
  export RST=$'\033[0m' GRN=$'\033[32m' YLW=$'\033[33m' RED=$'\033[31m'
  export DIM=$'\033[2m'
  export ANTH=$'\033[38;5;180m' BDCK=$'\033[38;5;72m' VTEX=$'\033[38;5;33m' FNDY=$'\033[38;5;39m'
  export CORAL=$'\033[38;5;209m' TEAL=$'\033[38;5;79m' AMBER=$'\033[38;5;214m' LAVENDER=$'\033[38;5;183m'
  export AGENT=$'\033[38;5;213m' DIMVER=$'\033[38;5;248m'
  export _NOW=$(date +%s)
  eval "$(sed -n '/^# --- Helpers ---$/,/^# --- Credentials/{ /^# --- Credentials/d; p; }' statusline-command.sh)"
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
# progress_bar — パーセンテージをバーに変換すること
# ============================================================================
@test "progress_bar: 0%で全て空のバーを返すこと" {
  progress_bar 0 result
  [[ "$result" == "○○○○○○○○○○" ]]
}

@test "progress_bar: 100%で全て埋まったバーを返すこと" {
  progress_bar 100 result
  [[ "$result" == "●●●●●●●●●●" ]]
}

@test "progress_bar: 50%で半分埋まったバーを返すこと" {
  progress_bar 50 result
  [[ "$result" == "●●●●●○○○○○" ]]
}

@test "progress_bar: 100%超でも10個で打ち止めになること" {
  progress_bar 120 result
  [[ "$result" == "●●●●●●●●●●" ]]
}

@test "progress_bar: 15%で1個だけ埋まること" {
  progress_bar 15 result
  [[ "$result" == "●○○○○○○○○○" ]]
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

@test "color_by_threshold: 下限以下で緑を返すこと" {
  color_by_threshold 50 90 80 result
  [[ "$result" == "$GRN" ]]
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
  [[ "$result" == *"38;5;209"*"Opus 4.6"* ]]
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

@test "モデル色: Haikuがラベンダーで表示されること" {
  result=$(echo '{"model":{"id":"claude-haiku-4-5","display_name":"Haiku 4.5"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"38;5;183"*"Haiku 4.5"* ]]
}

@test "モデル色: 大文字混在のdisplay_nameでも正しい色になること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"OPUS 4.6"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"38;5;209"*"OPUS 4.6"* ]]
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

@test "プロバイダー: CLAUDE_CODE_USE_VERTEX環境変数でVertexと検出すること" {
  result=$(CLAUDE_CODE_USE_VERTEX=1 bash -c 'echo "{\"model\":{\"id\":\"claude-opus\",\"display_name\":\"Opus 4.6\"},\"version\":\"2.1.76\",\"workspace\":{\"current_dir\":\"/tmp\"},\"context_window\":{\"used_percentage\":48}}" | bash statusline-command.sh 2>/dev/null | head -1')
  [[ "$result" == *"Vertex"* ]]
}

# ============================================================================
# 統合テスト: Line 4 — プロバイダー別の表示が正しいこと
# ============================================================================
@test "Line4: Bedrockでコスト・入力・出力トークンが表示されること" {
  result=$(echo '{"model":{"id":"global.anthropic.claude-opus-4-6-v1","display_name":"Opus 4.6"},"version":"2.1.77","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48,"total_input_tokens":125000,"total_output_tokens":8500},"cost":{"total_cost_usd":0.42}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" == *'$0.42'* ]]
  [[ "$result" == *"↑125.0k"* ]]
  [[ "$result" == *"↓8.5k"* ]]
}

@test "Line4: Bedrockでコスト0・トークンなしのとき\$0.00のみ表示すること" {
  result=$(echo '{"model":{"id":"global.anthropic.claude-opus-4-6-v1","display_name":"Opus 4.6"},"version":"2.1.77","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":0},"cost":{"total_cost_usd":0}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" == *'$0.00'* ]]
  [[ "$result" != *"↑"* ]]
  [[ "$result" != *"↓"* ]]
}

@test "Line4: Anthropicではコストが表示されないこと" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.77","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"cost":{"total_cost_usd":0.15}}' \
    | bash statusline-command.sh 2>/dev/null)
  # Anthropic should not show cost on any line
  [[ "$result" != *'$0.15'* ]]
}

@test "Line4: Anthropicでrate_limitsからレートリミットを表示すること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.80","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":"2099-01-01T00:00:00Z"},"seven_day":{"used_percentage":12,"resets_at":"2099-01-07T00:00:00Z"}}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" == *"35%"* ]]
  [[ "$result" == *"week:12%"* ]]
}

@test "Line4: rate_limitsがない旧CCでLine4が空になること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.79","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null)
  line_count=$(echo "$result" | grep -c . || echo 0)
  [[ "$line_count" -eq 3 ]]
}

@test "Line4: rate_limitsのused_percentageがfloatでもroundされること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.80","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":35.7,"resets_at":"2099-01-01T00:00:00Z"}}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" == *"36%"* ]]
}

# ============================================================================
# 統合テスト: Line 2 — ディレクトリとGit情報が表示されること
# ============================================================================
@test "Git: git管理外ディレクトリで(no git)と表示すること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" == *"(no git)"* ]]
}

@test "Git: gitリポジトリのコールドスタートで(no git)を表示しないこと" {
  # Clear cache to simulate cold start
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$(pwd)"'"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" != *"(no git)"* ]]
}

@test "Git: コールドスタートでブランチ名を即時表示すること" {
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  rm -f "$cache_dir"/* 2>/dev/null
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$(pwd)"'"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" == *"(main)"* || "$result" == *"(master)"* || "$result" == *"(HEAD@"* ]]
}

# ============================================================================
# 統合テスト: セッション表示 — 状態に応じた表示がされること
# ============================================================================
@test "セッション: 名前未設定で(no name)と表示すること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"(no name)"* ]]
}

@test "セッション: ブランチ時に(branch)と表示すること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"session_name":"(Branch) my session","version":"2.1.77","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"(branch)"* ]]
}

@test "セッション: 旧フォーク形式でも(branch)と表示すること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"session_name":"(Fork) my session","version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"(branch)"* ]]
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
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" == *"48%"* ]]
}
