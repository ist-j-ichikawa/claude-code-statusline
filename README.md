# claude-code-statusline

Claude Code の statusline を 3 行で描く bash スクリプト 1 本。macOS 専用。

```
Anthropic(Max 20x)  Opus 5.5  high  v2.1.293
~/dev/claude-code-statusline  main
⣿⣿⣿   62%/1M  $24.31  cache 5m 05:47  5h:⣿⣿⣀   43% 06:13  Fable:⣿⣿⣤   51% Sat 16:00
```

| 行 | 出すもの |
|---|---|
| 1 | 課金先とプラン、モデル、reasoning effort、fast、Claude Code の版（追いついていれば薄く、遅れていれば赤） |
| 2 | パス、worktree 名、ブランチ、進行中の git 操作、conflicts、ahead/behind |
| 3 | コンテキスト消費、セッションの課金額、プロンプトキャッシュ（warm の間は TTL と切れる時刻 `cache 5m 05:47`、cold になったら TTL・原因・このセッションの miss 回数 `cold 5m tools_changed +2 -1 ×4`。キャッシュトークンを報告しないプロバイダでは出しません）、5h/週間/モデル別の枠（**90% を超えた枠は赤**） |

**出さないものの方が多いです。** 組み込みの UI が常時見せているもの（PR の状態、セッション名、vim モード、変更行数）は複製しません。スラッシュコマンドで見られるものも、**一過性**（窓が閉じたらコマンドでも見られない）か**決断のトリガー**（その数字が無いとコマンドを打つべきかも判断できない）のどちらかでなければ出しません。

## 入れる

```sh
git clone https://github.com/<owner>/claude-code-statusline.git ~/src/claude-code-statusline
```

`~/.claude/settings.json` に:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/bin/bash /Users/you/src/claude-code-statusline/statusline-command.sh",
    "refreshInterval": 30
  },
  "timeFormat": "24-hour"
}
```

- `refreshInterval` の単位は**秒**（最小 1）。30 で十分です — 本体が再描画を 300ms でデバウンスしており、1 描画は約 50ms なので余裕があります
- vim モードを使うなら `statusLine.hideVimModeIndicator` は**付けないでください**。このスクリプトは vim モードを出さないので、付けると組み込みの `-- INSERT --` まで消えます
- `timeFormat` は付けなくても動きます（既定の `auto` は locale 任せで、`en_US` 系では**本体が 12 時間・このスクリプトが 24 時間**になります）。`timeZone` と `12-hour` / `24-hour` / `24-hour-utc` には追従します

更新は `git pull` だけです。

### サブエージェントの行（任意）

プロンプトの下のエージェントパネルで、サブエージェントの行に**モデル名**・**reasoning effort**・**worktree 名**を足します。それ以外は Claude Code の既定の行と同じ並びです。effort はセッションと違う値を指定したときだけ出ます（継承したときは Claude Code が値を渡さないので）。worktree 名（`🌲fix-auth`）は、セッションと別の worktree で動いているサブエージェントだけに出ます。

```
既定:  ○ Explore  Find auth callers  3m · ↓ 12.4k tokens
これ:  ○ reviewer  Sonnet 5.5  low  🌲fix-auth  Find auth callers  3m · 12.4k tokens
```

```json
{
  "subagentStatusLine": {
    "type": "command",
    "command": "/bin/bash /Users/you/src/claude-code-statusline/statusline-command.sh --subagent"
  }
}
```

- 書き換えるのは**普通のサブエージェントの行だけ**です。チームメイト・ワークフロー・シェル・クラウドの行は既定のまま残ります
- 書き換えた行では、Claude Code がこのスクリプトに渡さない次の要素が消えます: 待機中の `waiting`、`N queued`、活動中かどうかの ↓/↑。エージェントの種類（`Explore` など）は Claude Code 2.1.293 以降なら既定どおり出ます（それより前の版では、名前を付けずに起動したエージェントの名前が空になります）
- 経過時間は実行中の行だけに出します（終わった行の終了時刻は渡されないので）

## 参考: フッターのリンクのバッジ

**ステータスラインの機能ではありません。** Claude Code 本体の `footerLinksRegexes` は、会話の出力（ツールの結果と Claude の返答）に正規表現を当てて、マッチしたものをプロンプトの下のバッジにする別の機能です。ステータスラインの出力には効きません。相性がよいので、実際に使っている設定を置いておきます。

```
PR #57  issue #12
```

`~/.claude/settings.json` に（project の `.claude/settings.json` に書いても読まれません）:

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

- **入れているのは GitHub の PR と issue の 2 種類だけ**です。直近 30 日の会話で、この 2 つが出現数と出たプロジェクト数の両方で上位でした
- **絞る理由はバッジが最大 5 個だからです。** 新しいマッチが古いものを押し出すので、パターンを増やすほど大事なバッジが追い出されます
- **Slack は入れていません。** 会話に出る Slack のリンクの大半は自分で貼ったもので、バッジの対象（ツールの結果と返答）になりません。逆に検索結果は 1 回で数十件のリンクを返すので、一度当たると 5 枠が全部埋まります
- PR と issue はパターンを分けています。1 本にまとめると、ラベルで `PR` と `issue` を書き分けられません
- **claude.ai の Artifact は入れていません。** 3 番目に多いリンクですが、そのセッションで公開したり開いたりした Artifact は、本体がフッターの右端に `⧉` 付きで出します。同じページのバッジが 2 つ並ぶだけでした
- 今のブランチの PR は、本体が自前のバッジで出します（`prStatusFooterEnabled`）

## 要るもの

`bash 3.2`（macOS 同梱の `/bin/bash`）、`jq`、`git`。1 描画で外に出るプロセスは **`jq` 1 個 + `git` 1 個**だけです。

プランとモデル別の週間枠は `stdin` に来ないので、Keychain と `/usage` から背景で取ってキャッシュします（`$TMPDIR` に 1 ファイル、TTL 300 秒、`mkdir -m 700`）。**Bedrock / Vertex / Foundry では取りません** — OAuth のアカウントは課金先と無関係で、出すと別アカウントの情報を見せることになります。`CLAUDE_STATUSLINE_NO_NET=1` で外への問い合わせを止められます。

## ダークテーマ前提です

白地では 1.0〜1.6:1 しか出ない色があります。

## 版

`2.x` はここで説明している 3 行の実装です。`1.x` は 5 行の別実装で、**2026-09-03 に `v1.90.0` で凍結**しました。v1 を使いたい場合はそのタグを checkout してください（`statusline-command.sh` と `lib.sh` の 2 本構成で、設定のパスは同じです）。

`2.0.0` は 1.x からの破壊的変更です。表示は 5 行から 3 行になり、`install.sh` と `subagentStatusLine` は無くなりました（`subagentStatusLine` は `2.6.0` で `--subagent` として戻りました）。

## ライセンス

MIT
