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
  export CORAL=$'\033[38;5;209m' TEAL=$'\033[38;5;79m' AMBER=$'\033[38;5;214m' LAVENDER=$'\033[38;5;183m'
  export AGENT=$'\033[38;5;213m' DIMVER=$'\033[38;5;248m'
  export _NOW=$(date +%s)
  eval "$(sed -n '/^# --- Helpers ---$/,/^# --- Credentials/{ /^# --- Credentials/d; p; }' statusline-command.sh)"
}

# build_git の background cache 書き込み完了まで polling (最大 ~1秒)
# 4 テストで `sleep 1` 固定にすると合計 +4秒のオーバーヘッドになるため
_wait_for_cache() {
  local cache_dir=$1 i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    [[ -n "$(ls -A "$cache_dir" 2>/dev/null)" ]] && return 0
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

@test "Effort/Thinking: 旧CC(両キーなし)でeffort/thinkが表示されないこと" {
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
@test "Line4: コストとトークンが表示されないこと" {
  result=$(echo '{"model":{"id":"global.anthropic.claude-opus-4-6-v1","display_name":"Opus 4.6"},"version":"2.1.77","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48,"total_input_tokens":125000,"total_output_tokens":8500},"cost":{"total_cost_usd":0.42}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" != *'$'* ]]
  [[ "$result" != *"↑"* ]]
  [[ "$result" != *"↓"* ]]
}

@test "Line4: Anthropicでレートリミットが表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.80","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":4070908800},"seven_day":{"used_percentage":12,"resets_at":4071427200}}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '4p')
  [[ "$result" == *"35%"* ]]
  [[ "$result" == *"week:12%"* ]]
}

@test "Line4: Anthropicでrate_limitsからレートリミットを表示すること" {
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

@test "Git: GitHub originでgh:owner/repoがdimでブランチ前に表示されること" {
  local cache_dir="/tmp/ist-j-ichikawa-claude-statusline/git"
  rm -f "$cache_dir"/* 2>/dev/null
  # cold start: build_git の background が cache を書く
  echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$(pwd)"'"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh >/dev/null 2>&1
  _wait_for_cache "$cache_dir"
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"'"$(pwd)"'"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '3p')
  [[ "$result" == *"gh:ist-j-ichikawa/claude-code-statusline"* ]]
  [[ "$result" == *"${DIM}gh:"* ]]
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
  [[ "$result" == *"gh:acme/widgets"* ]]
  # .git サフィックスが取れていること
  [[ "$result" != *"gh:acme/widgets.git"* ]]
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
  [[ "$result" == *"38;5;209"*"Opus 4.7"* ]]
}

@test "モデル色: Opus 4.7 (1M context) でもコーラルで表示されること" {
  result=$(echo '{"model":{"id":"claude-opus-4-7[1m]","display_name":"Opus 4.7 (1M context)"},"version":"2.1.112","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' \
    | bash statusline-command.sh 2>/dev/null | head -1)
  [[ "$result" == *"38;5;209"*"Opus 4.7 (1M context)"* ]]
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
# サブディレクトリ削除 — →current_dirが表示されないこと
# ============================================================================
@test "サブディレクトリ: project_dirとcurrent_dirが異なっても→が表示されないこと" {
  result=$(echo '{"model":{"id":"test","display_name":"Test"},"version":"2.1.76","workspace":{"current_dir":"/tmp/sub","project_dir":"/tmp"},"context_window":{"used_percentage":10}}' \
    | bash statusline-command.sh 2>/dev/null | sed -n '2p')
  [[ "$result" != *"→"* ]]
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
