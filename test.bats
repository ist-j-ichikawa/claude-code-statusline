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
  result=$(progress_bar 0)
  [[ "$result" == "○○○○○○○○○○" ]]
}

@test "progress_bar: 100%で全て埋まったバーを返すこと" {
  result=$(progress_bar 100)
  [[ "$result" == "●●●●●●●●●●" ]]
}

@test "progress_bar: 50%で半分埋まったバーを返すこと" {
  result=$(progress_bar 50)
  [[ "$result" == "●●●●●○○○○○" ]]
}

@test "progress_bar: 100%超でも10個で打ち止めになること" {
  result=$(progress_bar 120)
  [[ "$result" == "●●●●●●●●●●" ]]
}

@test "progress_bar: 15%で1個だけ埋まること" {
  result=$(progress_bar 15)
  [[ "$result" == "●○○○○○○○○○" ]]
}

# ============================================================================
# color_by_threshold — 閾値に応じた色を返すこと
# ============================================================================
@test "color_by_threshold: 上限以上で赤を返すこと" {
  result=$(color_by_threshold 95 90 80)
  [[ "$result" == "$RED" ]]
}

@test "color_by_threshold: 中間で黄を返すこと" {
  result=$(color_by_threshold 85 90 80)
  [[ "$result" == "$YLW" ]]
}

@test "color_by_threshold: 下限以下で緑を返すこと" {
  result=$(color_by_threshold 50 90 80)
  [[ "$result" == "$GRN" ]]
}

@test "color_by_threshold: 上限ちょうどで赤を返すこと" {
  result=$(color_by_threshold 90 90 80)
  [[ "$result" == "$RED" ]]
}

@test "color_by_threshold: 中間ちょうどで黄を返すこと" {
  result=$(color_by_threshold 80 90 80)
  [[ "$result" == "$YLW" ]]
}

# ============================================================================
# format_tokens — トークン数を人間が読みやすい形式に変換すること
# ============================================================================
@test "format_tokens: 100万以上でM表記になること" {
  result=$(format_tokens 1500000)
  [[ "$result" == "1M" ]]
}

@test "format_tokens: 1000以上でK表記になること" {
  result=$(format_tokens 45000)
  [[ "$result" == "45K" ]]
}

@test "format_tokens: 1000未満でそのまま表示されること" {
  result=$(format_tokens 999)
  [[ "$result" == "999" ]]
}

@test "format_tokens: ちょうど1000でK表記になること" {
  result=$(format_tokens 1000)
  [[ "$result" == "1K" ]]
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

# ============================================================================
# 統合テスト: セッション表示 — 状態に応じた表示がされること
# ============================================================================
@test "セッション: 名前未設定で(no name)と表示すること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"(no name)"* ]]
}

@test "セッション: フォーク時に(fork)と表示すること" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"session_name":"(Fork) my session","version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"(fork)"* ]]
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
