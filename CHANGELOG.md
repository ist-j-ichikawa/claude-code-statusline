# Changelog

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
