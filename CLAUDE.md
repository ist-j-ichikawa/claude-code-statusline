# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Single-file Bash script (`statusline-command.sh`) that renders a custom statusline for Claude Code CLI. Claude Code pipes session JSON to stdin; the script outputs multiple `printf` lines that become the statusline rows.

## Testing

`bats test.bats` で自動テストを実行。テスト名は t-wada スタイル（日本語「〜すること」）。
```bash
bats test.bats
```
手動確認:
```bash
echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"version":"2.1.76","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":48}}' | bash statusline-command.sh
```
Verify: exit code must be 0, all lines render with correct colors, no raw `\033` in output.

## Architecture

- **ドキュメントの置き場**: スクリプト内のヘッダーコメントは最小限（1行）。詳細はREADMEと公式ドキュメントへのリンクで管理。
- **Single jq call**: Extracts all JSON fields at once via `eval` + `@sh` — do NOT split into multiple jq invocations.
- **Background refresh**: `build_git()` runs in background subshell (`& disown`). Stale cache is served immediately; refresh happens asynchronously. Never blocks statusline output.
- **Shared `cache_stale()`**: Generic cache-staleness checker (file + max_age) used by git (5s) and subscription (3600s). Uses `_NOW` timestamp to avoid multiple `date` forks.
- **Cache location**: All caches under `/tmp/ist-j-ichikawa-claude-statusline/{git,subscription}`.
- **Lines 1-3**: Each line is built as a bash array, then `printf '%s\n'` outputs each. Always exactly 3 lines. Script must end with `exit 0` — a trailing `[[ ]] && ...` that evaluates false would exit 1 and blank the statusline.
- **Session name**: Not displayed — Claude Code 2.1.76+ shows session name natively in the top-right corner. `(branch)` (黄) がバージョン後に表示される（名前未設定時は何も表示しない）。2.1.77で`/fork`→`/branch`にリネーム。`(Branch)`と旧`(Fork)`両方を検出。
- **Subscription type**: `fetch_subscription()` reads `.claudeAiOauth.subscriptionType` from Keychain/credentials via shared `get_credentials_blob()`. 3600s background-cached. Shown as `Anthropic(enterprise)` etc. on Line 1 (Anthropic provider only).
- **Cloud provider indicator**: Bedrock (model.id prefix or `CLAUDE_CODE_USE_BEDROCK` or `CLAUDE_CODE_USE_MANTLE`), Vertex (`CLAUDE_CODE_USE_VERTEX`), Foundry (`CLAUDE_CODE_USE_FOUNDRY`), otherwise Anthropic. Each has a branded color.
- **Model display**: Prefers `display_name`, falls back to `model_id` when empty (e.g. Bedrock). Colors match Anthropic's official brand: Opus=coral(`CORAL`), Sonnet 4.6=teal(`TEAL`), Sonnet 4.5/3.5=amber(`AMBER`), Haiku=lavender(`LAVENDER`).
- **Terminal width adaptation**: `COLUMNS` env var → `tput cols` → default 80. Narrow terminals progressively drop low-priority elements: version (<65), session indicator (<55), subscription type (<45), agent name (<45), model version suffix (<35), git info (<45), worktree indicator (<45), weekly rate limit (<70). Paths are displayed in full (no truncation); git info is truncated from the right based on remaining width. `_truncate_bytes` provides a byte-level safety net on all output lines with ANSI escape cleanup.
- **Git info (Line 2)**: `build_git()` shows branch name in Git brand orange (`GIT`, `38;5;202`, Pantone 1788C), dirty state (A=staged/M=modified/?=untracked/U=conflicts — git standard symbols), ahead/behind, last commit age+message (20char truncated), detached HEAD (red). Non-git dirs show `(no git)`. Cold start (no cache yet) reads `.git/HEAD` directly (pure bash, no fork) to show branch name immediately; worktree `.git` files with relative gitdir paths are resolved.
- **Worktree indicator (Line 2)**: Shows 🌲 when `worktree.name` (CC worktree session) or `workspace.git_worktree` (git linked worktree, CC 2.1.97+) is set. `from:original_branch` (dim) is appended when `worktree.original_branch` is available (absent for hook-based worktrees). `worktree.path` overrides `current_dir` so that path display and `build_git()` reference the worktree directory, not the original repo.
- **Added dirs (Line 2)**: `workspace.added_dirs` (CC 2.1.78+) の配列長を `(+N dirs)` で表示。`/add-dir` でディレクトリを追加した場合のみ出現。
- **OSC 8 links (Line 2)**: `editor_url` で `file://` URL を生成し、パスをクリック可能にする。カスタムURLスキーム（`zed://` 等）はターミナルが対応しないため `file://` 固定。
- **Upstream tracking**: `~/ghq/github.com/anthropics/claude-code/CHANGELOG.md` で Claude Code の変更を確認。公開リポにソースコードはなく、CHANGELOG + plugins + scripts のみ。
- **Line 3 (rate limit + context)**: 左から順に: 5h rate limit (`braille_bar` + %) → context window (`braille_bar` 5-char, `⣀⣄⣤⣦⣶⣷⣿`, 40 steps + %) → weekly rate limit。5h rate limitを最左に配置（最も頻繁に確認する情報）。Anthropic rate limit は stdin JSON `rate_limits` field (CC 2.1.80+)。`resets_at` is Unix epoch seconds (not ISO 8601). 5-hour in Anthropic sand (`ANTH`, `38;5;180`) with remaining time (`format_reset_remaining`), weekly in dim with absolute day/time reset (`format_reset_absolute`). Pre-2.1.80 CC では rate limit 部分が空（graceful degradation）。トークン数とコストは非表示（CCの `total_input_tokens` がキャッシュトークンを含まず誤解を招くため）。

