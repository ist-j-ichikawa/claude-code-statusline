# Claude Code Statusline

j-ichikawa's custom statusline for [Claude Code](https://code.claude.com/) CLI.

![Version](https://img.shields.io/badge/version-1.29.0-blue)
![Built against](https://img.shields.io/badge/Claude_Code-2.1.173-purple)

## Overview

Claude Code の各アシスタント応答後に表示されるカスタムステータスラインです。セッション情報、Git 状態、コンテキスト使用量、コスト等をリアルタイムに表示します。

### 表示レイアウト

```
Line 1: [vim mode] + プロバイダー + Model + effort + think + Agent名 + Version + branch
Line 2: ディレクトリパス + 🌲worktree from:branch + added_dirs (+N dirs)
Line 3: Git ([gh:owner/repo] + ブランチ [OSC 8 リンク → GitHub tree] + PR review_state + from:親ブランチ + dirty state + ahead/behind + last commit)
Line 4: 5hレート制限 + コンテキストバー + weeklyレート制限 + セッションコスト ($)
```

> セッション名は Claude Code 2.1.76+ で右上に組み込み表示されるため、ステータスラインには含みません。`/branch` セッション時は `branch` (黄) を表示します。
> 端末幅による表示切替は行いません。すべての要素が常時フル表示されます。

### 表示例

```
Anthropic(enterprise)  Fable 5 (1M context)  high  think  v2.1.173
~/dev/my-project  🌲 from:develop  (+2 dirs)
gh:acme/my-project  feature/x  approved  from:main  A3 M2 ?1 ↑2 1h fix: update logic..
⣿⣀    16%  2:20  ⣿⣿⣄   48%  week:9%  金 12:00  $4.83
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
    "refreshInterval": 30
  }
}
```

> **Note:** `/path/to/...` は clone 先の実際の絶対パスに置き換えてください (`~` は展開されないので絶対パスで書きます)。スクリプトは実行ビット付きでコミットされているため `chmod` は不要です。

`refreshInterval` (Claude Code 2.1.97+) はステータスラインを N 秒ごとに自動再実行する設定です。レート制限の残り時間やGit状態がアイドル中も更新されます。30秒推奨。

### 代替: clone せず ~/.claude に置く

clone を残したくない場合は、公開リポジトリからスクリプトだけを直接ダウンロードして `~/.claude` に配置できます。ただしこれは**コピー**なので、更新は手動 (再ダウンロード) になります:

```bash
curl -fsSL -o ~/.claude/statusline-command.sh \
  https://raw.githubusercontent.com/ist-j-ichikawa/claude-code-statusline/main/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

この場合は settings.json の `command` を `/Users/<username>/.claude/statusline-command.sh` (絶対パス) に向けます。

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
├── Git info         build_git() — ブランチ、dirty state、ahead/behind、last commit (age + msg)（5秒バックグラウンドキャッシュ、atomic mv 書き込み）
├── Line 1           [vim mode バッジ (INSERT=ライムグリーン bg / VISUAL・V-LINE=ゴールド bg、NORMAL は非表示)] + プロバイダー + モデル名（Fable=スチールブルー, Opus=コーラル, Sonnet 4.6=ティール, Sonnet 4.5=アンバー, Haiku=ラベンダー）+ effort（light purple）+ think（light cyan）+ Agent + Version + branch
├── Line 2           ディレクトリパス (OSC 8 リンク) + 🌲worktree + from:branch + added_dirs (+N dirs)
├── Line 3           Git ([gh:owner/repo (dim, GitHub origin あり時のみ)] + ブランチ [OSC 8 リンク → GitHub tree] + PR review_state (Claude Code 2.1.145+ pr.review_state、テキスト色分け、PR # は Claude Code 組み込み footer に任せて非表示) + from:親ブランチ (reflog) + dirty state + ahead/behind + last commit)、非git時は "no git"
├── Line 4           5hレート制限 + コンテキストバー + weeklyレート制限 (Anthropic のみ) + セッションコスト ($、dim)
└── Output           printf で各行を出力
```

### カラーテーマ

| 指標 | 色 | ANSIコード |
|---|---|---|
| vim mode `INSERT` | 黒文字 / ライムグリーン bg (bold) | 1;30;48;5;148 |
| vim mode `VISUAL` / `V-LINE` | 黒文字 / ゴールド bg (bold) | 1;30;48;5;214 |
| コンテキスト使用率 | < 80% lime green / 80-89% 黄 / >= 90% 赤 | 38;5;82 / 33 / 31 |
| Fable | スチールブルー | 38;5;74 |
| Opus | コーラル | 38;5;209 |
| Sonnet 4.6 | ティール | 38;5;79 |
| Sonnet 4.5 / 3.5 | アンバー | 38;5;214 |
| Haiku | ラベンダー | 38;5;183 |
| Anthropic / 5hレート制限 | サンドベージュ | 38;5;180 |
| Bedrock | ティールグリーン | 38;5;72 |
| Vertex | Google ブルー | 38;5;33 |
| Foundry | Azure ブルー | 38;5;39 |
| effort (`low`/`high`/`max`) | light purple | 38;5;105 |
| think | light cyan | 38;5;117 |
| Agent 名 | ピンク | 38;5;213 |
| version (`v2.1.x`) | グレー | 38;5;248 |
| branch セッション (`branch`) | 黄 | 33 |
| Git ブランチ名 | Git brand オレンジ | 38;5;202 |
| Git staged `A` / ahead `↑` | 緑 | 32 |
| Git modified `M` | 黄 | 33 |
| Git untracked `?` | グレー | 38;5;248 |
| Git conflicts `U` / behind `↓` / Detached HEAD | 赤 | 31 |
| last commit (age + msg)、worktree from、Git branch parent (`from:`)、Git origin (`gh:owner/repo`) / weekly rate limit / セッションコスト (`$X.XX`) | dim | 2 |

### パフォーマンス

- **バックグラウンド更新**: Git (5秒) と Subscription 種別取得 (3600秒) はサブシェルで非同期更新。stale キャッシュを即座に返すため出力をブロックしない
- **単一 jq 呼び出し**: stdin JSON を `eval` + `@sh` で一括抽出（フィールドごとの再パースなし）
- **共有タイムスタンプ**: `_NOW=$(date +%s)` を1回だけ呼び、全キャッシュ判定で再利用
- **キャッシュ**: `/tmp/ist-j-ichikawa-claude-statusline/{git,subscription}` (mkdir 700) に保存
- **Git worktree 対応**: stdin JSON の `worktree.name` または `workspace.git_worktree` (Claude Code 2.1.97+) を検出して 🌲 を表示

### Line 4: レート制限 + コンテキストバー + コスト

**Anthropic** (rate_limits が届く場合)
- Claude Code 2.1.80+ の stdin JSON `rate_limits` フィールドから直接取得
- 表示: 5hバー + % + リセット残(H:MM) → コンテキストバー + % → week:% + リセット曜日時刻 → セッションコスト
- Pre-2.1.80 ではレート制限部分が非表示（graceful degradation）

**Bedrock / Vertex AI / Foundry**
- `rate_limits` フィールドは届かないため、コンテキストバーとコストのみ表示

**セッションコスト** (`$X.XX`、dim、最右)
- stdin JSON `cost.total_cost_usd` をそのまま表示。Claude Code がキャッシュ区分 (cache read/write) 込みで計算済みの API 換算額
- subscription (Max 等) 利用時は実請求ではなく参考値 — 優先度の低い情報として最右・dim 配置
- `$0.00` (セッション開始直後) とフィールド欠落 (旧 Claude Code) では非表示
- トークン数は引き続き非表示（Claude Code の `total_input_tokens` がキャッシュトークンを含まず誤解を招くため）

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
- `curl` (`fetch_subscription()` のみ — Keychain の OAuth トークンを stdin 経由で渡してサブスクリプション種別を取得)
- `git` (Git 情報表示用)
- Bash 3.2+ (macOS 標準の `/bin/bash` で動作 — bash 4+ 機能は使わない)
- macOS 専用: `stat -f %m` / `md5 -q -s` を使用

## License

MIT
