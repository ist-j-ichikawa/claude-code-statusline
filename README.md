# claude-code-statusline

Claude Code の statusline を 3 行で描く bash スクリプト 1 本です。macOS 専用です。

![3 行の statusline](https://github.com/user-attachments/assets/0e2a6e08-c757-4d29-ad65-d11a8e8d5e88)

| 行 | 出すもの |
|---|---|
| 1 | 課金先とプラン、モデル、reasoning effort、fast、Claude Code の版（追いついていれば薄く、遅れていれば赤） |
| 2 | パス、worktree 名、ブランチ、進行中の git 操作、conflicts、ahead/behind |
| 3 | コンテキストの消費、セッションの課金額、プロンプトキャッシュ（warm の間は TTL と切れる時刻、cold になったら原因と miss 回数）、5h・週間・モデル別の枠（**90% を超えた枠は赤**） |

**出さないものの方が多いです。** Claude Code が画面に常に出しているもの（PR の状態、セッション名、vim モード、変更行数）は重ねて出しません。スラッシュコマンドで見られるものも、窓が閉じたら見られなくなるものか、その数字が無いとコマンドを打つべきかも判断できないもの以外は出しません。

サブエージェントの行にも、モデル名・effort・worktree を足せます（[下](#サブエージェントの行)）。

## インストール

### Claude Code に頼む

Claude Code に次の 1 文を貼れば、下の「手順」どおりに入れてくれます。

```
https://github.com/ist-j-ichikawa/claude-code-statusline の README の「手順」に従って、この statusline をインストールして。~/.claude/settings.json のほかの設定は消さないで、最後に「確かめる」のコマンドで 3 行出ることを見せて。
```

### 手順

上から順に実行します。何度実行しても同じ結果になります。

**1. 要るものを確かめる**（macOS、`/bin/bash`、`jq`、`git`）

```sh
uname -s            # Darwin
command -v jq git   # 2 行とも出れば OK。jq が無ければ brew install jq
```

**2. 取ってくる**

```sh
git clone https://github.com/ist-j-ichikawa/claude-code-statusline.git ~/src/claude-code-statusline
```

別の場所に置いた場合は、下の `~/src/claude-code-statusline` を読み替えてください。

**3. settings に足す**（ほかの設定は残したまま、`statusLine` と `subagentStatusLine` だけを書き込みます。元のファイルは `.bak` に残ります）

```sh
f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
d="$HOME/src/claude-code-statusline"
[ -f "$f" ] || echo '{}' > "$f"
cp "$f" "$f.bak"
jq --arg d "$d" '
  .statusLine = {"type": "command", "command": ("/bin/bash " + $d + "/statusline-command.sh"), "refreshInterval": 30}
  | .subagentStatusLine = {"type": "command", "command": ("/bin/bash " + $d + "/statusline-command.sh --subagent")}
' "$f.bak" > "$f"
```

**4. 確かめる**

```sh
printf '%s' '{"model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},"workspace":{"current_dir":"'"$PWD"'"},"context_window":{"used_percentage":42,"context_window_size":1000000}}' \
  | /bin/bash ~/src/claude-code-statusline/statusline-command.sh
```

モデル名・パス・コンテキストの行が出れば入っています。Claude Code は次の描画から新しい statusline を使います（再起動は要りません）。

### 更新・元に戻す

- **更新**: `git -C ~/src/claude-code-statusline pull`（settings は触りません）
- **元に戻す**: settings から `statusLine` と `subagentStatusLine` を消します

  ```sh
  f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  jq 'del(.statusLine, .subagentStatusLine)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  ```

### おすすめの設定

- **`"timeFormat": "24-hour"`** をトップレベルに足すと、Claude Code 本体とこの statusline の時刻表記が揃います。既定の `auto` は locale 任せで、`en_US` 系では本体が 12 時間・この statusline が 24 時間になります。`timeZone` と `12-hour` / `24-hour` / `24-hour-utc` には追従します
- `refreshInterval` の単位は**秒**です。30 で十分です（1 回の描画は約 50ms）
- vim モードを使うなら、`statusLine.hideVimModeIndicator` は**付けないでください**。この statusline は vim モードを出さないので、付けると組み込みの `-- INSERT --` まで消えます
- **ダークテーマ前提**です。白地では読みにくい色があります

## サブエージェントの行

プロンプトの下のエージェントパネルで、サブエージェントの行に**モデル名**・**effort**・**worktree** を足します。並びは Claude Code の既定の行と同じです。

![既定の行と、--subagent の行の比較](https://github.com/user-attachments/assets/b78caf9b-7a1a-4e49-8f9f-2aae0869eee4)

- **モデル名**は 1 行目と同じ色で出ます。サブエージェントをどのモデルで走らせているかが一目で分かります
- **effort** は、セッションと違う値を指定したときだけ出ます（継承したときは Claude Code が値を渡さないため）
- **`🌲`** は、セッションと別の worktree で動いているときだけ出ます。自分で付けた worktree 名（`🌲fix-auth`）は名前ごと、`isolation: worktree` で隔離したサブエージェント（名前が ID）は `🌲` だけです
- 書き換えるのは普通のサブエージェントの行だけです。チームメイト・ワークフロー・シェル・クラウドの行は既定のまま残ります
- 書き換えた行では、Claude Code がスクリプトに渡さない `waiting`・`N queued`・活動中かどうかの ↓/↑ が消えます。経過時間は実行中の行だけに出ます

「手順」の 3 で一緒に入ります。要らなければ `subagentStatusLine` を消してください。

## 何を読み、どこと通信するか

- **stdin**: Claude Code が渡すセッションの JSON（モデル、パス、コンテキスト、課金額、枠など）
- **git**: 2 行目のために、カレントのリポジトリで `git status` を 1 回走らせます（optional locks は取りません）
- **Keychain と `/usage`**: プラン名とモデル別の週間枠は stdin に来ないので、Claude Code が Keychain に保存した OAuth トークンを読み、`https://api.anthropic.com/api/oauth/usage` に問い合わせます。トークンはコマンドラインに出さず、標準入力で curl に渡します。**問い合わせるのはこの 1 か所だけ**で、背景で走るので描画は待ちません
- **キャッシュ**: 結果は `$TMPDIR/claude-statusline-v2-<UID>/` に 1 ファイル置きます（持ち主だけが読める `700`、5 分ごとに取り直し）
- **Bedrock / Vertex / Foundry では Keychain も `/usage` も触りません**（OAuth のアカウントは課金先と関係ないため）
- `CLAUDE_STATUSLINE_NO_NET=1` を環境変数に入れると、外への問い合わせを止められます（キャッシュは読みます）

1 回の描画で外に起動するプロセスは `jq` 1 個と `git` 1 個です。

## 参考: フッターのリンクのバッジ

**これは statusline の機能ではありません。** Claude Code 本体の `footerLinksRegexes` は、会話の出力（ツールの結果と Claude の返答）に正規表現を当てて、マッチしたものをプロンプトの下のバッジにする別の機能です。相性がよいので、実際に使っている設定を置いておきます。

```
PR #57  issue #12
```

`~/.claude/settings.json` に足します（project の `.claude/settings.json` に書いても読まれません）。

```json
{
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
    }
  ]
}
```

- 入れているのは GitHub の PR と issue の 2 種類だけです。バッジは最大 5 個で、新しいマッチが古いものを押し出すので、増やすほど大事なバッジが消えます
- Slack は入れていません。会話に出る Slack のリンクの大半は自分で貼ったもので、バッジの対象になりません。逆に検索結果は 1 回で数十件のリンクを返すので、5 枠が埋まります
- claude.ai の Artifact も入れていません。そのセッションで開いた Artifact は、本体がフッターの右端に `⧉` 付きで出します
- 今のブランチの PR は、本体が自前のバッジで出します

## 版

`2.x` がこの README の 3 行の実装です。`1.x` は 5 行の別実装で、`v1.90.0` で凍結しました（使うならそのタグを checkout してください）。変更点は [CHANGELOG.md](CHANGELOG.md) にあります。

## ライセンス

MIT
