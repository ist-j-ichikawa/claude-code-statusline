# 実装詳細

`statusline-command.sh` の内部構造・カラーテーマ・パフォーマンス最適化・プロバイダー検出ロジックの詳細。利用者向けの導入手順は [README](../README.md) を参照。

## 仕組み

Claude Code はアシスタントの応答ごとに（300ms デバウンス付きで）このスクリプトを呼び出します。セッション情報は JSON で **stdin** に渡され、`printf` の出力がそのままステータスラインの各行になります。ANSI カラーと OSC 8 ハイパーリンクに対応しています。

## 入力 JSON フィールド

stdin で受け取るフィールドの一覧は公式ドキュメントを参照:
[Available data — Claude Code Statusline](https://code.claude.com/docs/en/statusline#available-data)

## スクリプト構造

```
statusline-command.sh
├── Constants        ANSI色定数、キャッシュ設定、_NOW タイムスタンプ
├── Helpers          has_val(), cache_stale(), braille_bar(pct), etc.
├── Subscription     fetch_subscription() — Keychain からサブスクリプション種別を取得（バックグラウンドキャッシュ）
├── JSON extraction  単一の jq 呼び出しで全フィールドを抽出
├── Git info         build_git() — ブランチ、dirty state、ahead/behind、last commit (age + msg)（5秒バックグラウンドキャッシュ、atomic mv 書き込み）
├── Line 1           [vim mode バッジ (INSERT=ライムグリーン bg / VISUAL・V-LINE=ゴールド bg、NORMAL は非表示)] + プロバイダー + モデル名（Fable=多色(蝶標本), Opus=コーラル, Sonnet 5=緑グラデーション, Sonnet 4.6=ティール, Sonnet 4.5=アンバー, Haiku=ラベンダー）+ effort（light purple）+ think（light cyan）+ Agent + Version + branch
├── Line 2           ディレクトリパス (OSC 8 リンク) + 🌲worktree名 + from:branch + added_dirs (+N dirs)。`<repo>/.claude/worktrees/<name>` 配下はリポ root と 🌲<name> (dim) に分割表示（リンクは root / worktree 各 dir へ。サブディレクトリ滞在時・既定外配置ではフルパスに fallback）。from:HEAD (detached から作成) も表示する
├── Line 3           Git ([gh: (dim) + owner/repo (通常輝度)、GitHub origin あり時のみ] + ブランチ [OSC 8 リンク → GitHub tree] + PR review_state (Claude Code 2.1.145+ pr.review_state、テキスト色分け、PR # は Claude Code 組み込み footer に任せて非表示) + base:親ブランチ (reflog) + dirty state + ahead/behind + last commit)、非git時は "no git"
├── Line 4           5hレート制限 + コンテキストバー + weeklyレート制限 (Anthropic のみ) + extra-usage実課金 ($、gold、Anthropic のみ) + セッションコスト ($、dim)
└── Output           printf で各行を出力
```

## カラーテーマ

| 指標 | 色 | ANSIコード |
|---|---|---|
| vim mode `INSERT` | 黒文字 / ライムグリーン bg (bold) | 1;30;48;5;148 |
| vim mode `VISUAL` / `V-LINE` | 黒文字 / ゴールド bg (bold) | 1;30;48;5;214 |
| コンテキスト使用率 | < 80% lime green / 80-89% 黄 / >= 90% 赤 | 38;5;82 / 33 / 31 |
| Fable | 多色・蝶標本 (文字ごとに循環) | `rainbow()` 178/172/130/167/143/107/66 |
| Opus | コーラル (artwork実測) | 38;5;173 |
| Sonnet 5 | 緑グラデーション (文字ごとにスイープ) | `gradient()` 28→154 |
| Sonnet 4.6 | ティール | 38;5;79 |
| Sonnet 4.5 / 3.5 | アンバー | 38;5;214 |
| Haiku | ラベンダー | 38;5;183 |
| Anthropic / 5hレート制限 | サンドベージュ | 38;5;180 |
| extra-usage 実課金額 | gold | 38;5;220 |
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
| PR review_state (`approved` / `changes_requested` / `pending` / `draft`、他は dim) | 緑 / 赤 / 黄 / グレー | 32 / 31 / 33 / 38;5;245 |
| last commit (age + msg)、worktree from、worktree 名 (🌲 直後)、Git branch parent (`base:`)、Git origin プレフィックス (`gh:`) / weekly rate limit / セッションコスト (`$X.XX`) | dim | 2 |
| Git origin リポ名 (`owner/repo`) | 通常輝度（デフォルト前景色） | - |

## パフォーマンス

- **バックグラウンド更新**: Git (5秒) と Subscription 種別取得 (3600秒) はサブシェルで非同期更新。stale キャッシュを即座に返すため出力をブロックしない
- **単一 jq 呼び出し**: stdin JSON を `eval` + `@sh` で一括抽出（フィールドごとの再パースなし）
- **共有タイムスタンプ**: `_NOW=$(date +%s)` を1回だけ呼び、全キャッシュ判定で再利用
- **キャッシュ**: `/tmp/ist-j-ichikawa-claude-statusline/{git,subscription}` (mkdir 700) に保存
- **Git worktree 対応**: stdin JSON の `worktree.name` または `workspace.git_worktree` (Claude Code 2.1.97+) を検出して 🌲 を表示。`.claude/worktrees` 配下ではパスをリポ root で切り worktree 名を 🌲 直後に表示（パス末尾のランダム名でリポ dir が埋まるのを防ぐ）

## Line 4: レート制限 + コンテキストバー + コスト

**Anthropic** (rate_limits が届く場合)
- Claude Code 2.1.80+ の stdin JSON `rate_limits` フィールドから直接取得
- 表示: 5hバー + % + リセット残(H:MM) → コンテキストバー + % → week:% + リセット曜日時刻 → extra-usage実課金 → セッションコスト
- Pre-2.1.80 ではレート制限部分が非表示（graceful degradation）

**Bedrock / Vertex AI / Foundry**
- `rate_limits` フィールドは届かないため、コンテキストバーとコストのみ表示（extra-usage も Anthropic 限定なので非表示）

**extra-usage 実課金** (`extra:$X.XX`、gold `38;5;220`、Anthropic のみ)
- `fetch_usage_spend()` が `/usage` OAuth エンドポイント (`api.anthropic.com/api/oauth/usage`) の `spend.used` を取得 — **stdin に無い唯一の課金情報**で、usage-credits の実消費額（参考値の session cost と別物）
- **このスクリプト唯一のネットワーク呼び出し**。背景 subshell + 300s キャッシュで hot path をブロックしない。OAuth トークンは `curl --config -` で argv 非露出
- Fable は 7/7 以降 extra-usage 課金に移行するため「実際に溶けた額」を出す実益が大きい
- データ無し / 取得失敗 / `$0.00` は非表示。`CLAUDE_STATUSLINE_NO_NET=1` で fetch 自体を無効化（オフライン / プライバシー）。エンドポイントは非公式なので変わりうる前提の graceful degradation

**セッションコスト** (`$X.XX`、dim、最右)
- stdin JSON `cost.total_cost_usd` をそのまま表示。Claude Code がキャッシュ区分 (cache read/write) 込みで計算済みの API 換算額
- subscription (Max 等) 利用時は実請求ではなく参考値 — 優先度の低い情報として最右・dim 配置
- `$0.00` (セッション開始直後) とフィールド欠落 (旧 Claude Code) では非表示
- トークン数は引き続き非表示（Claude Code の `total_input_tokens` がキャッシュトークンを含まず誤解を招くため）

## クラウドプロバイダー検出

| プロバイダー | 検出条件 |
|---|---|
| Bedrock | `model.id` プレフィックス (`global.`/`jp.`/`us.`/`us-gov.`/`eu.`/`au.`/`apac.`) or `CLAUDE_CODE_USE_BEDROCK=1` or `CLAUDE_CODE_USE_MANTLE=1` |
| Vertex AI | `CLAUDE_CODE_USE_VERTEX=1` |
| Foundry | `CLAUDE_CODE_USE_FOUNDRY=1` |
| Anthropic | 上記以外 |
