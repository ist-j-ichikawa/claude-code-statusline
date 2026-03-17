# Changelog

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
- Rate limit display via OAuth API with 300s background refresh
- Subscription type display from Keychain/credentials
- Session info: fork indicator (yellow), no-name indicator (dim), context window usage bar
- Background async refresh for all I/O operations (git 5s, usage API 300s, gh account 60s)
- bats test suite with t-wada style naming (Japanese)
