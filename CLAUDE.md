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

## Commits

Conventional Commits 厳守。実履歴で使用しているのは `feat:` / `fix:` / `refactor:` / `docs:` / `test:` のみ。`chore:` / `style:` / `perf:` 等は未使用。1 コミット = 1 マイナー版 ＋ CHANGELOG 1 エントリが原則（詳細は Gotchas の「CHANGELOG のバージョン分割ルール」参照）。

## Architecture

- **ドキュメントの置き場**: スクリプト内のヘッダーコメントは最小限（1行）。詳細はREADMEと公式ドキュメントへのリンクで管理。
- **Single jq call**: Extracts all JSON fields at once via `eval` + `@sh` — do NOT split into multiple jq invocations.
- **Background refresh**: `build_git()` runs in background subshell (`& disown`). Stale cache is served immediately; refresh happens asynchronously. Never blocks statusline output.
- **Shared `cache_stale()`**: Generic cache-staleness checker (file + max_age) used by git (5s) and subscription (3600s). Uses `_NOW` timestamp to avoid multiple `date` forks.
- **Cache location**: All caches under `/tmp/ist-j-ichikawa-claude-statusline/{git,subscription}`.
- **Lines 1-4**: Each line is built as a bash array, then `printf '%s\n'` outputs each. Normally exactly 4 lines (path と git を別行にして Line 2 のオーバーフローを回避)。`line_git` が空のエッジケースでは 3 行出力。Script must end with `exit 0` — a trailing `[[ ]] && ...` that evaluates false would exit 1 and blank the statusline.
- **Session name**: Not displayed — Claude Code 2.1.76+ shows session name natively in the top-right corner. `branch` (黄) がバージョン後に表示される（`/branch` セッションのみ。名前未設定時は何も表示しない）。2.1.77で`/fork`→`/branch`にリネーム。`(Branch)`と旧`(Fork)`両方を検出。
- **Subscription type**: `fetch_subscription()` reads `.claudeAiOauth.subscriptionType` from Keychain/credentials via shared `get_credentials_blob()`. 3600s background-cached. Shown as `Anthropic(enterprise)` etc. on Line 1 (Anthropic provider only).
- **Cloud provider indicator**: Bedrock (model.id prefix or `CLAUDE_CODE_USE_BEDROCK` or `CLAUDE_CODE_USE_MANTLE`), Vertex (`CLAUDE_CODE_USE_VERTEX`), Foundry (`CLAUDE_CODE_USE_FOUNDRY`), otherwise Anthropic. Each has a branded color.
- **Model display**: Prefers `display_name`, falls back to `model_id` when empty (e.g. Bedrock). Colors match Anthropic's official brand: Opus=coral(`CORAL`), Sonnet 4.6=teal(`TEAL`), Sonnet 4.5/3.5=amber(`AMBER`), Haiku=lavender(`LAVENDER`).
- **Effort & thinking (Line 1)**: `.effort.level` (CC 2.1.119+) をレベル名そのまま (`high` / `max` 等)、`.thinking.enabled=true` を `think` で表示し、両方ある時は半角スペース区切り (`high think`)。色は**モデル色との衝突回避**のため独立カラー: `EFFORT` (`38;5;105` light purple)、`THINK` (`38;5;117` light cyan)。CCがネイティブのeffort表示を廃止したため統合。プレフィックスと記号区切りは付けない — 色分けで識別する方針。`effort` キーが欠落した古いCCでも graceful degradation。
- **No width adaptation**: 端末幅に応じた表示切替はしない方針。すべての要素を常時フル表示する。ターミナルが折り返す場合はそれで良しとする（シンプルさ優先）。
- **Line 2 (path + worktree)**: path (OSC 8 クリック可能リンク) → worktree 🌲 (`from:original_branch` 付き) → `added_dirs` インジケータの順。🌲 は「このパスが worktree である」事実を示すので path 直後、`(+N dirs)` は独立した補助情報なので末尾。git info は Line 2 から独立して Line 3 に分離済み（Line 2 が長くなりすぎる問題への対処）。
- **Line 3 (git info)**: `build_git()` shows `gh:owner/repo` (dim, GitHub origin only — "GitHub にあげたっけ" の即答用), branch name in Git brand orange (`GIT`, `38;5;202`, Pantone 1788C), `from:<parent>` (dim, reflog `branch: Created from` パース — 切った元ブランチ), dirty state (A=staged/M=modified/?=untracked/U=conflicts — git standard symbols), ahead/behind, last commit age+message (20char truncated), detached HEAD (red). Non-git dirs show `(no git)`. Cold start (no cache yet) reads `.git/HEAD` directly (pure bash, no fork) to show branch name immediately (`gh:` is not shown in cold start — only after 5s background cache populates); worktree `.git` files with relative gitdir paths are resolved. `from:` は reflog が GC される (~90日) と消える / `from:HEAD` (=匿名 HEAD から作成) や clone 直後のブランチでは表示しない。`gh:owner/repo` は `git remote get-url origin` を SSH/HTTPS 両形式から正規化（既存の tree URL リンクと共通ロジック）、non-GitHub remote (GitLab 等) や origin 未設定では表示しない。public/private (visibility) は GitHub API 依存になるので未対応 (gh CLI の active account が `gh auth switch` で切り替わるとリポ毎に false negative を出すため意図的に避けている)。専用行にすることでパスの長さに関係なく git 情報が完全表示される。
- **Worktree indicator (Line 2)**: Shows 🌲 when `worktree.name` (CC worktree session) or `workspace.git_worktree` (git linked worktree, CC 2.1.97+) is set. `from:original_branch` (dim) is appended when `worktree.original_branch` is available (absent for hook-based worktrees). `worktree.path` overrides `current_dir` so that path display and `build_git()` reference the worktree directory, not the original repo.
- **Added dirs (Line 2)**: `workspace.added_dirs` (CC 2.1.78+) の配列長を `(+N dirs)` で表示。`/add-dir` でディレクトリを追加した場合のみ出現。
- **OSC 8 links (Line 2)**: `editor_url` で `file://` URL を生成し、パスをクリック可能にする。カスタムURLスキーム（`zed://` 等）はターミナルが対応しないため `file://` 固定。
- **OSC 8 links (Line 3 branch)**: `build_git()` 内でブランチ名を `${remote}/tree/${branch}` の OSC 8 リンクにする。**CC 組み込みのフッター PR badge** (`prUrlTemplate` でカスタマイズ可、PR状態dot + クリックリンク) と重複しないよう、tree URL のみ提供（PR への遷移は CC 側に任せる）。PRがないブランチでも GitHub に飛べる補完機能として機能。`git remote get-url origin` を SSH/HTTPS 両形式から正規化、non-GitHub remote（GitLab等）と detached HEAD はリンク化スキップ。OSC 8 ラップは既存の `osc8()` ヘルパー再利用。`gh` 依存を意図的に避けてネットワーク呼び出しゼロを維持。
- **Upstream tracking**: `~/ghq/github.com/anthropics/claude-code/CHANGELOG.md` で Claude Code の変更を確認。公開リポにソースコードはなく、CHANGELOG + plugins + scripts のみ。`/check-claude-code-update` skill (`.claude/skills/check-claude-code-update/`) が前回チェック済みハッシュを `.claude/upstream-last-checked` に保存し、差分から statusline 影響を分析する正規ワークフロー。
- **Line 4 (rate limit + context)**: 左から順に: 5h rate limit (`braille_bar` + %) → context window (`braille_bar` 5-char, `⣀⣄⣤⣦⣶⣷⣿`, 40 steps + %) → weekly rate limit。5h rate limitを最左に配置（最も頻繁に確認する情報）。Anthropic rate limit は stdin JSON `rate_limits` field (CC 2.1.80+)。`resets_at` is Unix epoch seconds (not ISO 8601). 5-hour in Anthropic sand (`ANTH`, `38;5;180`) with remaining time (`format_reset_remaining`), weekly in dim with absolute day/time reset (`format_reset_absolute`). Pre-2.1.80 CC では rate limit 部分が空（graceful degradation）。トークン数とコストは非表示（CCの `total_input_tokens` がキャッシュトークンを含まず誤解を招くため）。

