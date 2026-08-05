# Claude Code Statusline

j-ichikawa's custom statusline for [Claude Code](https://code.claude.com/) CLI.

![Version](https://img.shields.io/badge/version-1.66.0-blue)
![Built against](https://img.shields.io/badge/Claude_Code-2.1.222-purple)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)

## Overview

Claude Code の各アシスタント応答後に表示されるカスタムステータスラインです。
セッション情報、Git 状態、コンテキスト使用量、コスト等をリアルタイムに表示します。

### 表示レイアウト

| 行 | 内容 |
|---|---|
| **Line 1** | vim mode · プロバイダー · Model · effort · think · fast · Agent 名 · Version · branch / fork |
| **Line 2** | ディレクトリパス · 🌲worktree 名 · `from:`元ブランチ · `(+N dirs)` |
| **Line 3** | `gh:`owner/repo · ブランチ (OSC 8 → GitHub tree) · PR review_state · `base:`親ブランチ · dirty state · ahead/behind · last commit |
| **Line 4** | 5h レート制限 · コンテキストバー (分母付き `/200k` `/1M`) · weekly レート制限 · extra-usage 実課金 · セッション経過 · セッションコスト |

> セッション名は Claude Code 2.1.76+ で右上に組み込み表示されるため、ステータスラインには含みません。
> 代わりに**セッションの出自**を黄で出します — `/branch` した会話は `branch`、`/fork` した複製は `fork`。
> `fork` が出ているときは親セッションが並走しています。Claude Code 2.1.221 以前は複製が親と同じ checkout で走るため、Line 3 の変更が自分のものとは限りません（2.1.222 で `/fork` は自前の worktree を作るようになり、この衝突は解消）。
> `branch` は transcript の `forkedFrom` で裏取りするので、元の会話に戻れば消えます（Claude Code は元セッションの名前にも `(Branch)` を書き込むため、名前だけでは見分けられません）。
> 端末幅による表示切替は行いません。すべての要素が常時フル表示されます。

### 表示例

```
Anthropic(enterprise)  Opus 5  high  think  fast  v2.1.222
~/dev/my-project  🌲my-feature  from:develop  (+2 dirs)
gh:acme/my-project  feature/x  approved  base:main  A3 M2 ?1 ↑2 1h fix: update logic..
⣶     16%  2:20  ⣿⣿⣄   48%/1M  week:9%  金 12:00  extra:$2.14  3h  $4.83
```

コンテキストバーの分母は使用率と同じ色で、`%` と一体で読めます (200k のモデルでは `48%/200k`)。

origin 未設定 / 非 GitHub remote (GitLab 等) では `gh:` 部分が省略され、Line 3 はブランチ名から始まります。
「まだ GitHub に上げてないリポ」がひと目でわかります。
`gh:` プレフィックスは dim、`owner/repo` は通常輝度です — ローカルのディレクトリ名と origin のリポジトリ名が食い違っていても、どこの repo かがここで判別できます。

worktree セッションで `<repo>/.claude/worktrees/<名前>` 配下にいる場合、パスはリポジトリ root までで切り、worktree 名を 🌲 の直後に表示します。
パス末尾がランダムな worktree 名で占領されず、リポジトリのディレクトリ名がパス末尾に残ります。
リンクはパス部分がリポ root、worktree 名部分が worktree ディレクトリを開きます。

```
~/scratch/local-repo
master  0m initial commit
```

プロバイダー別の表示:

```
Anthropic(enterprise)  Opus 5  ...                ← Anthropic直接 (サンドベージュ + サブスク種別)
Bedrock  global.anthropic.claude-opus-5-v1  ...   ← AWS Bedrock (ティールグリーン)
Vertex  Opus 5  ...                               ← Google Vertex AI (ブルー)
Foundry  Opus 5  ...                              ← Microsoft Foundry (Azureブルー)
```

## Installation

clone して、`~/.claude/settings.json` に 2 キー足すだけです。

```bash
git clone https://github.com/ist-j-ichikawa/claude-code-statusline.git ~/.claude/statusline
```

> **既に `~/.claude/settings.json` がある場合は、下の 2 キーを既存の JSON に**追加**してください。**
> ファイルごと置き換えると `env` / `permissions` / `hooks` などの既存設定を失います。
> マージが面倒なら、下の折りたたみの `install.sh` が既存キーを保ったまま追加し、バックアップも取ります。

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline/statusline-command.sh",
    "refreshInterval": 30,
    "hideVimModeIndicator": true
  },
  "subagentStatusLine": {
    "type": "command",
    "command": "~/.claude/statusline/subagent-statusline-command.sh"
  }
}
```

`command` はシェル経由で実行されるので `~` はそのまま使えます。
上の clone 先に合わせてあるので、書き換えずにコピーできます。

- `refreshInterval` — アイドル中もレート制限の残り時間や Git 状態を更新します (30 秒推奨)
- `hideVimModeIndicator` — vim mode は Line 1 先頭に自前描画するので、組み込みの `-- INSERT --` を抑止して二重表示を消します
- `subagentStatusLine` — agent panel の行を描きます。省略すれば Claude Code 既定の行のままです

スクリプトは実行ビット付きでコミットしてあるので `chmod` は不要です。`lib.sh` は両スクリプトが読む共有ライブラリで、同じディレクトリにある必要があります (clone すれば同梱されています)。

**更新は `git pull` だけ。** コピーを作らずリポジトリを直接参照するので、このリポジトリが single source of truth のままです。

> ただし **`settings.json` 側の推奨キーは `git pull` では増えません**。`refreshInterval` / `hideVimModeIndicator` / `subagentStatusLine` は後から推奨に加わったので、以前から使っている場合は欠けていることがあります。上の JSON と見比べて足してください。
> `./install.sh --dry-run` でも不足キーを差分で確認できます (何も書き込みません)。ただし手で貼った設定に対しては、`command` を `/bin/bash <絶対パス>` 形に書き換える差分も一緒に出ます — install.sh が使う形が違うだけで、不足キーではありません。

<details>
<summary>v1.52.0 より前から使っている場合</summary>

キャッシュの置き場が `/tmp/ist-j-ichikawa-claude-statusline` からユーザー単位の `$TMPDIR/claude-statusline-<uid>` に変わりました。
移行作業は不要で、初回だけ Git 情報が 5 秒遅れて出ます。
旧ディレクトリは macOS が定期的に掃除しますが、気になる場合は消せます:

```bash
rm -rf /tmp/ist-j-ichikawa-claude-statusline
```

</details>

<details>
<summary>settings.json を自分で触りたくない場合（install.sh）</summary>

`install.sh` が同じ登録を代わりに行います。clone 先はどこでも構いません。

```bash
git clone https://github.com/ist-j-ichikawa/claude-code-statusline.git
cd claude-code-statusline
./install.sh --dry-run   # まず何が変わるか差分で確認
./install.sh             # 差分を表示して y/N を聞いた上で書き込む
```

グローバル設定を触るので、**差分を見せて確認するまで一切書き込みません**。

- `statusLine` と `subagentStatusLine` を clone 先の絶対パスで登録します。clone 先がどこでも良い代わりに、上の手貼り例の `~/.claude/statusline/statusline-command.sh` ではなく **`/bin/bash /Users/…/statusline-command.sh` の形**で書き込みます (動作は同じです)。手貼り済みの設定に後から `install.sh` を流すと、この差が差分として出ます
- **既存の設定は保ったままマージ** — 他のキーはそのまま。`refreshInterval` / `hideVimModeIndicator` は未設定のときだけ推奨値を入れます
- **既存の `statusLine` が別のツールを指している場合は名指しで警告**してから確認を求めます
- 書き換え前に**タイムスタンプ付きバックアップ**を作成します (`settings.json.bak.20260727043008`)。固定名にしないので、2 回実行しても最初のバックアップが残ります
- `settings.json` が **symlink（dotfiles 管理）ならリンクを壊さず実体に書き込み**ます
- 登録前にスクリプトを試走し、動かなければ何も書かずに中止します
- 冪等 — 既に同じ内容なら「変更なし」で終了し、バックアップも作りません

| オプション | 用途 |
|---|---|
| `-n`, `--dry-run` | 変更内容を表示するだけで書き込まない |
| `-y`, `--yes` | 確認プロンプトを省略（非対話環境ではこれが必須） |
| `--main-only` | サブエージェント行は Claude Code 既定のままにする |
| `--uninstall` | 2 キーの登録を外す（他のキーは触らない） |
| `CLAUDE_SETTINGS=<path>` | 書き込み先の settings.json を差し替える |

`--uninstall` は clone を消した後（スクリプト本体が無くても）実行できるので、孤児になった設定の掃除に使えます。

</details>

<details>
<summary>git clone を残したくない場合</summary>

スクリプトを直接ダウンロードして配置できます。ただし**コピー**なので、更新は手動 (再ダウンロード) になります。
`lib.sh` は共有ライブラリで、スクリプトと同じディレクトリに必須です。

```bash
mkdir -p ~/.claude/statusline
base=https://raw.githubusercontent.com/ist-j-ichikawa/claude-code-statusline/main
for f in lib.sh statusline-command.sh subagent-statusline-command.sh; do
  curl -fsSL -o ~/.claude/statusline/$f "$base/$f"
