# Changelog

## [1.15.0] - 2026-05-07

### Added

- Branch name on Line 3 is now an OSC 8 hyperlink to the GitHub `tree/<branch>` page — クリックでブランチをブラウザで開ける。CC 組み込みのフッター PR badge は PR への遷移を担うので、ここでは tree URL のみ提供して役割分担。`git remote get-url origin` を SSH (`git@github.com:owner/repo`)、SSH URL (`ssh://git@github.com/owner/repo`)、HTTPS いずれの形式からも正規化、non-GitHub remote (GitLab 等) と detached HEAD はリンク化スキップ。`gh` への依存はなくネットワーク呼び出しゼロを維持

### Fixed

- `build_git()` の dirty state カウント (`grep -c .`) に付いていた `|| echo 0` を削除 — `grep -c .` は no-match でも "0" を出力してから exit 1 するため、`|| echo 0` を付けると pipefail 環境下で stdout が "0\n0" になり、`((staged > 0))` 等が syntax error を吐いて空のバックグラウンドキャッシュが書かれる事故が起きていた。`grep -c` 単体で意図通り動く

## [1.14.0] - 2026-05-07

### Changed

- Line 3 (git info) now always shows branch only — previously, when the current directory's basename differed from the repo name (e.g. browsing a subdirectory), Line 3 prefixed the output with the repo name (`claude-code main` instead of `main`). The location-dependent format was hard to remember and surprised the user every time they hit a subdirectory. Repo identification lives entirely on Line 2 (path), which already shows the full path; Line 3 is now a consistent branch-info-only row

### Removed

- `repo_name` derivation in `build_git()` and the caller-side basename comparison + string-stripping logic — eliminates 2-3 `git rev-parse` forks (`--git-dir`, `--git-common-dir`, `--show-toplevel`) per cache refresh. The new `[[ -z "$branch" ]] && return` early-return additionally short-circuits 4 git forks (diff/ls-files/rev-list/log) for non-git directories that previously executed before silently producing nothing

## [1.13.0] - 2026-05-07

### Added

- Effort and thinking indicator on Line 1 — `effort:high·think` between model and version. Reads `.effort.level` and `.thinking.enabled` from stdin JSON (CC 2.1.119+). CC stopped showing effort natively in recent versions, so the statusline surfaces it again. Colors chosen to avoid collision with model tier colors (CORAL/TEAL/AMBER/LAVENDER): `EFFORT=38;5;105` (light purple), `THINK=38;5;117` (light cyan). Level severity (`low`/`medium`/`high`/`xhigh`/`max`) is conveyed by the text — color is single-hue per indicator. Older CC versions without these fields render unchanged

## [1.12.0] - 2026-04-30

### Changed

- `added_dirs` indicator reverted from per-basename enumeration (`+foo +bar`) back to aggregate count (`(+N dirs)`) — with 3+ added directories, Line 2 overflowed the terminal width, wrapping the line and pushing Line 3 (git) and Line 4 (rate limit + context) below the visible statusline viewport. Aggregate count keeps Line 2 in one physical row regardless of how many directories were added; basename details remain recoverable from settings/`/add-dir` history

## [1.11.0] - 2026-04-21

### Changed

- Statusline layout expanded from 3 lines to 4 — path and git info are now on separate lines (Line 2: path/worktree, Line 3: git info). Previously, long paths + long git output combined on Line 2 often overflowed and got hidden
- `added_dirs` indicator changed from count (`(+2 dirs)`) to explicit basename enumeration (`+foo +bar`) — know at a glance which directories were added
- Parentheses removed from standalone indicators: `(branch)` → `branch`, `(+N dirs)` → `+N ...`, `(no git)` → `no git`. Parens reserved for within-element separation (e.g. `Anthropic(enterprise)`)
- Branch names in git info dropped parentheses: `(main)` → `main`, `(HEAD@abc1234)` → `HEAD@abc1234`. Git orange color already distinguishes the branch visually
- Untracked count `?N` color changed from DIM attribute to gray 248 — DIM rendering is terminal-dependent and blended visually with the adjacent DIM commit message; gray 248 is a fixed 256-color value that reliably distinguishes them

