# claude-code-statusline

Claude Code の statusline を 3 行で描く bash スクリプト 1 本。macOS 専用。

```
Anthropic(Max 20x)  Opus 5  high  v2.1.273
~/dev/claude-code-statusline  main
⣿⣿⣿   62%/1M  $24.31  cold ttl_expired_5m  5h:⣿⣿⣀   43% 06:13  Fable:⣿⣿⣤   51% Sat 16:00
```

| 行 | 出すもの |
|---|---|
| 1 | 課金先とプラン、モデル、reasoning effort、fast、遅れている間だけ Claude Code の版 |
| 2 | パス、worktree 名、ブランチ、進行中の git 操作、conflicts、ahead/behind |
| 3 | コンテキスト消費、セッションの課金額、プロンプトキャッシュが cold の瞬間（キャッシュトークンを報告しないプロバイダでは出しません）、5h/週間/モデル別の枠（**90% を超えた枠は赤**） |

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
  "hideVimModeIndicator": true,
  "timeFormat": "24-hour"
}
```

- `refreshInterval` の単位は**秒**（最小 1）。30 で十分です — 本体が再描画を 300ms でデバウンスしており、1 描画は約 50ms なので余裕があります
- `hideVimModeIndicator` は組み込みの vim 表示を消すためではなく、**このスクリプトが vim モードを出さない**ので二重表示の心配が要らない、という確認用です。付けなくても動きます
- `timeFormat` は付けなくても動きます（既定の `auto` は locale 任せで、`en_US` 系では**本体が 12 時間・このスクリプトが 24 時間**になります）。`timeZone` と `12-hour` / `24-hour` / `24-hour-utc` には追従します

更新は `git pull` だけです。

## 要るもの

`bash 3.2`（macOS 同梱の `/bin/bash`）、`jq`、`git`。1 描画で外に出るプロセスは **`jq` 1 個 + `git` 1 個**だけです。

プランとモデル別の週間枠は `stdin` に来ないので、Keychain と `/usage` から背景で取ってキャッシュします（`$TMPDIR` に 1 ファイル、TTL 300 秒、`mkdir -m 700`）。**Bedrock / Vertex / Foundry では取りません** — OAuth のアカウントは課金先と無関係で、出すと別アカウントの情報を見せることになります。`CLAUDE_STATUSLINE_NO_NET=1` で外への問い合わせを止められます。

## ダークテーマ前提です

白地では 1.0〜1.6:1 しか出ない色があります。

## 版

`2.x` はここで説明している 3 行の実装です。`1.x` は 5 行の別実装で、**2026-09-03 に `v1.90.0` で凍結**しました。v1 を使いたい場合はそのタグを checkout してください（`statusline-command.sh` と `lib.sh` の 2 本構成で、設定のパスは同じです）。

`2.0.0` は 1.x からの破壊的変更です。表示は 5 行から 3 行になり、`install.sh` と `subagentStatusLine` は無くなりました。

## ライセンス

MIT
