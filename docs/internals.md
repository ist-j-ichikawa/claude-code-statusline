# 実装詳細

`statusline-command.sh` の内部構造・カラーテーマ・パフォーマンス最適化・プロバイダー検出ロジックの詳細。利用者向けの導入手順は [README](../README.md) を参照。

## ファイル構成

- **`statusline-command.sh`** — メイン statusLine (プロンプト直下の 4 行)。`settings.json` の `statusLine` から参照。
- **`subagent-statusline-command.sh`** — agent panel の各サブエージェント行 (`subagentStatusLine`、v1.45.0 追加)。`settings.json` の `subagentStatusLine` から参照。
- **`lib.sh`** — 両者が `source` する共有ライブラリ。色定数と fork-free な presentation ヘルパー (`has_val`/`osc8`/`editor_url`/`rainbow`/`gradient`/`model_key`/`model_color`/`braille_bar`/`color_by_threshold`/`format_tokens`/`fmt_ctx_size`/`fmt_elapsed`)。ネットワーク・キャッシュ・`date` 等の副作用は持たず、それらは `statusline-command.sh` 側に残す。モデル色は `model_color` に一元化され両 statusline が同一の tier 色を使う。tier 判定は `model_key` が display_name / id / Bedrock inference-profile を `opus 5` 等の正規形に畳み、`model_color` はその完全一致で分岐する（新モデルはパレット 1 行 + arm 1 行で足せる）。**色の対象は 4.x 以降**（3.x 系は全廃止済み。下限未満は generic tier 色に落ちるだけで壊れない）。**スクリプトと同じディレクトリに必須**（`${BASH_SOURCE%/*}/lib.sh` で解決、相対起動時は `.` に fallback）。

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
├── Git info         build_git() — git の「事実」を US 区切りで返す（ANSI も stdin 由来値も含めない。5秒バックグラウンドキャッシュ、atomic mv 書き込み）
├── Git render       render_git() — facts + stdin 由来値（workspace.repo / pr.review_state）から Line 3 を組む。cold-start も同じ presenter を通るので経路ごとの gate 差が生じない
├── Line 1           [vim mode バッジ (INSERT=ライムグリーン bg / VISUAL・V-LINE=ゴールド bg、NORMAL は非表示)] + プロバイダー + モデル名（Fable=多色(蝶標本), Opus 5=coral スイープ, Opus 4.x=コーラル, Sonnet 5=緑グラデーション, Sonnet 4.6=ティール, Sonnet 4.5=アンバー, Haiku=ラベンダー）+ effort（light purple）+ think（light cyan）+ fast（greenyellow、/fast 有効時のみ）+ Agent + Version + branch
├── Line 2           ディレクトリパス (OSC 8 リンク) + 🌲worktree名 + from:branch + added_dirs (+N dirs)。`<repo>/.claude/worktrees/<name>` 配下はリポ root と 🌲<name> (dim) に分割表示（リンクは root / worktree 各 dir へ。サブディレクトリ滞在時・既定外配置ではフルパスに fallback）。from:HEAD (detached から作成) も表示する
├── Line 3           Git ([gh: (dim) + owner/repo (通常輝度)、GitHub origin あり時のみ] + ブランチ [OSC 8 リンク → GitHub tree] + PR review_state (Claude Code 2.1.145+ pr.review_state、テキスト色分け、PR # は Claude Code 組み込み footer に任せて非表示) + base:親ブランチ (reflog) + dirty state + ahead/behind + last commit)、非git時は "no git"
├── Line 4           5hレート制限 + コンテキストバー (`%` 直後に分母 `/200k`・`/1M` 等を常時表示、% と同色) + weeklyレート制限 (Anthropic のみ) + extra-usage実課金 ($、gold、Anthropic のみ) + セッション経過時間 (dim、60秒未満は非表示) + セッションコスト ($、dim)
└── Output           printf で各行を出力
```

## Subagent statusline (`subagent-statusline-command.sh`)

agent panel (プロンプト下のサブエージェント一覧) の各行を独自描画する別系統の statusline。Claude Code の `subagentStatusLine` で有効化する (任意)。メイン statusLine とは**入出力の契約が別物**:

| | メイン statusLine | subagentStatusLine |
|---|---|---|
| stdin | セッション 1 件の JSON | 表示中の全行を 1 個の JSON (`columns` + `tasks[]`) |
| stdout | プレーンテキスト (そのまま行になる) | 上書きする行ごとに JSON 1 行 `{"id":..,"content":..}` |
| 行の扱い | 常に全行出力 | `id` を出せば上書き / 省けば既定描画 / `content:""` で非表示 |

各行の描画 (既存 statusline の語彙に揃える。`⚡` 等の独自グリフは付けない — 場所で subagent と分かる):

```
説明  モデル(pretty・tier色)  [状態]  [🌲worktree]
```

- **説明** (先頭・通常輝度): `label // description // name`。**切り詰めなし**（主 statusline と同じく端末幅適応はしない。折り返し/切れは端末に委ねる）。
- **モデル** (`model_color` の tier 色): `model` は id 形式 (`claude-opus-4-8[1m]`) で来るので `prettify_model` で Line 1 と同じ display_name 風 (`Opus 4.8`) に整形してから着色。Bedrock の inference-profile prefix (`jp.anthropic.` / `global.anthropic.` 等) と版接尾辞も剥がす (実 id は `-v1:0` の形なので `:N` を先に落とす。v1.51.0 修正)。旧形式 (`claude-3-5-sonnet-…` 等、版が tier より前) は誤分割を避け cleaned id のまま出す。
- **状態** (`status`): **「実行中」表示は Claude Code のネイティブ chrome (行頭の `○`/スピナー) に委ね、行本文に独自グリフは出さない**（自前の tick 駆動アニメは CC の本物と重複・劣化するため）。`running` / `completed`(行はまもなく消える) / 無しは無表示、それ以外 (`needs_input` 等の注意状態) だけ**黄で status 語**を出す (PR review_state と同じ色付き単語作法)。
- **worktree** (`cwd` が `.claude/worktrees` 配下の時だけ `🌲名`、Line 2 と協調)。
- **context% と経過は出さない** (v1.51.0 で撤去)。並走する subagent は同じタスクを分担するのでどれも似た値になり (実測 5-9% / 5-6m)、行が伸びるだけで判断に効かなかった。撤去に伴い `tokenCount`/`contextWindowSize`/`startTime` の抽出、`fmt_elapsed`、`date` fork がまとめて落ちた (残る fork は jq 2 回のみ)。差を見たい時は Claude Code 既定描画のトークン数か `/context` を使う。
- `effort` (2.1.214+) は per-task で明示された時のみ来る (継承時 absent・セッション effort は subagent payload に無い) スパースな値なので、現状は描画に採用していない。

実装の要点:
- **単一 jq で抽出**: `tasks[]` を US (`0x1f`) 区切りで連結。`read` の `IFS=tab` は空フィールドを潰す (tab は IFS 空白扱い) ため桁ずれする → 非空白の US を区切りに使う。全 text フィールド (`id`/`label`/`model`/`status`/`cwd`) の改行・タブは jq `gsub` で空白化し 1 行 = 1 task を保つ。抽出は default 付きスカラーのみで配列 index をしないので、1 task のフィールド型不正でも jq が abort せず全行が消えることはない。
- **単一 jq で JSON 化**: `jq -Rc 'split("\u001f") | {id,content}'` (US で分割)。content 内の ESC / 引用符 / バックスラッシュを安全にエスケープ (Claude Code 側で JSON パース後、ANSI/OSC 8 としてそのまま描画される)。
- **graceful degradation**: `model`/`status` 欠落 (旧 Claude Code)、`tasks` 空、不正 JSON、空入力のいずれでも `exit 0`。`id` を出さない行は Claude Code 既定の `名前 · 説明 · トークン数` に委ねる。先頭の `❯ ◯`・選択・クリック展開は Claude Code 側の chrome で、本スクリプトは行本文のみ差し込む。

## カラーテーマ

| 指標 | 色 | ANSIコード |
|---|---|---|
| vim mode `INSERT` | 黒文字 / ライムグリーン bg (bold) | 1;30;48;5;148 |
| vim mode `VISUAL` / `V-LINE` | 黒文字 / ゴールド bg (bold) | 1;30;48;5;214 |
| コンテキスト使用率 | < 80% lime green / 80-89% 黄 / >= 90% 赤 | 38;5;82 / 33 / 31 |
| Fable | 多色・蝶標本 (文字ごとに循環) | `rainbow()` 178/172/130/167/143/107/66 |
| Opus 5 | coral 一族の暗→明スイープ orange→coral→gold | `gradient()` 130→173→215 |
| Opus 4.x | コーラル (artwork実測) | 38;5;173 |
| Sonnet 5 | 緑グラデーション (文字ごとにスイープ) | `gradient()` 28→70→148→154 |
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
| fast (`/fast` 有効時、`fast_mode`) | greenyellow | 38;5;190 |
| Agent 名 | ピンク | 38;5;213 |
| version (`v2.1.x`) | グレー | 38;5;248 |
| branch セッション (`branch`) | 黄 | 33 |
| Git ブランチ名 | Git brand オレンジ | 38;5;202 |
| Git staged `A` / ahead `↑` | 緑 | 32 |
| Git modified `M` | 黄 | 33 |
| Git untracked `?` | グレー | 38;5;248 |
| Git conflicts `U` / behind `↓` / Detached HEAD | 赤 | 31 |
| PR review_state (`approved` / `changes_requested` / `pending` / `draft`、他は dim) | 緑 / 赤 / 黄 / グレー | 32 / 31 / 33 / 38;5;245 |
| last commit (age + msg)、worktree from、worktree 名 (🌲 直後)、Git branch parent (`base:`)、Git origin プレフィックス (`gh:`)、weekly rate limit、セッション経過時間 | dim (SGR 2 = faint 属性。色ではないので端末依存) | 2 |
| セッションコスト (`$X.XX`) | 通常輝度 (色を付けない — Line 4 の 3 系統の色に 4 つ目を足さない。金色は extra-usage の実課金と混同するため不可) | - |
| コンテキストの分母 (`/200k`・`/1M` 等を常時表示。値が来ていない旧 CC のみ無印) | 使用率と同じ色 (`88%/1M` を一体で読ませる) | 38;5;82 / 33 / 31 |
| Git origin リポ名 (`owner/repo`) | 通常輝度（デフォルト前景色） | - |

## パフォーマンス

- **バックグラウンド更新**: Git (5秒) と Subscription 種別取得 (3600秒) はサブシェルで非同期更新。stale キャッシュを即座に返すため出力をブロックしない
- **単一 jq 呼び出し**: stdin JSON を `eval` + `@sh` で一括抽出（フィールドごとの再パースなし）
- **共有タイムスタンプ**: `_NOW=$(date +%s)` を1回だけ呼び、全キャッシュ判定で再利用
- **キャッシュ**: `${TMPDIR:-/tmp}/claude-statusline-$UID/{git,subscription,usage_spend}` (mkdir 700、親も含めて owner-only) に保存。`CLAUDE_STATUSLINE_CACHE_DIR` で差し替え可 (テスト密閉の seam)。固定の共有パスは共有 Mac で書けず curl storm になるため v1.52.0 でユーザー単位に変更
- **Git worktree 対応**: stdin JSON の `worktree.name` または `workspace.git_worktree` (Claude Code 2.1.97+) を検出して 🌲 を表示。`.claude/worktrees` 配下ではパスをリポ root で切り worktree 名を 🌲 直後に表示（パス末尾のランダム名でリポ dir が埋まるのを防ぐ）

## Line 4: レート制限 + コンテキストバー + コスト

**Anthropic** (rate_limits が届く場合)
- Claude Code 2.1.80+ の stdin JSON `rate_limits` フィールドから直接取得
- 表示: 5hバー + % + リセット残(H:MM) → コンテキストバー + % → week:% + リセット曜日時刻 → extra-usage実課金 → セッション経過時間 → セッションコスト
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