### Removed

- Terminal width adaptation — `COLUMNS`/`tput cols` detection, all `((_cols >= N))` conditionals, and width-based element hiding removed. Every element is now always shown at full length regardless of terminal width
- `_truncate_bytes` byte-level safety-net helper and its calls — no longer needed without width control
- Unreachable day branch in `format_reset_remaining` — 5h rate limit window never exceeds 5 hours, so the `%dd%dh` format was dead code

## [1.10.0] - 2026-04-13

### Removed

- Vim mode indicator (`[I]`/`[N]`) from Line 1 — Claude Code displays `-- INSERT --` / `-- NORMAL --` natively at the bottom of the screen, making the statusline indicator redundant

## [1.9.0] - 2026-04-10

### Changed

- Branch name color on Line 2 changed from green to Git brand orange (`38;5;202`, Pantone 1788C `#F03C2E`) — distinguishes branch from staged count (`A`, green) which previously blended together

## [1.8.0] - 2026-04-09

### Added

- Mantle provider detection — `CLAUDE_CODE_USE_MANTLE=1` is now detected as Bedrock (CC 2.1.94+, "Amazon Bedrock powered by Mantle")
- Git linked worktree indicator — `workspace.git_worktree` (CC 2.1.97+) shows 🌲 for manual `git worktree add` worktrees, not only CC `--worktree` sessions
- `refreshInterval: 30` recommended in README settings example (CC 2.1.97+ auto-reruns statusline every N seconds)

### Changed

- Built against badge updated from CC 2.1.76 to 2.1.97

## [1.7.0] - 2026-04-06

### Added

- `/add-dir` indicator on Line 2 — shows `(+N dirs)` when directories are added via `/add-dir` (CC 2.1.78+ `workspace.added_dirs`)
- OSC 8 clickable path links via `file://` on Line 2

### Changed

