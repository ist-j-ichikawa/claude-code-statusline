# Claude Code Statusline

j-ichikawa's custom statusline for [Claude Code](https://code.claude.com/) CLI.

![Version](https://img.shields.io/badge/version-1.54.0-blue)
![Built against](https://img.shields.io/badge/Claude_Code-2.1.220-purple)

## Overview

Claude Code の各アシスタント応答後に表示されるカスタムステータスラインです。セッション情報、Git 状態、コンテキスト使用量、コスト等をリアルタイムに表示します。

### 表示レイアウト

```
Line 1: [vim mode] + プロバイダー + Model + effort + think + fast + Agent名 + Version + branch
Line 2: ディレクトリパス + 🌲worktree名 from:branch + added_dirs (+N dirs)
Line 3: Git ([gh:owner/repo] + ブランチ [OSC 8 リンク → GitHub tree] + PR review_state + base:親ブランチ + dirty state + ahead/behind + last commit)
Line 4: 5hレート制限 + コンテキストバー (1M時は /1M) + weeklyレート制限 + extra-usage実課金 ($) + セッション経過時間 + セッションコスト ($)
```

> セッション名は Claude Code 2.1.76+ で右上に組み込み表示されるため、ステータスラインには含みません。`/branch` セッション時は `branch` (黄) を表示します。
> 端末幅による表示切替は行いません。すべての要素が常時フル表示されます。

### 表示例

```
Anthropic(enterprise)  Opus 5  high  think  fast  v2.1.220
~/dev/my-project  🌲my-feature  from:develop  (+2 dirs)
gh:acme/my-project  feature/x  approved  base:main  A3 M2 ?1 ↑2 1h fix: update logic..
⣿⣀    16%  2:20  ⣿⣿⣄   48%/1M  week:9%  金 12:00  extra:$2.14  3h24m  $4.83
```

origin 未設定 / 非 GitHub remote (GitLab 等) では `gh:` 部分が省略され、Line 3 はブランチ名から始まります — 「まだ GitHub に上げてないリポ」がひと目でわかります。`gh:` プレフィックスは dim、`owner/repo` は通常輝度です — ローカルのディレクトリ名と origin のリポジトリ名が食い違っていても、どこの repo かがここで判別できます。

worktree セッションで `<repo>/.claude/worktrees/<名前>` 配下にいる場合、パスはリポジトリ root までで切り、worktree 名を 🌲 の直後に表示します（上の Line 2 例）。パス末尾がランダムな worktree 名で占領されず、リポジトリのディレクトリ名がパス末尾に残ります。リンクはパス部分がリポ root、worktree 名部分が worktree ディレクトリを開きます。

```
~/scratch/local-repo
master  0m initial commit
```

プロバイダー別の表示:
```
Anthropic(enterprise)  Opus 5  ...                ← Anthropic直接 (サンドベージュ + サブスク種別)
Bedrock  global.anthropic.claude-opus-5-v1  ...   ← AWS Bedrock (ティールグリーン)
Vertex  Opus 5  ...                      ← Google Vertex AI (ブルー)
Foundry  Opus 5  ...                     ← Microsoft Foundry (Azureブルー)
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

```bash
git clone https://github.com/ist-j-ichikawa/claude-code-statusline.git
cd claude-code-statusline
./install.sh --dry-run   # まず何が変わるか差分で確認
./install.sh             # 差分を表示して y/N を聞いた上で書き込む
```

グローバル設定 (`~/.claude/settings.json`) を触るので、**差分を見せて確認するまで一切書き込みません**。手で JSON を編集したい場合は下の折りたたみに手順があります。

`install.sh` の挙動:

- `statusLine` と `subagentStatusLine` を**clone 先の絶対パスで**登録（`~` は展開されないため、パスを自分で書き写す必要をなくしています）
- **既存の設定は保ったままマージ** — 他のキーはそのまま。`refreshInterval` / `hideVimModeIndicator` を既に自分で決めている場合はその値を尊重し、未設定のときだけ推奨値 `30` / `true` を入れます
- **既存の `statusLine` が別のツールを指している場合は名指しで警告**してから確認を求めます（無警告で奪いません）
- 書き換え前に**タイムスタンプ付きバックアップ**を作成（`settings.json.bak.20260727043008`）。固定名にしないので、2 回実行しても最初のバックアップは残ります
- `settings.json` が **symlink（dotfiles 管理）ならリンクを壊さず実体に書き込み**ます
- 登録前にスクリプトを試走し、動かなければ何も書かずに中止
- 冪等 — 既に同じ内容なら「変更なし」で終了し、バックアップも作りません

| オプション | 用途 |
|---|---|
| `-n`, `--dry-run` | 変更内容を表示するだけで書き込まない |
| `-y`, `--yes` | 確認プロンプトを省略（非対話環境ではこれが必須。付けないと中止します） |
| `--main-only` | サブエージェント行は Claude Code 既定のままにする |
| `CLAUDE_SETTINGS=<path>` | 書き込み先の settings.json を差し替える |

**更新は `git pull` だけ** — コピーを作らずリポジトリを直接参照するので、このリポジトリが single source of truth のままになります。

<details>
<summary>すでにインストール済みの場合（v1.49.0 以前から）</summary>

**`git pull` だけで更新は完了します。** 再インストールは不要です（settings.json はスクリプトを絶対パスで参照しているだけなので、中身が新しくなればそのまま反映されます）。

`./install.sh` を再実行しても安全です — 冪等なので、既に同じ内容なら「変更なし」で終了します。差分があれば表示して確認を求めます。以下が新しく入る/変わる可能性があります:

- `subagentStatusLine`（v1.45.0 以降の追加機能。未設定なら足されます）
- `refreshInterval` / `hideVimModeIndicator`（**未設定のときだけ**推奨値が入ります。自分で値を決めている場合はそのまま尊重されます）
- `command` が `/bin/bash <path>` の形に揃います（実行ビット経由でも同じ `/bin/bash` が使われるので挙動は同じです）

**キャッシュの置き場が変わりました**（v1.52.0）。`/tmp/ist-j-ichikawa-claude-statusline` から、ユーザー単位の `$TMPDIR/claude-statusline-<uid>` になります。移行作業は不要で、初回だけ Git 情報が 5 秒遅れて出ます。旧ディレクトリは放置しても macOS が定期的に掃除しますが、気になる場合は消せます:

```bash
rm -rf /tmp/ist-j-ichikawa-claude-statusline
```

</details>

<details>
<summary>settings.json を自分で書きたい場合</summary>

`~/.claude/settings.json` に clone 先の**絶対パス**で指定します:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/path/to/claude-code-statusline/statusline-command.sh",
    "refreshInterval": 30,
    "hideVimModeIndicator": true
  },
  "subagentStatusLine": {
    "type": "command",
    "command": "/path/to/claude-code-statusline/subagent-statusline-command.sh"
  }
}
```

- `/path/to/...` は clone 先の実際の絶対パスに置き換えます (`~` は展開されません)。スクリプトは実行ビット付きでコミットされているので `chmod` は不要です
- `refreshInterval` (Claude Code 2.1.97+) はステータスラインを N 秒ごとに自動再実行します。レート制限の残り時間や Git 状態がアイドル中も更新されます。30 秒推奨
- `hideVimModeIndicator: true` は Claude Code 組み込みの `-- INSERT --` 表示を抑止します。本スクリプトは vim mode を Line 1 先頭に目立つバッジで自前描画するため、`true` にして二重表示を防ぎます
- `subagentStatusLine` はメインの `statusLine` とは独立した設定です。省略すれば Claude Code 既定の行 (`名前 · 説明 · トークン数`) のままになります
- どちらのスクリプトも同じディレクトリの `lib.sh` (共有ライブラリ) を読み込みます。clone した場合は同梱されているので追加作業は不要です

</details>

### サブエージェント行

`subagentStatusLine` は agent panel に並ぶサブエージェントの各行を、メインの statusline と協調した配色で描画します。各行は **説明 + モデル(tier 色) + [入力待ち等の状態] + [🌲worktree]** です（行頭の `❯ ◯` と「実行中」表示は Claude Code 側が描画）:

```
❯ ◯ review the diff for correctness bugs   Sonnet 5
❯ ◯ /code-review xhigh                     Opus 5     🌲issue-41
❯ ◯ 承認待ちのデプロイ                       Opus 5     needs_input
```

- **モデル**は Line 1 と同じ表記・tier 色（Bedrock の `jp.anthropic.claude-opus-5` 等も `Opus 5` に整形）
- **状態**は通常は出さず（実行中は Claude Code 標準の `○`/スピナーが示す）、`needs_input` など**注意が要る時だけ黄色い語**で表示
- **worktree** 隔離エージェントは作業先を `🌲名` で表示
- コンテキスト% と経過時間は**あえて出しません** — 並走するサブエージェントはどれも似た値になり（実測 5〜9% / 5〜6 分）、行が伸びるだけで判断に効きませんでした

<details>
<summary>代替: clone せず ~/.claude に置く</summary>

clone を残したくない場合は、公開リポジトリからスクリプトを直接ダウンロードして `~/.claude` に配置できます。ただしこれは**コピー**なので、更新は手動 (再ダウンロード) になります。`lib.sh` はスクリプトと同じディレクトリに必須です:

```bash
mkdir -p ~/.claude
# 共有ライブラリ (必須) + メイン statusline
curl -fsSL -o ~/.claude/lib.sh \
  https://raw.githubusercontent.com/ist-j-ichikawa/claude-code-statusline/main/lib.sh
curl -fsSL -o ~/.claude/statusline-command.sh \
  https://raw.githubusercontent.com/ist-j-ichikawa/claude-code-statusline/main/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
# (任意) サブエージェント行のカスタマイズも使う場合
curl -fsSL -o ~/.claude/subagent-statusline-command.sh \
  https://raw.githubusercontent.com/ist-j-ichikawa/claude-code-statusline/main/subagent-statusline-command.sh
chmod +x ~/.claude/subagent-statusline-command.sh
```

この場合は settings.json の `command` を `/Users/<username>/.claude/statusline-command.sh` (絶対パス) に向けます。

</details>

## 実装詳細

スクリプトの仕組み・構造・カラーテーマ・パフォーマンス最適化・Line 4 の内訳・クラウドプロバイダー検出ロジックは **[docs/internals.md](docs/internals.md)** にまとめています。

## Requirements

- [Claude Code](https://code.claude.com/) CLI
- `jq` (JSON parser)
- `curl` (`fetch_usage_spend()` のみ — extra-usage の実課金額取得。OAuth トークンは argv に出さず stdin 経由で渡す。サブスクリプション種別の取得はネットワークを使わず Keychain 読みだけ)
- `git` (Git 情報表示用)
- Bash 3.2+ (macOS 標準の `/bin/bash` で動作 — bash 4+ 機能は使わない)
- macOS 専用: `stat -f %m` / `md5 -q -s` を使用

## License

MIT
