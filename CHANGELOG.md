# Changelog

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