done
chmod +x ~/.claude/statusline/*-command.sh
```

配置先が上と同じなので、settings.json は本文のものをそのまま使えます。

</details>

## サブエージェント行

`subagentStatusLine` は agent panel に並ぶサブエージェントの各行を、メインの statusline と協調した配色で描画します。
各行は **説明 + モデル(tier 色) + [effort] + [入力待ち等の状態] + [🌲worktree]** です（行頭の `❯ ◯` と「実行中」表示は Claude Code 側が描画）:

```
❯ ◯ review the diff for correctness bugs   Sonnet 5
❯ ◯ 大量ファイルの機械的な置換               Haiku 4.5  low
❯ ◯ /code-review xhigh                     Opus 5     xhigh   🌲issue-41
❯ ◯ 承認待ちのデプロイ                       Opus 5     needs_input
```

- **モデル**は Line 1 と同じ表記・tier 色（Bedrock の `jp.anthropic.claude-opus-5` 等も `Opus 5` に整形）
- **effort** は**そのエージェントだけ効力レベルが違う時にだけ**出ます（セッションの設定を継承している行では表示されません）
- **状態**は通常は出さず（実行中は Claude Code 標準の `○`/スピナーが示す）、`needs_input` など**注意が要る時だけ黄色い語**で表示
- **worktree** 隔離エージェントは作業先を `🌲名` で表示
- コンテキスト% と経過時間は**あえて出しません** — 並走するサブエージェントはどれも似た値になり（実測 5〜9% / 5〜6 分）、行が伸びるだけで判断に効きませんでした

## Recommended Terminal: Ghostty

[Ghostty](https://ghostty.org/) を推奨します。
Claude Code 公式の [terminal-config](https://code.claude.com/docs/en/terminal-config) でも紹介されており、本ステータスラインの全要件 (ANSI 256 色 + truecolor、OSC 8 ハイパーリンク、低レイテンシ描画) を満たします。

Claude Code 運用で特に便利な機能:

- **OSC 8 ハイパーリンク** — Line 2 のパス (`file://` で Finder/IDE へ) と Line 3 のブランチ名 (GitHub `tree/<branch>` へ) がクリック可能になる
- **[Shell Integration](https://ghostty.org/docs/features/shell-integration)** — bash/zsh/fish/elvish/nushell で自動セットアップ、新規ウィンドウが前の cwd を継承、`jump-to-prompt` で過去のプロンプト間をスキップ
- **Splits & Tabs** — `⌘D` / `⌘⇧D` で分割 (右 / 下)、`⌘T` で新規タブ。タブ名は最終実行コマンドで自動更新（複数 Claude Code を並走させる用途に最適）
- **Quick Terminal** — `toggle_quick_terminal` を任意のキーバインドに割り当てるとドロップダウン式の即時セッションが使える (デフォルトキーは未設定)
- **Config Hot-reload** — `⌘⇧,` で設定即時反映、ステータスラインのテーマ調整が高速
- **Metal GPU レンダリング** — `refreshInterval` (30s) ごとの再描画でもフリッカーなし
- **SGR 2 (faint) 対応** — 二次情報を弱めて出す表示（`base:`・`week:`・コミットメッセージ等）がそのまま効く。faint 未対応の端末ではこれらが通常輝度に潰れ、情報の階層が失われます

設定ファイル (macOS): `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`

> 他ターミナル (iTerm2, WezTerm, kitty, Alacritty 等) でも動作しますが、OSC 8 対応の差でクリック可能リンクが平文表示になる場合があります。

## 参考: フッターの GitHub リンクバッジ

**これはステータスラインの機能ではありません。** Claude Code 本体の `footerLinksRegexes` は会話テキストだけを対象にした別機能で、ステータスラインの出力には適用されません。相性がよいので、動作を確認した設定を参考として置いています。

会話に現れた GitHub の URL や `owner/repo#123` が、フッターのクリック可能なバッジになります。

<details>
<summary>設定（`~/.claude/settings.json` に追加）</summary>

```json
"footerLinksRegexes": [
  {
    "type": "regex",
    "pattern": "https://github\\.com/(?<owner>[A-Za-z0-9][\\w.-]*)/(?<repo>[A-Za-z0-9][\\w.-]*)/pull/(?<num>\\d+)",
    "url": "https://github.com/{owner}/{repo}/pull/{num}",
    "label": "PR #{num}"
  },
  {
    "type": "regex",
    "pattern": "https://github\\.com/(?<owner>[A-Za-z0-9][\\w.-]*)/(?<repo>[A-Za-z0-9][\\w.-]*)/issues/(?<num>\\d+)",
    "url": "https://github.com/{owner}/{repo}/issues/{num}",
    "label": "issue #{num}"
  },
  {
    "type": "regex",
    "pattern": "(?<![\\w./-])(?<owner>[A-Za-z0-9][\\w-]*)/(?<repo>[A-Za-z0-9][\\w.-]*)#(?<num>\\d+)\\b",
    "url": "https://github.com/{owner}/{repo}/issues/{num}",
    "label": "#{num}"
  }
]
```

パターンが 3 本に分かれている理由:

- `/pull/` と `/issues/` を `(?:issues|pull)` で 1 本にまとめると、遷移先を `/issues/{num}` に潰すことになり、`issue #5` と `PR #5` がどちらも同じラベルになります。URL 形式は文字列自体に種別が入っているので、分ければ判別できます
- 3 本目のベアな `owner/repo#123` は、issue か PR かを判別できません（正規表現は静的なので GitHub に問い合わせられない）。`/issues/{num}` に送って GitHub 側のリダイレクトに任せ、ラベルも曖昧な `#{num}` にしています
- 3 本目の先読み否定 `(?<![\w./-])` は、`src/utils/foo.ts#42` のようなコード中の参照を GitHub リンクと誤認しないためのものです（外すと誤マッチします）

使う前に知っておくとよいこと:

- **バッジは同時に 5 個まで**で、新しいマッチが古いものを押し出します。セッション自身が検出した PR は `prUrlTemplate` 経由で自動的に 1 個目のバッジになるため、その分だけ枠が減ります
- 設定は編集するとそのまま反映されます。**バッジが出てこないときは Claude Code を再起動**してください
- **user 設定でのみ有効**です。リポジトリの `.claude/settings.json` と `.claude/settings.local.json` では無視されます（Claude Code 2.1.221 のスキーマで確認）
- クリック可能になるのは OSC 8 対応端末（Ghostty 等）です。非対応端末ではラベルが平文で並びます

</details>

## 実装詳細

スクリプトの仕組み・構造・カラーテーマ・パフォーマンス最適化・Line 4 の内訳・クラウドプロバイダー検出ロジックは **[docs/internals.md](docs/internals.md)** にまとめています。

## Requirements

- **macOS 専用** — `stat -f %m` / `md5 -q -s` (BSD 版) に依存します
- [Claude Code](https://code.claude.com/) CLI
- `jq` (JSON parser)
- `curl` — `fetch_usage_spend()` のみ。extra-usage の実課金額取得に使い、OAuth トークンは argv に出さず stdin 経由で渡します。サブスクリプション種別の取得はネットワークを使わず Keychain 読みだけです
- `git` (Git 情報表示用)
- Bash 3.2+ (macOS 標準の `/bin/bash` で動作 — bash 4+ 機能は使いません)

## Development

テストは [bats](https://github.com/bats-core/bats-core) です。

```bash
brew install bats-core jq bash   # bash は 4+ が必要 (下記)
bats test.bats
```

**bats 自身は bash 4+ で起動してください。** テスト名が日本語なので、macOS 標準の bash 3.2 で起動すると bats 内部のテスト名エンコードがバイト単位に落ちてマルチバイト文字が割れ、**失敗ではなく 0 件実行**になります。0 件は流し読みでは「通った」に見えるため、`test.bats` 冒頭のガードが理由付きで落とします。

**一方スクリプト本体は `/bin/bash` (3.2) で起動します。** この分離は意図的で、テストがフルスクリプトを起動するときも `/bin/bash` を明示します — PATH の `bash` (homebrew 5.x) で起動すると、上記の bash 3.2 互換制約を一切検証しないテストになります。

表示の目視確認は fixture を流し込みます:

```bash
printf '%s' '{"model":{"display_name":"Opus 5"},"workspace":{"current_dir":"'"$PWD"'"}}' | ./statusline-command.sh
```

## License

[MIT](LICENSE)