## Key Constraints

- **Brand colors must match official branding** — model colors follow Anthropic's UI (claude.ai), provider colors follow each cloud's branding. Confirm with user before changing. **Indicator colors not tied to a brand** (e.g. `EFFORT`, `THINK`) are chosen to avoid collision with model tier colors (CORAL/TEAL/AMBER/LAVENDER); free to retune for legibility.
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
- **行数カウントは `grep -c .`** (単体): `wc -l | tr -d ' '` ではなく `grep -c .` を使う。forkが少なく macOS/Linux両方で安定。**`|| echo 0` は付けない**: `grep -c .` は no-match でも `"0"` を出力してから exit 1 するので、`|| echo 0` を付けると pipefail 下で stdout が `"0\n0"` の二重出力になり `((var > 0))` が syntax error を吐く。grep が無い等の異常時の defense は不要（grep は実質常駐）。
- **キャッシュは atomic mv で書き込み**: `build_git()` の background 書き出しは `> "${_gc}.tmp" && mv "${_gc}.tmp" "$_gc"` で必ず atomic 化する (`statusline-command.sh:383`)。CC は `refreshInterval` で定期再実行するため、同時に走る別呼び出しが書き込み中の cache を read すると半端な内容を表示する。直接 `>` で書く"シンプル化"は破壊的。
- **README の Line 説明は 3 箇所重複**: `README.md` 「表示レイアウト」(~L14-19) と「表示例」(~L26-31, 具体的なサンプル出力) と「スクリプト構造」(~L108-117) で Line 1-4 の役割を別々に記述している。表示変更時は **3 箇所すべて** + CLAUDE.md + CHANGELOG + バージョンバッジを更新しないと食い違う。
- **README バージョンバッジは手動同期**: L5-6 の `version-X.X.X` + `Claude_Code-X.X.X` は CHANGELOG bump 時に併せて手動更新する。自動同期はなく、放置すると数バージョン取り残される。
- **CHANGELOG のバージョン分割ルール**: 1 コミット = 1 マイナー版が原則（同日でも別コミットなら別バージョン）。**ただし同一コミット内で複数性質の変更（例: feat + fix）がある場合は1バージョンに同居** OK — 1.14.0 (Changed + Removed) や 1.11.0 (Changed + Removed) が前例。
