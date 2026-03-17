# Claude Code Statusline

j-ichikawa's custom statusline for [Claude Code](https://code.claude.com/) CLI.

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Built against](https://img.shields.io/badge/Claude_Code-2.1.76-purple)

## Overview

Claude Code の各アシスタント応答後に表示されるカスタムステータスラインです。セッション情報、Git 状態、コンテキスト使用量、コスト等をリアルタイムに表示します。

### 表示レイアウト

```
Line 1: プロバイダー + Model + Agent名 + Version + (branch)/(no name)
Line 2: ディレクトリパス(→遷移) + Git (ブランチ + dirty state + ahead/behind + stash + last commit)
Line 3: コンテキストバー
Line 4: レート制限バー (Anthropic) / セッションコスト+トークン数 (Bedrock/Vertex/Foundry)
```

> セッション名は Claude Code 2.1.76+ で右上に組み込み表示されるため、ステータスラインには含みません。未設定時は `(no name)`、ブランチ時は `(branch)` を表示します。

### 表示例

```
Anthropic  Opus 4.6 (1M context)  v2.1.76
~/dev/my-project → ~/dev/my-project/src  (main) +3 ~2 ?1 ↑2 1h fix: update logic..
●●●●●○○○○○ 48%
●●○○○○○○○○ 16%  2:20  week:9%  金 12:00
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
    "command": "/bin/bash /Users/<username>/.claude/statusline-command.sh"
  }
}
```

> **Note:** `<username>` は自分のユーザー名に置き換えてください。

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
├── Helpers          has_val(), cache_stale(), progress_bar(pct, style), etc.
├── OAuth/Usage      get_oauth_token(), fetch_usage() — バックグラウンド更新
├── JSON extraction  単一の jq 呼び出しで全フィールドを抽出
├── Git info         build_git() — ブランチ、dirty state、ahead/behind、stash、last commit（5秒バックグラウンドキャッシュ）
├── Line 1           プロバイダー + モデル名（Opus=コーラル, Sonnet 4.6=ティール, Sonnet 4.5=アンバー, Haiku=ラベンダー）+ Agent + Version + (branch)/(no name)
├── Line 2           ディレクトリパス(→遷移) + Git ブランチ + dirty state + ahead/behind + stash + last commit
├── Line 3           コンテキストバー
├── Line 4           レート制限バー (Anthropic) / コスト+トークン数 (Bedrock/Vertex/Foundry)
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
- **キャッシュ**: `/tmp/ist-j-ichikawa-claude-statusline/{git,usage}` に保存
- **Git worktree 対応**: `git-dir` と `git-common-dir` を比較し、worktree 使用時は 🌲 アイコン表示

### Line 4: プロバイダー別表示

**Anthropic (レート制限)**
- 非公開 OAuth API (`api.anthropic.com/api/oauth/usage`) 経由で取得
- OAuth トークン: 環境変数 → macOS Keychain → `~/.claude/.credentials.json`
- 300秒バックグラウンドキャッシュ — ステータスラインをブロックしない
- 表示: 5時間バー + % + リセット残(h:mm) + week:% + リセット曜日時刻(dow HH:MM)
- ネイティブサポートの Feature Request: https://github.com/anthropics/claude-code/issues/20636

**Bedrock / Vertex AI / Foundry (セッションコスト)**
- Claude Code の stdin JSON から `cost.total_cost_usd` と `total_input/output_tokens` を取得
- 表示: `$0.42 133.5k tok` — セッション累計コストとトークン数

### クラウドプロバイダー検出

| プロバイダー | 検出条件 |
|---|---|
| Bedrock | `model.id` プレフィックス (`global.`/`jp.`/`us.`/`eu.`/`au.`/`apac.`) or `CLAUDE_CODE_USE_BEDROCK=1` |
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
