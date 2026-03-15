# Changelog

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
