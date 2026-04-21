# Claude Code Statusline

j-ichikawa's custom statusline for [Claude Code](https://code.claude.com/) CLI.

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Built against](https://img.shields.io/badge/Claude_Code-2.1.97-purple)

## Overview

Claude Code の各アシスタント応答後に表示されるカスタムステータスラインです。セッション情報、Git 状態、コンテキスト使用量、コスト等をリアルタイムに表示します。

### 表示レイアウト

```
Line 1: プロバイダー + Model + Agent名 + Version + branch
Line 2: ディレクトリパス + added_dirs (+foo +bar) + 🌲worktree from:branch
Line 3: Git (repo + ブランチ + dirty state + ahead/behind + last commit)
Line 4: 5hレート制限 + コンテキストバー + weeklyレート制限
```

> セッション名は Claude Code 2.1.76+ で右上に組み込み表示されるため、ステータスラインには含みません。`/branch` セッション時は `branch` (黄) を表示します。
> 端末幅による表示切替は行いません。すべての要素が常時フル表示されます。

### 表示例

```
Anthropic(enterprise)  Opus 4.7 (1M context)  v2.1.111
~/dev/my-project  +foo  +bar  🌲 from:develop
main A3 M2 ?1 ↑2 1h fix: update logic..
⣿⣀    16%  2:20  ⣿⣿⣄   48%  week:9%  金 12:00
```

プロバイダー別の表示:
```
Anthropic(enterprise)  Opus 4.6 (1M context)  ...  ← Anthropic直接 (サンドベージュ + サブスク種別)
Bedrock  global.anthropic.claude-opus-4-6-v1  ...  ← AWS Bedrock (ティールグリーン)
Vertex  Opus 4.6  ...                    ← Google Vertex AI (ブルー)
Foundry  Opus 4.6  ...                   ← Microsoft Foundry (Azureブルー)
```

## Installation

### 1. スクリプトを配置

```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

### 2. settings.json に登録

`~/.claude/settings.json` に以下を追加します:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/bin/bash /Users/<username>/.claude/statusline-command.sh",
    "refreshInterval": 30
  }
}
```

> **Note:** `<username>` は自分のユーザー名に置き換えてください。

`refreshInterval` (CC 2.1.97+) はステータスラインを N 秒ごとに自動再実行する設定です。レート制限の残り時間やGit状態がアイドル中も更新されます。30秒推奨。

## Shell Script Details

### 仕組み

Claude Code はアシスタントの応答ごとに（300ms デバウンス付きで）このスクリプトを呼び出します。セッション情報は JSON で **stdin** に渡され、`printf` の出力がそのままステータスラインの各行になります。ANSI カラーと OSC 8 ハイパーリンクに対応しています。

### 入力 JSON フィールド

stdin で受け取るフィールドの一覧は公式ドキュメントを参照:
[Available data — Claude Code Statusline](https://code.claude.com/docs/en/statusline#available-data)

### スクリプト構造

```
statusline-command.sh
├── Constants        ANSI色定数、キャッシュ設定、_NOW タイムスタンプ
├── Helpers          has_val(), cache_stale(), braille_bar(pct), etc.
├── Subscription     fetch_subscription() — Keychain からサブスクリプション種別を取得（バックグラウンドキャッシュ）
├── JSON extraction  単一の jq 呼び出しで全フィールドを抽出
├── Git info         build_git() — ブランチ、dirty state、ahead/behind、stash、last commit（5秒バックグラウンドキャッシュ）
├── Line 1           プロバイダー + モデル名（Opus=コーラル, Sonnet 4.6=ティール, Sonnet 4.5=アンバー, Haiku=ラベンダー）+ Agent + Version + branch
├── Line 2           ディレクトリパス (OSC 8 リンク) + added_dirs basename 列挙 + 🌲worktree + from:branch
├── Line 3           Git (repo + ブランチ + dirty state + ahead/behind + last commit)、非git時は "no git"
├── Line 4           5hレート制限 + コンテキストバー + weeklyレート制限 (Anthropic のみ)
└── Output           printf で各行を出力
```

### カラーテーマ

| 指標 | 色 | ANSIコード |
|---|---|---|
| コンテキスト使用率 | < 80% 緑 / 80-89% 黄 / >= 90% 赤 | — |
| Opus | コーラル | 38;5;209 |
| Sonnet 4.6 | ティール | 38;5;79 |
| Sonnet 4.5 | アンバー | 38;5;214 |
| Haiku | ラベンダー | 38;5;183 |
| Anthropic | サンドベージュ | 38;5;180 |
| Bedrock | ティールグリーン | 38;5;72 |
| Vertex | Google ブルー | 38;5;33 |
| Foundry | Azure ブルー | 38;5;39 |
| レート制限 | サンドベージュ | 38;5;180 |
| Git staged `+N` | 緑 | — |
| Git modified `~N` | 黄 | — |
| Git untracked `?N` | dim | — |
| Git conflicts `!N` | 赤 | — |
| Git ahead `↑N` | 緑 | — |
| Git behind `↓N` | 赤 | — |
| Detached HEAD | 赤 | — |
| stash / last commit | dim | — |

### パフォーマンス

- **バックグラウンド更新**: Git (5秒) と Usage API (300秒) はサブシェルで非同期更新。stale キャッシュを即座に返すため出力をブロックしない
- **単一 jq 呼び出し**: stdin JSON と usage JSON それぞれ `eval` + `@sh` で一括抽出
- **共有タイムスタンプ**: `_NOW=$(date +%s)` を1回だけ呼び、全キャッシュ判定で再利用
- **キャッシュ**: `/tmp/ist-j-ichikawa-claude-statusline/{git,subscription}` に保存
- **Git worktree 対応**: `git-dir` と `git-common-dir` を比較し、worktree 使用時は 🌲 アイコン表示

### Line 4: レート制限 + コンテキストバー

**Anthropic** (rate_limits が届く場合)
- CC 2.1.80+ の stdin JSON `rate_limits` フィールドから直接取得
- 表示: 5hバー + % + リセット残(H:MM) → コンテキストバー + % → week:% + リセット曜日時刻
- Pre-2.1.80 ではレート制限部分が非表示（graceful degradation）

**Bedrock / Vertex AI / Foundry**
- `rate_limits` フィールドは届かないため、コンテキストバーのみ表示
- トークン数とコストは非表示（CCの `total_input_tokens` がキャッシュトークンを含まず誤解を招くため）

### クラウドプロバイダー検出

| プロバイダー | 検出条件 |
|---|---|
| Bedrock | `model.id` プレフィックス (`global.`/`jp.`/`us.`/`eu.`/`au.`/`apac.`) or `CLAUDE_CODE_USE_BEDROCK=1` or `CLAUDE_CODE_USE_MANTLE=1` |
| Vertex AI | `CLAUDE_CODE_USE_VERTEX=1` |
| Foundry | `CLAUDE_CODE_USE_FOUNDRY=1` |
| Anthropic | 上記以外 |

## Requirements

- [Claude Code](https://code.claude.com/) CLI
- `jq` (JSON parser)
- `curl` (レート制限API取得用)
- `git` (Git 情報表示用)
- Bash 4+

## License

MIT
