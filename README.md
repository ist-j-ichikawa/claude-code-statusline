# Claude Code Statusline

j-ichikawa's custom statusline for [Claude Code](https://code.claude.com/) CLI.

![Version](https://img.shields.io/badge/version-1.40.0-blue)
![Built against](https://img.shields.io/badge/Claude_Code-2.1.212-purple)

## Overview

Claude Code の各アシスタント応答後に表示されるカスタムステータスラインです。セッション情報、Git 状態、コンテキスト使用量、コスト等をリアルタイムに表示します。

### 表示レイアウト

```
Line 1: [vim mode] + プロバイダー + Model + effort + think + Agent名 + Version + branch
Line 2: ディレクトリパス + 🌲worktree from:branch + added_dirs (+N dirs)
Line 3: Git ([gh:owner/repo] + ブランチ [OSC 8 リンク → GitHub tree] + PR review_state + base:親ブランチ + dirty state + ahead/behind + last commit)
Line 4: 5hレート制限 + コンテキストバー + weeklyレート制限 + extra-usage実課金 ($) + セッションコスト ($)
```

> セッション名は Claude Code 2.1.76+ で右上に組み込み表示されるため、ステータスラインには含みません。`/branch` セッション時は `branch` (黄) を表示します。
> 端末幅による表示切替は行いません。すべての要素が常時フル表示されます。

### 表示例

```
Anthropic(enterprise)  Fable 5 (1M context)  high  think  v2.1.212
~/dev/my-project  🌲 from:develop  (+2 dirs)
gh:acme/my-project  feature/x  approved  base:main  A3 M2 ?1 ↑2 1h fix: update logic..
⣿⣀    16%  2:20  ⣿⣿⣄   48%  week:9%  金 12:00  extra:$2.14  $4.83
```

origin 未設定 / 非 GitHub remote (GitLab 等) では `gh:` 部分が省略され、Line 3 はブランチ名から始まります — 「まだ GitHub に上げてないリポ」がひと目でわかります。

```
~/scratch/local-repo
master  0m initial commit
```

プロバイダー別の表示:
```
Anthropic(enterprise)  Opus 4.7 (1M context)  ...  ← Anthropic直接 (サンドベージュ + サブスク種別)
Bedrock  global.anthropic.claude-opus-4-7-v1  ...  ← AWS Bedrock (ティールグリーン)
Vertex  Opus 4.7  ...                    ← Google Vertex AI (ブルー)
Foundry  Opus 4.7  ...                   ← Microsoft Foundry (Azureブルー)
```

## Recommended Terminal: Ghostty

[Ghostty](https://ghostty.org/) を推奨します。Claude Code 公式の [terminal-config](https://code.claude.com/docs/en/terminal-config) でも紹介されており、本ステータスラインの全要件 (ANSI 256 色 + truecolor、OSC 8 ハイパーリンク、低レイテンシ描画) を満たします。

Claude Code 運用で特に便利な機能:

- **OSC 8 ハイパーリンク** — Line 2 のパス (`file://` で Finder/IDE へ) と Line 3 のブランチ名 (GitHub `tree/<branch>` へ) がクリック可能になる
- **[Shell Integration](https://ghostty.org/docs/features/shell-integration)** — bash/zsh/fish/elvish/nushell で自動セットアップ、新規ウィンドウが前の cwd を継承、`jump-to-prompt` で過去のプロンプト間をスキップ
- **Splits & Tabs** — `⌘D` / `⌘⇧D` で分割 (右 / 下)、`⌘T` で新規タブ。タブ名は最終実行コマンドで自動更新（複数 Claude Code を並走させる用途に最適）
- **Quick Terminal** — `toggle_quick_terminal` を任意のキーバインドに割り当てるとドロップダウン式の即時セッションが使える (デフォルトキーは未設定。macOS / Linux GTK 対応)
- **Config Hot-reload** — `⌘⇧,` (macOS) で設定即時反映、ステータスラインのテーマ調整が高速
- **Metal GPU レンダリング** — `refreshInterval` (30s) ごとの再描画でもフリッカーなし

設定ファイル (macOS): `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`

> 他ターミナル (iTerm2, WezTerm, kitty, Alacritty 等) でも動作しますが、OSC 8 対応の差でクリック可能リンクが平文表示になる場合があります。

## Installation

このスクリプトは**リポジトリを直接参照**する運用を推奨します。コピーを作らないので、このリポジトリが single source of truth のまま `git pull` だけで更新が反映されます。

### 1. リポジトリを clone

```bash
git clone https://github.com/ist-j-ichikawa/claude-code-statusline.git
# ghq 派は: ghq get ist-j-ichikawa/claude-code-statusline
```

### 2. settings.json に登録

`~/.claude/settings.json` に、clone したスクリプトの**絶対パス**を指定します:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/path/to/claude-code-statusline/statusline-command.sh",
    "refreshInterval": 30,
    "hideVimModeIndicator": true
  }
}
```

> **Note:** `/path/to/...` は clone 先の実際の絶対パスに置き換えてください (`~` は展開されないので絶対パスで書きます)。スクリプトは実行ビット付きでコミットされているため `chmod` は不要です。

`refreshInterval` (Claude Code 2.1.97+) はステータスラインを N 秒ごとに自動再実行する設定です。レート制限の残り時間やGit状態がアイドル中も更新されます。30秒推奨。

`hideVimModeIndicator: true` は Claude Code 組み込みの `-- INSERT --` 表示を抑止します。本スクリプトは vim mode を Line 1 先頭に目立つバッジで自前描画するため、これを `true` にして二重表示を防ぎます (vim mode を使う場合の推奨設定)。

### 代替: clone せず ~/.claude に置く

clone を残したくない場合は、公開リポジトリからスクリプトだけを直接ダウンロードして `~/.claude` に配置できます。ただしこれは**コピー**なので、更新は手動 (再ダウンロード) になります:

```bash
curl -fsSL -o ~/.claude/statusline-command.sh \
  https://raw.githubusercontent.com/ist-j-ichikawa/claude-code-statusline/main/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

この場合は settings.json の `command` を `/Users/<username>/.claude/statusline-command.sh` (絶対パス) に向けます。

## 実装詳細

スクリプトの仕組み・構造・カラーテーマ・パフォーマンス最適化・Line 4 の内訳・クラウドプロバイダー検出ロジックは **[docs/internals.md](docs/internals.md)** にまとめています。

## Requirements

- [Claude Code](https://code.claude.com/) CLI
- `jq` (JSON parser)
- `curl` (`fetch_subscription()` のみ — Keychain の OAuth トークンを stdin 経由で渡してサブスクリプション種別を取得)
- `git` (Git 情報表示用)
- Bash 3.2+ (macOS 標準の `/bin/bash` で動作 — bash 4+ 機能は使わない)
- macOS 専用: `stat -f %m` / `md5 -q -s` を使用

## License

MIT
