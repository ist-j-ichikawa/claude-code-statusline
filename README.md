# Claude Code Statusline

j-ichikawa's custom statusline for [Claude Code](https://code.claude.com/) CLI.

![Version](https://img.shields.io/badge/version-1.89.0-blue)
![Built against](https://img.shields.io/badge/Claude_Code-2.1.258-purple)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)

## Overview

Claude Code の各アシスタント応答後に表示されるカスタムステータスラインです。
セッション情報、Git 状態、コンテキスト使用量、コスト等をリアルタイムに表示します。

> **ダークテーマの端末を推奨します。** 色は暗い背景でのコントラストを基準に選んでいるため、明るい背景では一部の要素 (コンテキストの緑・実課金の金・output style の白・think・fast) が読めません (白地に対して 1.0〜1.6:1 の実測)。ライトテーマ用の配色は用意していません。

### 表示レイアウト

| 行 | 内容 |
|---|---|
| **Line 1** | vim mode · プロバイダー · Model · effort · think · fast · output style · Agent 名 · 宛名 · `branch:`元セッション id / `fork` · Version |
| **Line 2** | ディレクトリパス · 🌲worktree 名 · `from:`元ブランチ · `(+N dirs)` |
| **Line 3** | 進行中の git 操作 (`rebase 2/5` 等) · `gh:`/`gl:`owner/repo · ブランチ (OSC 8 → GitHub / GitLab tree) · PR review_state · 変更行数 (`+42 -17`) · ahead/behind · last commit (`08-17T13:13`) |
| **Line 4** | コンテキストバー (分母付き `/200k` `/1M`) · セッション経過 · セッションコスト · プロンプトキャッシュ (`prompt_cache:warm` / `cold` と `hit_ratio:N%`) — **このセッション** |
| **Line 5** | 5h レート制限 · weekly レート制限 · モデル別 weekly 制限 (`Fable:39%`) · usage-credits 実課金 — **アカウント** |

> セッション名は Claude Code 2.1.76+ で右上に組み込み表示されるため、ステータスラインには含みません。

> 代わりに**セッションの出自**を黄で出します — `/branch` した会話は `branch`、`/fork` した複製は `fork`。
> `fork` が出ているときは親セッションが並走しています。Claude Code 2.1.221 以前は複製が親と同じ checkout で走るため、Line 3 の変更が自分のものとは限りません（2.1.222 で `/fork` は自前の worktree を作るようになり、この衝突は解消）。
> `branch` は transcript の `forkedFrom` で裏取りするので、元の会話に戻れば消えます（Claude Code は元セッションの名前にも `(Branch)` を書き込むため、名前だけでは見分けられません）。
> `branch` には**元セッションの id を添えます**。`/branch` の元は別の端末で resume されるので、この id をコピーして `claude --resume <id>` で戻れます（元の transcript が残っている場合。古い分岐では元が既に消えていることがあります）。裏取りに使う `forkedFrom` がその id を持っているので、追加のコストはかかりません。
> id は切り詰めず全体を出します — `--resume` は先頭 8 桁のような短縮形を受け付けない（`is not a UUID` で弾かれる）ので、短くするとコピーしても戻れません。
> `fork` には添えません。`/fork` の元は同じ端末に残り、`←` の detach で戻れるためです。
> 端末幅による表示切替は行いません。すべての要素が常時フル表示されます。

> Version は通常グレーですが、**最新版から遅れているときだけ赤く**なります。最新版は Claude Code 自身が置いている changelog キャッシュから読むので、ネットワーク取得はしません (キャッシュが読めなければグレーのままです)。

`my-project-41` は**このセッション自身の宛名**です。これをコピーして別のセッションに渡せば、そちらからこのセッションへメッセージを送れます。記号を付けずに置いているので、`my-project-41` のように空白を含まない名前ならダブルクリックだけで選択できます（背景セッションのように空白を含む名前になる場合は範囲選択してください）。

この名前はどこにも表示されていません。右上に出る名前は会話の内容から付きますが、宛名は作業ディレクトリ名から別に作られるので、両者は食い違います（内容が「v2について」でも宛名は `my-project-b6` のまま）。セッション id も宛名には使えません。同じリポジトリで複数のセッションを開くと末尾 2 文字だけが違う宛名（`my-project-41` と `my-project-5c`）になるため、並んでいる端末を見分けるにはこの表示が要ります。resume すると末尾が変わるので、メモして後から使うものではありません。

**セッションの種類によらず常に出します**（背景セッションや `/branch` では名前の作られ方が変わりますが、どれもそれが送信先です）。読めなくなったときは宛名だけが消え、他の表示はそのまま残ります。`CLAUDE_CONFIG_DIR` で設定ディレクトリを切り替えている場合も、そちらから読みます。

> 取得元は Claude Code の内部ファイルです。ステータスラインが受け取る JSON にも `session_name` が来ますが、そちらは**右上に出る表示名**（`/rename` で付けた名前、なければ AI が付けたタイトル）で宛名ではありません（Claude Code 2.1.258 の実装で確認）。出す理由・却下した表記・誤情報の経路は [docs/internals.md](docs/internals.md) の「宛名」節にまとめています。

### 表示例

```
Anthropic(Max 20x)  Opus 5  high  think  fast  default  my-project-41  v2.1.258
~/dev/my-project  🌲my-feature  from:develop  (+2 dirs)
gh:acme/  feature/x  approved  +42 -17 ↑2 08-17T13:13 fix: update logic..
⣿⣶   60%/1M  3h  $4.83  prompt_cache:warm hit_ratio:91%
⣶     16%  19:31  week:9%  金 12:00  Fable:39%  土 16:00  credits:$2.14
```

Line 3 の `gh:acme/` が owner だけなのは、repo 名 (`my-project`) が Line 2 のパス末尾に既に出ているためです (下の表を参照)。

`default` は output style です (常に出ます。既定なので弱め表示で、変更していれば白く出ます)。

コンテキストバーの分母は使用率と同じ色で、`%` と一体で読めます (200k のモデルでは `48%/200k`)。

時刻はすべて**同じタイムゾーン・同じ書式**で表示します。例外が無いのでゾーン名は表示していません。

Claude Code 2.1.257 以降は `settings.json` の **`timeFormat`** と **`timeZone`** に追従します（`/config` の Time format で選んだものがそのまま反映されます）。本体の時計と表記がずれないようにするためだけの機能です。

| 設定 | 5h リセット | 週間リセット |
|---|---|---|
| 未設定 / `auto` | `19:31` | `土 16:00` |
| `"12-hour"` | `7:31 PM` | `土 7:31 PM` |
| `"24-hour"` | `19:31` | `土 16:00` |
| `"24-hour-utc"` | `10:31Z` | `土 07:00Z` |
| `"%H時%M分"`（strftime パターン） | `19時31分` | `土 19時31分` |
| `"timeZone": "Europe/Dublin"` | そのゾーンの時刻 | 同じ |

- **`auto` は locale まで追いません** — 24 時間表記の locale では上の「未設定」と同じ表示です。12 時間表記の locale で本体が `7:31 PM` を出す場合は、`timeFormat` に `"12-hour"` を明示してください
- **`"24-hour-utc"` は `timeZone` より優先されます**（Claude Code 本体と同じ挙動）
- 上の表の `PM` は英語ロケールでの例です。`%p` は端末の `LC_TIME` に従うので、日本語ロケールなら `7:31 午後` になります
- 読むのは**ユーザー設定** (`~/.claude/settings.json`) だけです。プロジェクト側の `.claude/settings.json` に書いた場合は反映されず、従来どおりローカルの 24 時間表記になります
- 不正なタイムゾーン名は無視してこのマシンのゾーンに戻します（本体と同じ挙動）

### 変更の表示

Line 3 の変更表示は **Claude Desktop の code 画面と同じ単位と色**です。ファイル数ではなく**行数**で、追加が緑・削除が赤。

> 配色は**ダークテーマの端末を前提**にしています。

| 記号 | 意味 | 色 | 単位 |
|---|---|---|---|
| `+42` | 追加された行 | 緑 (GitHub の diff 色に合わせた 256 色。端末テーマに左右されません) | 行 |
| `-17` | 削除された行 | 赤 (同上) | 行 |
| `!2` | コンフリクト中のファイル | 赤 (**注意を促す赤**。行数の赤とは別の色) | ファイル |
| `↑2` | origin より進んでいるコミット | 緑 (行数と同じ) | コミット |
| `↓1` | origin より遅れているコミット | 赤 (行数と同じ) | コミット |

行数に畳まれるもの:

| 状態 | 扱い |
|---|---|
| ステージ済み / 未ステージ | **合算**して `+` `-` に出る（Claude Desktop のワーキングツリー表示と同じ範囲） |
| 未追跡ファイル | 全行を**追加として** `+` に畳む（Claude Desktop も未追跡を「追加」として扱います） |
| リネーム | 移動に伴う差分が `+` `-` に出る |
| 削除 | `-` に出る |
| バイナリ | 行数を持たないので**数えません** |

`+0` `-0` は出しません。追加だけの作業では `+42` だけが出ます。

コンフリクトの `!` は Claude Desktop に対応する表示が無いため独自に決めた記号です（`+` `-` と同じ ASCII の 1 桁なので、どの端末でも桁が揃います）。マージ中は最優先の情報なので、行数とは独立して出しています。

GitHub は `gh:`、GitLab は `gl:` を付け、ブランチはそれぞれの tree ページへリンクします。
origin 未設定、またはこの 2 つ以外のホストでは略号ごと省略され、Line 3 はブランチ名から始まります。

```
~/scratch/local-repo
master  09-02T14:46 initial commit
```

**略号 (`gh:` / `gl:`) は Line 2 のパスと重複した成分だけを削ります** — 同じ文字列が 2 行に並ばないようにするためです。

| Line 2 のパス末尾 | Line 3 の表示 |
|---|---|
| `owner/repo` と一致 (ghq 等) | 略号ごと出さない |
| repo 名だけ一致 (`~/dev/<repo>` 等) | `gh:owner/` に畳む (末尾の `/` は「続きは上の行」の意) |
| 不一致 | `gh:owner/repo` を全部出す |

「まだ GitHub に上げてないリポ」がひと目でわかります。
略号のプレフィックスは dim、`owner/repo` は通常輝度です — ローカルのディレクトリ名と origin のリポジトリ名が食い違っていても、どこの repo かがここで判別できます (一致していれば上のとおり省略されるので、**出ているときは必ず何か違う**ということです)。

worktree セッションで `<repo>/.claude/worktrees/<名前>` 配下にいる場合、パスはリポジトリ root までで切り、worktree 名を 🌲 の直後に表示します。
パス末尾がランダムな worktree 名で占領されず、リポジトリのディレクトリ名がパス末尾に残ります。
リンクはパス部分がリポ root、worktree 名部分が worktree ディレクトリを開きます。

プロバイダー別の表示:

```
Anthropic(Max 20x)  Opus 5  ...                ← Anthropic直接 (サンドベージュ + プラン名/レート枠)
Bedrock  global.anthropic.claude-opus-5-v1  ...   ← AWS Bedrock (ティールグリーン)
Vertex  Opus 5  ...                               ← Google Vertex AI (ブルー)
Foundry  Opus 5  ...                              ← Microsoft Foundry (Azureブルー)
```

## Installation

clone して、`~/.claude/settings.json` に 2 キー足すだけです（`CLAUDE_CONFIG_DIR` を設定している場合はそちらの `settings.json`）。

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

**あわせて `timeFormat` の設定をおすすめします**（`statusLine` の中ではなく **top-level**。Claude Code 2.1.257 以降）。

```json
{
  "timeFormat": "24-hour"
}
```

ステータスラインのリセット時刻は 24 時間表記（`19:31`）です。一方 Claude Code 本体の時計は既定が `"auto"` = **端末の locale 任せ**で、`LANG=en_US.UTF-8` のような環境では `7:31 PM` になります。つまり**何も設定しないと同じ画面に 12 時間表記と 24 時間表記が並びます**（en 系 locale では既定でこうなります）。`"24-hour"` を入れると本体がステータスラインに合わせるので、ステータスラインの表示は 1 文字も変わりません。

12 時間表記が好みなら `"12-hour"` でも揃います（その場合はステータスライン側が `7:31 PM` に追従します。Line 5 が 3 文字ほど伸びます）。**`install.sh` はこのキーを書きません** — 時刻の好みは人によるので、`refreshInterval` / `hideVimModeIndicator`（どちらも二重表示や更新漏れという不具合の回避）とは性質が違うと判断しました。

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

### 動作確認

fixture を流し込むと、Claude Code を再起動する前に描画を確かめられます。**clone したディレクトリで実行してください** — `install.sh` を使った場合は clone 先がどこでも構わないので、`~/.claude/statusline` とは限りません。

```bash
cd ~/.claude/statusline   # 別の場所に clone した場合はそのディレクトリ
printf '%s' '{"model":{"display_name":"Opus 5"},"workspace":{"current_dir":"'"$PWD"'"}}' | ./statusline-command.sh
```

色付きの行が出れば成功です。`jq` が足りない場合もここで分かります。
clone 先は Git リポジトリなので、ブランチ名を含む行まで出ます。

> **`bats test.bats` を実行する必要はありません。** テストはこのリポジトリに手を入れる人向けで、bats と bash 4+ の追加インストールが必要です。インストールできたかどうかは上の 1 行で確認できます。

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
- **説明文に制御文字が混ざっても行は崩れません** — タブ・改行に加えてエスケープ文字も空白に置き換えるので、エージェントの説明から色を差し込まれることもありません
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
- **SGR 2 (faint) 対応** — 二次情報を弱めて出す表示（`from:`・`week:`・コミットメッセージ等）がそのまま効く。faint 未対応の端末ではこれらが通常輝度に潰れ、情報の階層が失われます

設定ファイル (macOS): `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`

> 他ターミナル (iTerm2, WezTerm, kitty, Alacritty 等) でも動作しますが、OSC 8 対応の差でクリック可能リンクが平文表示になる場合があります。

## 参考: フッターの GitHub リンクバッジ

**これはステータスラインの機能ではありません。** Claude Code 本体の `footerLinksRegexes` は会話の出力（アシスタントの応答とツール結果）だけを対象にした別機能で、ステータスラインの出力には適用されません。相性がよいので、実際に使っている設定を参考として置いています。

会話に現れた GitHub の URL や `owner/repo#123` が、フッターのクリック可能なバッジになります。

<details>
<summary>設定（`~/.claude/settings.json` に追加）</summary>

```json
"footerLinksRegexes": [
  {
    "type": "regex",
    "pattern": "https://github\\.com/(?<owner>[A-Za-z0-9][A-Za-z0-9-]*)/(?<repo>[\\w.-]+)/pull/(?<num>\\d+)",
    "url": "https://github.com/{owner}/{repo}/pull/{num}",
    "label": "PR #{num}"
  },
  {
    "type": "regex",
    "pattern": "https://github\\.com/(?<owner>[A-Za-z0-9][A-Za-z0-9-]*)/(?<repo>[\\w.-]+)/issues/(?<num>\\d+)",
    "url": "https://github.com/{owner}/{repo}/issues/{num}",
    "label": "issue #{num}"
  },
  {
    "type": "regex",
    "pattern": "https://github\\.com/(?<owner>[A-Za-z0-9][A-Za-z0-9-]*)/(?<repo>[\\w.-]+)/releases/tag/(?<tag>[\\w.+-]*\\w)",
    "url": "https://github.com/{owner}/{repo}/releases/tag/{tag}",
    "label": "release {tag}"
  },
  {
    "type": "regex",
    "pattern": "(?<![\\w./-])(?<owner>[A-Za-z0-9][A-Za-z0-9-]*)/(?<repo>[\\w.-]+)#(?<num>\\d+)\\b",
    "url": "https://github.com/{owner}/{repo}/issues/{num}",
    "label": "#{num}"
  }
]
```

パターンを 4 本に分けている理由:

- **`/pull/` と `/issues/` を分けるのはラベルのため。** `(?:issues|pull)` で 1 本にまとめても、その部分を名前付きグループ（`(?<kind>issues|pull)`）にして URL テンプレートに埋めれば遷移先は保てます。ただしラベルにも同じ値しか入れられないので `issues #5` になり、`issue #5` と `PR #5` の書き分けができません。**パターンの本数はバッジ枠を消費しません**（枠を使うのはマッチした結果だけ）
- **ベアな `owner/repo#123` は issue か PR かを判別できません**（正規表現は静的なので GitHub に問い合わせられない）。GitHub では PR も issue 番号を共有するので `/issues/{num}` に送り、PR なら GitHub 側の転送に任せます。ラベルも曖昧な `#{num}` のままにしています
- **`releases/tag/` を足しました** — 出荷のたびに貼られる URL なので、`release v1.89.0` のバッジになると押しやすいためです。tag の末尾を `[\w.+-]*\w` にしているのは、文末の句点まで取り込まないため（`…/tag/v1.89.0.` → `v1.89.0`）
- **先読み否定 `(?<![\w./-])`** は、`src/utils/foo.ts#42` のようなコード中の参照を GitHub リンクと誤認しないためのものです（外すと誤マッチします）
- **owner は `[A-Za-z0-9-]` だけ、repo は `[\w.-]`** と非対称にしています。GitHub のアカウント名は英数字とハイフンだけなので owner を絞ると誤マッチが減り、逆にリポジトリ名は `.github` や `_priv` のように記号で始まれるので repo 側は緩める必要があります（repo にも「英数字で始まること」を要求していた頃は `org/.github#5` を拾えませんでした）

使う前に知っておくとよいこと（Claude Code 2.1.258 の実装で確認）:

- **バッジは同時に 5 個まで**で、新しいマッチが古いものを押し出します。セッション自身が検出した PR は `prUrlTemplate` 経由で自動的に 1 個目のバッジになるため、実質 4 枠です。`/clear` で消えます
- **同じ URL は 1 個に畳まれます。** 逆に、同じ issue でもベア参照（`owner/repo#2` → `/issues/2`）と PR の URL（`/pull/2`）は別 URL なので 2 個並びます
- **走査されるのは直前のユーザー入力より後の出力だけ**です。1 つのツール結果からは**末尾 8 KB**、全体では**末尾 64 KB**・**256 メッセージ**までしか見ないので、長い `git log` の先頭に出た URL は拾われません
- **ラベルは 28 文字で切られます**（`{repo}#{num}` のように長い値を入れると省略されます）
- 設定は編集するとそのまま反映されます。**バッジが出てこないときは Claude Code を再起動**してください
- **user 設定（と `--settings` / 管理ポリシー）でのみ有効**です。リポジトリの `.claude/settings.json` と `.claude/settings.local.json` では無視されます
- URL テンプレートは**リテラルのオリジンを持つ URL でなければ無視されます**。置換の結果オリジンが変わるものや、パスに `..` を含むものも捨てられます（誤誘導の防止）
- クリック可能になるのは OSC 8 対応端末（Ghostty 等）です。非対応端末ではラベルが平文で並びます

</details>

## 実装詳細

スクリプトの仕組み・構造・カラーテーマ・パフォーマンス最適化・Line 4 の内訳・クラウドプロバイダー検出ロジックは **[docs/internals.md](docs/internals.md)** にまとめています。

## Requirements

- **macOS 専用** — `stat -f %m` / `md5 -q -s` (BSD 版) に依存します
- **ダークテーマの端末推奨** — 配色を暗い背景基準で選んでいます (上記)
- [Claude Code](https://code.claude.com/) CLI
- `jq` (JSON parser)
- `curl` — `fetch_usage_spend()` のみ。usage-credits の実課金額取得に使い、OAuth トークンは argv に出さず stdin 経由で渡します。サブスクリプション種別の取得はネットワークを使わず Keychain 読みだけです
- `git` (Git 情報表示用)
- Bash 3.2+ (macOS 標準の `/bin/bash` で動作 — bash 4+ 機能は使いません)

## Development

> **ここから下はこのリポジトリに手を入れる人向けです。** statusline を使うだけなら不要で、bats や bash 4+ のインストールも要りません。インストールの確認は [動作確認](#動作確認) の 1 行で足ります。

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