- Line 3 now shows only rate limits and context — removed token counts and session cost (CC's `total_input_tokens` excludes cache tokens, making the display misleading)

- Dirty state symbols now use git standard: `A` (staged), `M` (modified), `?` (untracked), `U` (conflicts) — was `+`, `~`, `?`, `!`
- Worktree origin indicator changed from `←branch` to `from:branch` for clarity
- Line 3 reordered: 5h rate limit → context → ↑tokens → ↓tokens → $ → weekly (rate limit moved to leftmost for quick glance)
- Directory path is now displayed in full (no truncation); git info is truncated from the right when terminal width is limited

### Removed

- `(no name)` indicator for unnamed sessions — CC shows session name natively
- Subdirectory display (`→ current_dir`) — project root is sufficient
- Stash count display — not relevant to Claude Code sessions
- Unused `session_id` jq extraction
- Dead `truncate_path` function

## [1.6.1] - 2026-04-03

### Fixed

- Worktree sessions now show the correct path and git branch — `worktree.path` from stdin JSON overrides `workspace.current_dir` which points to the original repo

## [1.6.0] - 2026-03-27

### Added

- Vim mode indicator on Line 1 — `[I]` (green) for INSERT, `[N]` (dim) for NORMAL; hidden when vim is disabled (CC 2.1.84+ `vim.mode` field)
- Worktree indicator on Line 2 via stdin JSON `worktree.name` / `worktree.original_branch` — replaces git-command-based detection (zero fork, instant on cold start)
- Session cost and token counts now displayed for all providers (was Bedrock/Vertex/Foundry only) — Anthropic sessions show cost + tokens + rate limit together on Line 3

### Changed

- Worktree 🌲 detection moved from `build_git()` git commands to stdin JSON API (no git fork needed)

## [1.5.2] - 2026-03-24

### Fixed

- Line 1 width adaptation — narrow terminals progressively drop subscription type (<45), agent name (<45), and model version suffix (<35) to prevent line wrapping that blanks all statusline rows
- Skip `fetch_subscription` on narrow terminals (<45 cols) to avoid unnecessary `stat` fork

## [1.5.1] - 2026-03-24

### Changed

- Replace `vscode://file/` URI scheme with `file://` in OSC 8 path links — clicks now open Finder (editor-agnostic) instead of requiring VSCode

## [1.5.0] - 2026-03-23

### Added

- Terminal width adaptation — narrow terminals progressively drop low-priority elements (version, session indicator, weekly rate limit, git info) to prevent line wrapping that hides Line 2/3
- Path truncation (`truncate_path`) — keeps the informative tail with `…` prefix when path exceeds 40% of terminal width
- Byte-level safety-net truncation (`_truncate_bytes`) on all output lines with ANSI escape cleanup

## [1.4.0] - 2026-03-21

### Changed

- Replace `progress_bar` (10-char ●○) with `braille_bar` (5-char braille dots ⣀⣄⣤⣦⣶⣷⣿) — 40 steps of precision in half the width
- Merge Line 3 (context) and Line 4 (rate limit / cost) into a single Line 3 — output reduced from 3-4 lines to always 3

### Fixed

- Initialize all jq variables before `eval` — prevents `set -u` instant death on jq failure
- Add numeric guards (`^[0-9]+$`) to all arithmetic functions — non-numeric input returns safe fallback instead of crashing
- Show `jq error` (red) on Line 1 when stdin JSON is unparseable, with exit 0

## [1.3.1] - 2026-03-21

### Fixed

- Parse `resets_at` as Unix epoch seconds — CC 2.1.80 stdin uses epoch (not ISO 8601 like the old OAuth API), restoring reset time and weekly info on Line 4
- Add `floor` guard on `resets_at` jq extraction to handle potential float epochs

### Changed

- Remove `iso_to_epoch()` — saves 2 forks per render by accepting epoch directly in `format_reset_remaining`/`format_reset_absolute`

## [1.3.0] - 2026-03-20

### Changed

- Migrate Anthropic rate limit from undocumented OAuth API to CC 2.1.80+ stdin `rate_limits` field
- Remove `get_oauth_token()`, `fetch_usage()`, and usage cache — ~50 lines deleted, 1 fewer jq fork
- Pre-2.1.80 CC gracefully degrades (Line 4 empty for Anthropic)

## [1.2.0] - 2026-03-17

### Added

- Show session cost and token counts on Line 4 for Bedrock/Vertex/Foundry — `$0.42 ↑125.0k ↓8.5k` (amber/teal/coral)
- Anthropic users continue to see rate limit bars as before

### Changed

- `format_tokens()` now displays one decimal place with lowercase suffix (e.g., `133.5k`, `1.5M`)

## [1.1.0] - 2026-03-17

### Changed

- Rename fork indicator to branch — detect both `(Branch)` (2.1.77+) and legacy `(Fork)`, display as `(branch)`

## [1.0.1] - 2026-03-16

### Fixed

- Suppress false "(no git)" on cold start for git repositories — use pure-bash `.git` check instead of relying on empty cache

## [1.0.0] - 2026-03-16

### Added

- Provider detection (Anthropic/Bedrock/Vertex/Foundry) with brand colors
- Model display with Anthropic brand colors (Opus=coral, Sonnet 4.6=teal, Sonnet 4.5/3.5=amber, Haiku=lavender)
- Git info: dirty state (+staged/~modified/?untracked/!conflicts), ahead/behind, stash count, last commit age+message, detached HEAD, worktree indicator
- Rate limit display for Anthropic provider
- Subscription type display from Keychain/credentials
- Session info: fork indicator (yellow), no-name indicator (dim), context window usage bar
- Background async refresh for I/O operations (git 5s, subscription 3600s)
- bats test suite with t-wada style naming (Japanese)