## Key Constraints

- Color values must match official branding — model colors follow Anthropic's UI (claude.ai), provider colors follow each cloud's branding. Confirm with user before changing.
- Script must be **fast** — Claude Code blanks the statusline if it's slow. Avoid external commands in hot paths; use bash builtins. All I/O-heavy operations (git, curl) must run in background subshells.
- **Fork最小化**: `$(func)` サブシェル呼び出しはフォーク(プロセス生成)が発生する。ヘルパー関数は `printf -v "$varname"` パターンで変数に直接セットし、呼び出し側の `$(...)` フォークを回避する。同様に `cat file` → `$(<file)`、`echo x | md5 -q` → `md5 -q -s x`、`sed` → bash文字列操作、`$(cat)` → `IFS= read -r -d ''`、`tr '[:upper:]' '[:lower:]'` → `shopt -s nocasematch` で外部コマンドforkを削減。
- **bash 3.2互換**: shebangは `#!/bin/bash`（macOS標準）。`${var,,}` や `printf '%(%s)T'` 等のbash 4+機能は使用禁止 — Claude Codeの実行環境ではPATHにhomebrew bashがない場合があり、スクリプト全体が即死する。大文字小文字の比較には `shopt -s nocasematch`（bash 3.2互換）を使い、使用後は `shopt -u nocasematch` で必ずリセット。
- macOS-only: Uses `stat -f %m` and `md5 -q -s` (not GNU equivalents).
- The script is referenced directly from `~/.claude/settings.json` — no copy in `~/.claude/`. Single source of truth is this repo.
- ANSI colors and OSC 8 hyperlinks are supported by the terminal.
- Available stdin JSON fields: https://code.claude.com/docs/en/statusline#available-data

## Security

- OAuth tokens (used by `fetch_subscription()`) must NOT appear in command-line arguments (`ps aux` leak). Use `curl --config -` to pass Authorization headers via stdin.
- Cache directories under `/tmp` must use `mkdir -p -m 700` (owner-only).
- Variables set by `eval` under `set -u` must be initialized beforehand — if `eval` fails via `|| true`, unset variables cause fatal errors.

## Gotchas

- **`replace_all` with color codes**: Never use `replace_all` when the target string appears in its own definition (e.g. replacing `\033[38;5;208m` with `${ORG}` will also corrupt `ORG=$'\033[38;5;208m'`). Define the constant first, then manually update references.
- **Backward compatibility**: All jq fields use `// ""` or `// 0` defaults so older Claude Code versions (with fewer JSON fields) degrade gracefully — items simply don't display. Never add a field without a jq default.
- **`printf '%s'` not `'%b'`**: All output uses `printf '%s\n'` — never `%b` which interprets backslash escapes in external strings (session_name etc.). All ANSI colors must be `$'\033[...]'` constants (pre-expanded), not inline `"\033[...]"` strings.
- **Bedrock detection uses `model_id`**: Provider prefix regex (`^(global|jp|...)\.`) must check `model_id`, not `model_show` (which may be `display_name` like "Opus 4.6").
- **jq抽出とコードの同期**: 表示コードを削除/無効化したら、jqの`@sh`抽出行も必ず削除する。未使用のjq抽出はパフォーマンス劣化の原因になる。
- **行数カウントは `grep -c .`**: `wc -l | tr -d ' '` ではなく `grep -c . || echo 0` を使う。forkが少なく、macOS/Linux両方で安定。
