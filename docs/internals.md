# 実装詳細

`statusline-command.sh` の内部構造・カラーテーマ・パフォーマンス最適化・プロバイダー検出ロジックの詳細。利用者向けの導入手順は [README](../README.md) を参照。

## ファイル構成

- **`statusline-command.sh`** — メイン statusLine (プロンプト直下の 5 行)。`settings.json` の `statusLine` から参照。
- **`subagent-statusline-command.sh`** — agent panel の各サブエージェント行 (`subagentStatusLine`、v1.45.0 追加)。`settings.json` の `subagentStatusLine` から参照。
- **`lib.sh`** — 両者が `source` する共有ライブラリ。色定数と fork-free な presentation ヘルパー (`has_val`/`osc8`/`editor_url`/`rainbow`/`gradient`/`model_key`/`model_color`/`braille_bar`/`color_by_threshold`/`format_tokens`/`fmt_ctx_size`/`fmt_elapsed`/`plan_label`/`effort_color`/`ver_older`)。ネットワーク・キャッシュ・`date` 等の副作用は持たず、それらは `statusline-command.sh` 側に残す。モデル色は `model_color` に一元化され両 statusline が同一の tier 色を使う。tier 判定は `model_key` が display_name / id / Bedrock inference-profile を `opus 5` 等の正規形に畳み、`model_color` はその完全一致で分岐する（新モデルはパレット 1 行 + arm 1 行で足せる）。**色の対象は 4.x 以降**（3.x 系は全廃止済み。下限未満は generic tier 色に落ちるだけで壊れない）。**スクリプトと同じディレクトリに必須**（`${BASH_SOURCE%/*}/lib.sh` で解決、相対起動時は `.` に fallback）。`osc8` は URL 側だけ `%` `;` `#` `?` を percent-encode する（表示テキストは素のまま。理由と `%` を先に処理する必要は `lib.sh` のコメント）。

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
├── Line 1           [vim mode バッジ (INSERT=青 bg / VISUAL・V-LINE=橙 bg、vim 側の流儀。NORMAL は非表示)] + プロバイダー + モデル名（Fable 5=多色(蝶標本), Fable 5.1=Venus レーダーのスイープ, Opus 5=coral スイープ, Opus 4.x=コーラル, Sonnet 5=緑グラデーション, Sonnet 4.6=ティール, Sonnet 4.5=アンバー, Haiku=ラベンダー）+ effort（レベルごとの色。low=gold / medium=green / high=薄紫 / xhigh=濃紫 / max=多色）+ think（light cyan）+ fast（greenyellow、/fast 有効時のみ）+ output style（常に出す。`default` は dim = 「特に設定していない」プレースホルダ扱い、非既定は白で立つ）+ Agent + 宛名（cross-session messaging のアドレス。`~/.claude/sessions/<pid>.json` の derived name を `session_id` で照合して読む。ラベルも囲みも付けないので、要素間のスペースが単語境界になりダブルクリックで名前だけ取れる）+ セッション出自（`/branch`=`branch:`+元セッション id (full uuid) / `/fork`=`fork`、ラベルはどちらも黄。`branch` は transcript の `forkedFrom` で裏取りし、同じ記録から元 id も抜く）+ Version（**行の最後**。Claude Code の版は行動に効かない参照情報なので、モデル・effort・宛名・出自の後に置く。truncate で最初に削られてよい要素でもある）
├── Line 2           ディレクトリパス (OSC 8 リンク) + 🌲worktree名 + from:branch + added_dirs (+N dirs)。`<repo>/.claude/worktrees/<name>` 配下はリポ root と 🌲<name> (dim) に分割表示（リンクは root / worktree 各 dir へ。サブディレクトリ滞在時・既定外配置ではフルパスに fallback）。from:HEAD (detached から作成) も表示する
├── Line 3           Git ([進行中の git 操作 (`rebase 2/5`/`merge`/`cherry-pick`/`revert`/`bisect`、赤。**行の先頭**。`HEAD@<sha>` だけでは「sha を checkout した」と「rebase 中」が区別できないため)] + [forge 略号 (dim。GitHub = `gh:` / GitLab = `gl:`) + owner/repo (通常輝度)。既知 forge の origin あり時のみ。Line 2 のパスと一致した成分だけ削る: owner/repo 一致 → 非表示 / repo 名だけ一致 → `gh:owner/` / 不一致 → 全表示] + ブランチ [OSC 8 リンク → GitHub は `/tree/`、GitLab は `/-/tree/`] + PR/MR review_state (Claude Code 2.1.145+ pr.review_state。GitLab MR は 2.1.234+ で同じキーに載り値は draft/approved/pending の 3 値。テキスト色分け、PR #/MR ! は Claude Code 組み込み footer に任せて非表示) + 変更行数 (`+42 -17`、Claude Desktop の code 画面と同じ単位・色) + ahead/behind + last commit (**ISO 8601 風の絶対時刻** `08-17T13:13`。180 日超は `2025-08-17`。どの古さでも必ず出す) + msg)、非git時は "no git"
├── Line 4           **このセッション**: コンテキストバー (`%` 直後に分母 `/200k`・`/1M` 等を常時表示、% と同色) + セッション経過時間 (dim、60秒未満は非表示。**アイドル込みの壁時計** = `cost.total_duration_ms`) + セッションコスト ($、ブロンズ 136 = 参考値) + プロンプトキャッシュ (`prompt_cache:warm`/`cold` と `hit_ratio:N%`。ラベルだけ dim。Claude Code 2.1.251+)
├── Line 5           **アカウント**: 5hレート制限 + weeklyレート制限 + モデル別weekly制限 (`Fable:39%`) + usage-credits実課金 ($、gold)。全要素 Anthropic 限定なので Bedrock 等ではこの行が出ない (空行は挟まない)
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
説明  モデル(pretty・tier色)  [effort]  [状態]  [🌲worktree]
```

- **説明** (先頭・通常輝度): `label // description // name`。**切り詰めなし**（主 statusline と同じく端末幅適応はしない。折り返し/切れは端末に委ねる）。
- **モデル** (`model_color` の tier 色): `model` は id 形式 (`claude-opus-4-8[1m]`) で来るので `prettify_model` で Line 1 と同じ display_name 風 (`Opus 4.8`) に整形してから着色。Bedrock の inference-profile prefix (`jp.anthropic.` / `global.anthropic.` 等) と版接尾辞も剥がす (実 id は `-v1:0` の形なので `:N` を先に落とす。v1.51.0 修正)。**日付つき id の末尾 8 桁も落とす** — `claude-haiku-4-5-20251001` は現行モデルの実 id で、落とさないと Line 1 の display_name (`Haiku 4.5`) に対して subagent 行だけ `Haiku 4.5.20251001` になり、同じモデルが 2 通りの名前で並ぶ (v1.89.0 修正)。**「末尾の数字」ではなく 8 桁ちょうどのパターンで消す** — 数字一般だと `opus-5` の版まで食う。旧形式 (`claude-3-5-sonnet-…` 等、版が tier より前) は誤分割を避け cleaned id のまま出す (日付だけは同じ規則で落ちるので `3-5-sonnet` になる)。
- **状態** (`status`): **「実行中」表示は Claude Code のネイティブ chrome (行頭の `○`/スピナー) に委ね、行本文に独自グリフは出さない**（自前の tick 駆動アニメは CC の本物と重複・劣化するため）。`running` / `completed`(行はまもなく消える) / 無しは無表示、それ以外 (`needs_input` 等の注意状態) だけ**黄で status 語**を出す (PR review_state と同じ色付き単語作法)。
- **worktree** (`cwd` が `.claude/worktrees` 配下の時だけ `🌲名`、Line 2 と協調)。
- **context% と経過は出さない** (v1.51.0 で撤去)。並走する subagent は同じタスクを分担するのでどれも似た値になり (実測 5-9% / 5-6m)、行が伸びるだけで判断に効かなかった。撤去に伴い `tokenCount`/`contextWindowSize`/`startTime` の抽出、`fmt_elapsed`、`date` fork がまとめて落ちた (残る fork は**抽出の jq 1 個だけ**。v1.89.0 で出力側の jq も落ちた)。差を見たい時は Claude Code 既定描画のトークン数か `/context` を使う。
- **`effort`** (レベルごとの色。Line 1 と同じ `effort_color` を使う、2.1.214+): **セッションの effort を継承している行では absent** なので、出るのは「この subagent だけ effort が違う」時だけ = 差分そのものがシグナルになる (v1.61.0 で採用)。撤去した context%/経過とは性質が逆で、あちらは全行に出て値が揃っていた (だから情報量が無かった)。値はレベル文字列 (`low`/`medium`/`high`/`xhigh`/`max`) か**数値のトークン予算**で、数値は `fmt_ctx_size` で `8k` 形に畳む。docs は「設定された値をそのまま報告する」と明記しており、モデルが非対応レベルなら実際に適用される effort と異なりうる。

実装の要点:
- **単一 jq で抽出**: `tasks[]` を US (`0x1f`) 区切りで連結。`read` の `IFS=tab` は空フィールドを潰す (tab は IFS 空白扱い) ため桁ずれする → 非空白の US を区切りに使う。全 text フィールド (`id`/`label`/`model`/`status`/`cwd`/`effort`) の制御文字は jq `gsub("[[:cntrl:]]"; " ")` で空白化し 1 行 = 1 task を保つ。**改行・タブだけでは足りなかった** (v1.89.0 修正): US を含む label が来ると連結行が割れ、**model が status のフィールドに入って生 id が黄で出る** (実測)。ESC も同時に落ちるので、task の説明文からの ANSI 注入も塞がる — 行に色を付けるのは本スクリプトだけになる。**クラス名で書く理由は escape が要らないこと** — 正規表現側のエスケープとして `\u0001-\u001f` を渡すと jq の正規表現エンジンが字面で解釈して別の文字を潰し (実測)、jq の文字列エスケープで書くと**プログラムに生の制御文字が埋まって `grep` で見えなくなる** (このリポは「US は ASCII エスケープで書く」を規則にしている)。**stdin は変数に読まず jq に直接継承させる** (主 statusline と同じ作法。`read` + here-string の一時ファイルが消える)。抽出は配列 index をせず、`effort` のように非スカラーが来うるフィールドは `if type == "string" or type == "number"` の型ガードを通してから `tostring` するので、1 task のフィールド型不正でも jq が abort せず全行が消えることはない (ガード無しで新フィールドを足すと全パネルが既定描画に戻る)。
- **JSON 化は fork ゼロの bash 置換** (v1.89.0。以前は `jq -Rc` を 1 個起動していた): `json_str` が `\` → `"` → ESC の順で escape する。**不変条件は「`\` を最初」の 1 つだけ** — 後回しにすると `"`/ESC の置換が入れた `\` をもう一度 escape して壊す (`osc8` が `%` を最初に処理するのと同じ理屈)。`"` と ESC は互いの生成物に触らないので相互順序は問わない。扱うのは**自分が付けた ANSI の ESC だけ**で、他の制御文字は抽出側で空白化済み。ESC を `\u001b` にするのは Claude Code の JSON パーサに素の制御文字を渡さないため (従来の `jq -Rc` の出力と同じ形なので、ワイヤ上の表現は変わっていない)。**行ごとに printf せず最後に単一 printf** (主 statusline と同じ)。実測 17.4ms → 11.3ms (jq 1 個 + here-string 2 個ぶん。2 task の入力を直接 spawn して 30 回平均。`/bin/bash -c` 越しに測ると両方に一定のオーバーヘッドが乗って 39ms → 24ms になるが、削減率は同じ)。テストは ① `jq -e .` でパース可能なこと ② `"` と `\` を含む値が往復すること ③ **jq の起動回数が 1 回**であること（回数は表示に出ないので `_count_cmd` で数え、PATH に jq しか置かないので他を fork すれば stderr で赤くなる）④ **2 task なら 2 行**で空行を挟まないこと（連結 1 行でも空行入りでも `jq -r .content` は通るので、行数でしか pin できない）⑤ 制御文字は**クラス全部**が潰れること（US と ESC だけ列挙した実装では、`0x01` が残って出力が不正 JSON になる = agent panel の全行が落ちる）の 5 点で pin する。
- **graceful degradation**: `model`/`status` 欠落 (旧 Claude Code)、`tasks` 空、不正 JSON、空入力のいずれでも `exit 0`。`id` を出さない行は Claude Code 既定の `名前 · 説明 · トークン数` に委ねる。先頭の `❯ ◯`・選択・クリック展開は Claude Code 側の chrome で、本スクリプトは行本文のみ差し込む。

## カラーテーマ

**採色の作法**（CLAUDE.md から降ろした。2026-08-31）: **スクリーンショットから採色しない** — 背景と混ざるので、追加行/削除行の 71 / 203 は GitHub Primer dark の `#3fb950` / `#f85149` の **256 色最近傍**として決めた（ANSI 31/32 は端末テーマが olive/brick に化けさせるので使わない）。output style の 231 は **176 を却下した結果**（Agent 名の 213 と実機で見分けが付かなかった）。effort の値は `/effort` ピッカーの実測で、**未知のレベルは 105 に落とす**。金額は SPEND 220 太字（実課金）と COST 136（参考値）の明度差で序列を出す（**コストを無色に戻さない**）。`DIMVER` 248 と `DRAFT` 245 は明度差 30 で併存できる。

**ダークテーマ推奨**（2026-08-17 の判断）。色は暗い背景でのコントラストを基準に選んでいるので、白地では lime 82 / gold 220 / 白 231 / think 117 / fast 190 が 1.0〜1.6:1 しかなく読めない（実測）。**ライトテーマ対応は入れない** — 端末の地色を知る手段が無い（stdin にテーマ情報は来ない）ので、両対応にするには「どちらでも読める中間色」へ寄せる＝暗地でのコントラストを捨てることになる。再検討条件は **stdin が端末の配色/テーマを渡してきたとき**。


| 指標 | 色 | ANSIコード |
|---|---|---|
| vim mode `INSERT` | 黒文字 / 青 bg (bold)。**gruvbox/airline の流儀**（緑は NORMAL/COMMAND なので使わない） | 1;30;48;5;109 |
| vim mode `VISUAL` / `V-LINE` | 黒文字 / 橙 bg (bold) | 1;30;48;5;208 |
| コンテキスト使用率 | < 80% lime green / 80-89% 黄 / >= 90% 赤 | 38;5;82 / 33 / 31 |
| Fable 5 | 多色・蝶標本 (文字ごとに循環) | `rainbow()` 178/172/130/167/143/107/66 |
| Fable 5.1 / 版なし `Fable` | 多色・Venus レーダー (1 回スイープ) brick→tan→amber→cream | `gradient()` 95→137→214→187 |
| Opus 5 | coral 一族の暗→明スイープ orange→coral→gold | `gradient()` 130→173→215 |
| Opus 4.x | コーラル (artwork実測) | 38;5;173 |
| Sonnet 5 | 緑グラデーション (文字ごとにスイープ) | `gradient()` 28→70→148→154 |
| Sonnet 4.6 | ティール | 38;5;79 |
| Sonnet 4.5 | アンバー | 38;5;214 |
| Haiku | ラベンダー | 38;5;183 |
| Anthropic / 5hレート制限 | サンドベージュ | 38;5;180 |
| usage-credits **実課金額** | 明るい gold + **太字** | 1 / 38;5;220 |
| セッションコスト | ブロンズ (credits と同色相で明度だけ下げる = 参考値) | 38;5;136 |
| Bedrock | ティールグリーン | 38;5;72 |
| Vertex | Google ブルー | 38;5;33 |
| Foundry | Azure ブルー | 38;5;39 |
| effort `low` | gold | 38;5;178 |
| effort `medium` | green | 38;5;71 |
| effort `high` / 未知のレベル | 薄紫 (periwinkle) | 38;5;105 |
| effort `xhigh` | 濃紫 (violet) | 38;5;99 |
| effort `max` | 多色・紫→桃→橙 (文字ごとにスイープ) | `gradient()` 99→170→209 |
| think | light cyan | 38;5;117 |
| fast (`/fast` 有効時、`fast_mode`) | greenyellow | 38;5;190 |
| Agent 名 | ピンク | 38;5;213 |
| 宛名 (derived name。ラベルも囲みも付けない) | 無色・通常輝度 (値が一次情報。`SendMessage` にコピーする値なので弱めない) | - |
| セッション出自のラベル (`branch:` / `fork`) | 黄 | 33 |
| セッション出自に添える元セッション id (full uuid) | 通常輝度 (`gh:` と同じ「ラベルだけ色、値は一次情報」の作法。コピーして `--resume` に渡す値なので弱めない) | - |
| version (`v2.1.x`。Line 1 の最後) | グレー | 38;5;248 |
| version (最新版から遅れている間だけ。追いつけば 248 に戻る) | 赤 (アラーム色。既存の「注意すべき状態」の語彙を借りる) | 31 |
| output style (非既定) | 白 (Line 1 に唯一残っていた「色相を持たない」枠。Agent 名のピンク 213 と被らせないため) | 38;5;231 |
| output style (`default`) | dim (既定値はプレースホルダ扱い。`no git` と同じ) | 2 |
| 進行中の git 操作 (`rebase 2/5` / `merge` / `cherry-pick` / `revert` / `bisect`、Line 3 の先頭) | 赤 (detached / conflicts と同じ「特別な git 状態」) | 31 |
| Git ブランチ名 | Git brand オレンジ | 38;5;202 |
| Git 追加行 `+N` / ahead `↑` | GitHub Primer `--fgColor-success`(dark `#3fb950`) の最近傍。**ANSI 32 は端末テーマが olive に化かす**ので 256 色を明示 | 38;5;71 |
| Git 削除行 `-N` / behind `↓` | GitHub Primer `--fgColor-danger`(dark `#f85149`) の最近傍（同上） | 38;5;203 |
| conflicts `!N` / Detached HEAD | 赤 (**アラームの赤**。「量」の 71/131 と役割を分ける) | 31 |
| PR review_state (`approved` / `changes_requested` / `pending` / `draft`、他は dim) | 緑 / 赤 / 黄 / グレー | 32 / 31 / 33 / 38;5;245 |
| last commit (age + msg)、worktree from、worktree 名 (🌲 直後)、Git origin の forge 略号 (`gh:` / `gl:`)、weekly rate limit、セッション経過時間 | dim (SGR 2 = faint 属性。色ではないので端末依存) | 2 |
| コンテキストの分母 (`/200k`・`/1M` 等を常時表示。値が来ていない旧 CC のみ無印) | 使用率と同じ色 (`88%/1M` を一体で読ませる) | 38;5;82 / 33 / 31 |
| プロンプトキャッシュのラベル (`prompt_cache:` / `hit_ratio:`。Line 4 の末尾) | dim (ラベルだけ弱め・値は通常輝度 = `gh:` と同じ dim 役。色は増やさない) | 2 |
| Git origin リポ名 (`owner/repo`) | 通常輝度（デフォルト前景色） | - |

**Fable のパレットは 2 本ある**（2026-09-02、v1.88.0）。公式 hex は Fable 5 / Fable 5.1 とも**未発表**なので、どちらも発表アートワーク由来の暫定色。

- **`fable 5` だけが蝶標本**（`FABLE_PAL`）— Fable 5 の発表アートワーク（ヴィンテージの蝶標本プレート、暖色主体）の実測色。**旧モデルを選んだ人の画面は変えない**ので専用に残す
- **5.1 と、版が読めない裸の `Fable` は Venus レーダー**（`FABLE51_PAL`）— Fable 5.1 の発表記事の図版が別モチーフ（Venus / Magellan のレーダー画像。動画は 15 秒すべて tan のモノクロームで、2 秒ごとの平均色は `#8d7d63`〜`#96856b`、明度分位は `#4a4338`〜`#ddbc82`）なので追従した。**「ヒーローアートワーク」ではない** — 5.1 の発表ページは記事のヒーロー画像を持たず（OG 画像も Anthropic のワードマークだけ）、この図版は本文「Computational analysis and modeling」節のもの。キャプションは実物で `Magellan radar` / `Altimetry 10-20km footprint` / `New DEM (300m) a volcano 15km across` / `A small shield volcano on Venus`。**Fable 5.1 自身が作った成果**の説明図で、Magellan のレーダー画像から Venus の 1/3 の標高マップを 10〜20km → 2〜3km 解像度で作り直したもの（NASA VERITAS / ESA EnVision に向けて CC ライセンスで公開）。だから Fable 5 の蝶標本（モデルの識別画像そのもの）とは性質が違う
- **generic 側（`fable*`）を Venus にする向きが必須** — `/usage` の `limits[]` は版を持たない `"Fable"` しか返さないので、Line 5 の `Fable:39%` は generic の arm に落ちる。既定モデルが 5.1 なので、Line 1 と色が揃うのはこの向きだけ

**アートワークの生値そのままにはしない。** 実測の最暗 `#4a4338` は 256 色最近傍が 238（純グレー）で黒地では先頭文字がほぼ沈み、最明側は near-white で light テーマで飛ぶ。`/model-colors` の明度式（**`L = 0.2126R + 0.7152G + 0.0722B` = ガンマ補正済み値の相対輝度。CIE L* ではない**）でほぼ等間隔に引き直した（L=103.5 → 140.6 → 179.4 → 212.1、ΔL=+37/+39/+33 で同 skill の「28 以上離す」を満たす）。**180 は使わない** — Line 1 でモデル名のすぐ左に来る `Anthropic` ラベルと同じ色なので、1 塊に見えて要素の境界が消える。214 は Sonnet 4.5 の flat 色と同値だが、スイープ内部の 1 ストップなので衝突しない（Opus 5 が 173 = Opus 4.x 色を内部に持つのと同じ前例）。低彩度の tan/olive がくすんで「グラデーションに見えない」実測（Opus 5 のアートワーク忠実版。CHANGELOG 1.50.0）を避けられるのは、この明度レンジ（103→212）が Sonnet 5 の `28`→`154` と同程度に広いから。

差し替えの再検討条件は **claude.ai の UI か発表ページに Fable の公式 hex が現れたとき**。

## 宛名 (cross-session messaging のアドレス)

cross-session messaging（`SendMessage` / `ListAgents`、2.1.224+）でこのセッションを指すアドレスです。`~/.claude/sessions/<pid>.json` の `name` フィールドを、stdin の `session_id` で照合して読みます。

読む場所は **`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions/`** です。`CLAUDE_CONFIG_DIR` は設定ディレクトリ全体を差し替える環境変数で、docs（env-vars）が「All settings, session history, and plugins are stored under this path」と明記しています。複数アカウントの併用や案件ごとの切り替えでこれを設定して走るセッションがあり、`$HOME/.claude` をハードコードすると sessions が 1 件も見つからず**宛名が丸ごと消えます**（v1.71.0 までのバグ。実測で `CLAUDE_CONFIG_DIR` を切り替えたセッションのファイルはそちらにしか存在しませんでした）。同じ理由で `.credentials.json` の fallback パスも env を尊重します — ただしこちらが見るのは `CLAUDE_CONFIG_DIR` ではなく **`CLAUDE_SECURESTORAGE_CONFIG_DIR`**（定義済みならその値、空なら `$HOME/.claude`、未定義なら config dir）で、上流も credentials だけこの変数で置き場を決めます。ハードコードしていた間は、別 config dir で subscription と usage-credits が無言で消えていました。

出すのは**そのセッション自身の宛名**です。目的は「これをコピーして別のセッションに渡し、そちらからこのセッションへ送らせる」ことなので、`session_id` が指すセッションの名前を出します（同じ端末に interactive と背景の 2 セッションが並ぶことがありますが、描画対象の `session_id` に対応する側を出せば常に「自分の宛先」になります）。

**アドレスは session id でも右上のタイトルでもなく、`name` フィールドです**（2.1.229 実測）。`ListAgents` の実出力も `my-project-otlp-41` の形で `name` と一致し、ツール定義も "Names are the address" と明記しています。`claude agents --json` も同じ `name` を返すので、2 系統で裏が取れています。

タイトルは **2 系統**あります:

| キー | 誰が書くか | 直近 40 transcript での付与 |
|---|---|---|
| `aiTitle` | Claude Code が会話内容から自動生成（`language` 設定で言語が決まる） | 26 件 |
| `customTitle` | ユーザー由来のみ（`/rename` と `/branch <名前>`） | 14 件 |

**どちらも会話内容由来**なので、通常のセッション（`nameSource: derived`）では cwd 由来の宛名と食い違います。決定的な実測は、customTitle が `v2について` のセッションでも `name` は `my-project-b6` / `nameSource` は `derived` のままだったことです。この形では宛名がどこにも表示されていませんでした（下の表のとおり、背景セッションと `/branch <名前>` では一致します）。

**ステータスラインの stdin に来る `session_name` は宛名ではありません。** 2.1.258 の payload 構築コードでは `session_name` が `customTitle ?? aiTitle`、つまり**上の表の 2 系統そのもの = 右上に出る表示名**です。つまり「sessions/*.json の走査をやめて stdin の 1 フィールドに寄せる」最適化は成立しません — 宛名として出せば**送れない名前を送信先として見せる**ことになり、この機能で唯一の誤情報経路（`SendMessage` の誤配）を新設します。`session_name` を読んでいるのは出自マーカー（`(Branch)` / `⑂`）の判定だけで、表示はしません。

**`nameSource` で絞り込みません。** `name` は生成規則にかかわらず常に `SendMessage` のアドレスなので、出さなければ「送れる宛先が画面のどこにも無い」状態が生まれます。

`name` の生成規則は 3 通り観測しています:

| セッションの種類 | `nameSource` | `name` の値 |
|---|---|---|
| 素の interactive | `derived` | cwd 由来（`my-project-c7`） |
| 背景（`kind:bg`、`claude agents` 経由） | **キー無し** | AI 生成タイトル（`statuslineに session id を常に表示`） |
| 背景・タイトル生成前 | **キー無し** | **8 桁の job id**（`8ee64b09`）。あとで AI タイトルに変わる |
| `/branch <名前>` | **キー無し** | ユーザーが渡した名前（`customTitle` にも同じ値が入る） |
| `/rename <名前>` | **キー無し** | ユーザーが渡した名前（`name` を書き換え、`nameSource` キーを消す） |

v1.69.0 では「`"nameSource":"derived"` の明示があるときだけ出す」許可リストにしていました。`/branch <名前>` が右上のタイトルと同じ文字列になるのを避ける意図でしたが、**キー不在は `/branch <名前>` 固有ではありません** — 背景セッションも、`/rename <名前>`（interactive で誰でも使う常用コマンド）もキーを持たないので、`claude agents` 経由のセッションと**リネームした全セッション**で宛名が丸ごと消えていました（v1.71.0 で撤去）。「キー不在 = ユーザーが付けた名前 = 右上に出ている」という推論が外れていた形で、テストも stderr も赤くならない沈黙した破綻でした。

そのため `/branch <名前>` と `/rename <名前>` では右上と宛名が同じ文字列になりますが、**常に送れる状態を保つほうを優先します**。

**enum を増やして絞り直すのは誤りです。** `nameSource` は「この名前が既に画面のどこかに出ているか」の代理にすぎず、`derived OR kind:bg` のように観測済みの種類を列挙し直しても、上流が次の種類を追加した瞬間に同じ沈黙した破綻が再発します（実際、この再検討条件は CLAUDE.md に事前登録してあったのに踏みました）。再び gate を入れてよいのは **① Claude Code が宛名をネイティブ表示するようになった**（重複が純粋なノイズになる）か **② 「この名前はユーザーに見えている」を直接示すフィールドが来た**ときだけです。「別の `kind` が見つかった」は理由になりません。

なお `jq` で読むと欠損フィールドも `null` を返すため「`nameSource` が null になる」と誤読しやすい点は変わらず注意が必要です — 生の JSON には `"nameSource"` の並びが 1 つもありません。テスト fixture も実物どおりキーを丸ごと落とします。

### 表記: ラベルも囲みも付けない

宛名は `SendMessage` にコピーして使う値なので、**ダブルクリックで名前だけが選択される**ことが要件です。その条件は「前後が単語境界文字であること」で、要素間のスペースがそれを満たします。名前に含まれる `-` は Ghostty のデフォルト境界文字 18 文字（`` \t'"│`|:;,()[]{}<>$``、`src/terminal/selection_codepoints.zig` 実測）に**含まれない**ので、`claude-code-statusline-74` は丸ごと 1 単語として選択されます。

却下した表記:

| 表記 | 却下理由 |
|---|---|
| `@name` | `@` が境界文字に無いため記号ごと選択され、貼った後に消す手間が出る |
| `<name>` / `[name]` | 囲みが視覚ノイズなうえ、**選択の改善にならない**（下記） |
| `peer:` | ラベル語の向きが逆 — 上流は `peerProtocol` / `Peer sessions` を**他セッション群**に使うので、自分の宛名に付けると「相手」に読める |

**空白を含む名前はどの表記でもダブルクリックで取れません。** 空白は Ghostty のデフォルト境界文字に含まれるので、選択は空白で必ず切れます — 囲みや記号は「どこまでが名前か」を示すだけで、選択範囲を変えません。したがって背景セッションや `/rename <名前>` の名前は範囲選択が必要で、これは表記の選び方では解決しない制約です（解決するには名前そのものを加工することになり、宛先として間違った値になります）。cwd 由来の名前は空白を含まないので、そちらはダブルクリックで取れます。

`branch:<uuid>` 側は対応不要です（`:` が境界文字かつ `-` が非境界なので、uuid 全体が一発で取れます）。ラベルを持たないことで `branch:` との形の違いも自然に付きます — 役割が真逆（自分の宛名 / 他セッションへの参照）なので、同じ `ラベル:値` で揃えると色（dim / 黄）だけでは「どちらが自分か」が読み取れません。

同一リポで複数セッションを開くと suffix だけが違う宛名になります（実測: `…-my-project-41` と `-5c`）。どの端末がどちらかは宛名を見ないと判別できないので、常時表示します。**ただし宛名は固定 ID ではありません** — resume で pid が変わると suffix も変わります（実測: `claude-code-statusline-74` → `-1d`）。判別に使えるのは「その時点で並んでいる端末どうしの区別」までで、宛名をメモして後で使う類のものではありません。

読み取りは **fork ゼロ**です（glob 展開 + `read` のリダイレクトのみ。実測 1.2ms / `grep` 版は 5.9ms）。この安さのためキャッシュを持ちません — `cache_stale` の `stat` を 1 個足すほうが高くついた（v1.81.0 のまとめ取り以降はこのコスト差は無くなりましたが、次の理由だけで判断は変わりません）。そして**宛名は走行中に実際に書き換わる**ので（`/branch <名前>` `/rename <名前>` はどちらも `name` を書き換え、背景セッションは 8 桁 id → AI タイトルへ変わる）、キャッシュすると死んだ宛先を出し続けることになります。毎レンダー同期で読む今の形だけが、その瞬間に有効な宛先を保証します。`read` の戻り値は見ず**内容の有無で判断します** — このファイル群は末尾に改行が無く、`read` は rc=1 を返しつつ内容は変数に入るためです（`forkedFrom` スキャンと同じ罠）。`name` の needle は `"name":"` で、`"nameSource":"` には一致しません（`"name` の次が `S`）。

ファイルは **`[[ -r "$_sf" ]]` で gate します**。`read ... < "$_sf" 2>/dev/null` ではリダイレクトが左から適用されるため入力側の失敗を黙らせられず、`~/.claude/sessions/` が無い環境（cross-session messaging は 2.1.224+ なので旧版には存在しません）では glob が未展開のまま渡って**毎レンダー stderr に "No such file or directory"** が出ます。credentials の `$(<file)` と同じ扱いで、リダイレクトではなく gate で消します。テストは **stderr が空であることを assert します** — `2>/dev/null` で捨てると gate を外しても緑のままになるためです。各 gate は `break` ではなく `continue` を使い、同一 sessionId のファイルが複数ある形（`--resume` 後の残骸など）で先頭が読めなくても後続の正しいファイルを拾えるようにしています。fork ゼロのループなので走査を続けるコストはありません。

値の取り出しでは**終端の `"` を探す前に `\"` と `\\` を退避します**。値の中の `"` は JSON では必ず `\"` なので、素朴に最初の `"` で切ると `fix \"foo\" bug` が `fix \` になり、**誤った宛名を出して `SendMessage` が誤配されます**。名前が cwd 由来の slug だけだった頃は `"` が入らず踏みませんでしたが、AI 生成タイトルや `/branch <名前>` の任意文字列を受けるようになって常用経路に乗りました。

同一 `sessionId` のファイルが複数あるときは **glob 順（pid の辞書順）の先勝ち**です。ただし実測では `<pid>.json` は**再利用され、中の `sessionId` が別のセッションに差し替えられる**ことがあります（`/branch` で観測）。したがって「古いファイルが残り続ける」形よりも「同じファイルが上書きされる」形が普通で、stale による誤表示は起きにくい構造です。recency 判定には `stat` の fork が要り fork ゼロの利点を失うので入れていません — キャッシュを持たない設計なので、ずれても次のレンダーで自然回復します。

「宛名が変」という報告が来たときに疑う順序:

1. **glob 順** — 上記のとおり先勝ちです。
2. **消えるのではなく「別物が出る」場合は抽出側** — `${_sl#*'"name":"'}` はスコープを閉じないので、上流が `name` を持つオブジェクトを top-level より前にネストすると（`"model":{"name":…}` 等）誤った名前を出します。これはこの機能で唯一「無表示」ではなく**誤情報**になる経路で、`SendMessage` の誤配につながります。現状は flat な 1 行 object という実測（5 件）で足りているため brace 均衡チェックは入れていません。兄弟の `parent_sid` 抽出が `}` でスコープを閉じ uuid 形を許可リストで検証しているのに対し、宛名側は cwd 由来の任意文字を受けるため検証できる形がありません。

`~/.claude/sessions/` は docs にも CHANGELOG にも記載の無い内部ファイルなので、subscription エンドポイントと同じ graceful degradation とし、読めなければ宛名だけを落として他の要素は出します。`session_id` が来ない旧 Claude Code ではファイルを読みにも行きません（挙動の防御は id 照合が単独で担い、このゲートは 5-9 ファイル分の read を省く性能目的）。

## セッション出自 (`branch` / `fork`)

Line 1 の黄バッジ（宛名と Version の間）は `session_name` 末尾のマーカーから読みます。`/branch` は ` (Branch)`（同じ会話から 2 本目を切ると ` (Branch 2)` の連番）、`/fork` は ` ⑂`（U+2442）。2.1.77 より前の ` (Fork)` は当時の `/branch` のエイリアスなので **branch 扱い**。両方付いた時は fork を優先します（親が並走しているほうが行動に直結する）。

**`(Branch)` 系は名前だけでは判定できません** — `/branch` は分岐した子だけでなく **元セッションの名前にも** ` (Branch)` を書き込みます（2.1.221 実測。元・子・元を resume した実体の 3 つが同名になり、元の会話に戻ってもバッジが消えませんでした）。そこで `transcript_path` の**冒頭 20 行に `"forkedFrom":{` があるか**で裏取りします — これが「本当に派生した側」の唯一の証拠です。1 行でなく 20 行見るのは、冒頭に custom-title / mode / file-history-snapshot のヘッダ記録が積まれて `forkedFrom` が 7 行目に来る transcript が実在するため（実測 23 件中 22 件が 1 行目、1 件が 7 行目）。needle の `":{` は、JSON 文字列値の中では `"` が必ず `\"` にエスケープされる性質を使っています — 生の `"forkedFrom":{` は構造上のキーとしてしか現れないので、jsonl 断片を本文に貼ったセッションでも誤爆しません。読み込みは `read` のリダイレクトなので fork ゼロ。`transcript_path` が来ない・読めない環境では従来どおり名前だけで判定します（graceful degradation）。マーカーの受理形は実測どおり `(Branch)` / `(Branch N)` に限定します — 前方一致にすると `(Branch protection rules)` のような名前が degraded path で誤爆します。

`⑂` にはこの裏取りを掛けません。`⑂` は transcript の `customTitle` には書かれず実行時の名前にだけ付くので元セッションへ伝播しません。そして **fork の子は `forkedFrom` を持ちません**（2.1.222 実測: `/fork` した子の transcript 全 47 行に 1 件も無く、`customTitle` も空）。掛ければ「出るべき fork が出ない」が確実に起きるので、branch とゲートの有無を分けるのは非対称ではなく実測どおりです。

### 元セッション id を添える (`branch:<uuid>`)

`branch` には元セッションの id を添えます。`/branch` の元は別の端末で resume されるため、戻るには id が必要です（コピーして `claude --resume <id>`）。元の transcript が消えていれば `No conversation found` になります — 手元の実測では派生した子 26 件中 3 件が既に親を失っていました。id は「戻れるかもしれない手がかり」で、常に resume できる保証ではありません。

**切り詰めずに full uuid で出します。** `--resume` は先頭 8 桁のような短縮形を受け付けません（2.1.222 実測: `Error: … "3052272d" is not a UUID and does not match any session title`。full uuid では `No conversation found with session ID:` = UUID として受理された上での不一致になり、エラーの種類が違います）。prefix 解決はどこにも無いので、短くすると「コピーできるのに戻れない id」になります。`claude attach` のほうは 8 桁を受けますが、あちらは背景セッション専用で `/branch` の元には使えません。

裏取りに使う `forkedFrom` の記録が `{"sessionId":"…","messageUuid":"…"}` の形で親 id を持っているので、**追加の I/O も fork もありません**。抽出は `}` まででスコープを閉じます — 閉じないと、`forkedFrom` が `sessionId` を持たない形（将来のスキーマ変更）で同じ行の後続キーを拾い、「元へ戻る id」が自分自身になって往復が成立しなくなります。取り出した値は許可リストで検査し（hex とハイフン以外を弾いた上で 8-4-4-4-12 の配置を見る）、通らなければ語だけの表示に落とします（拒否リストは持たない方針）。

`fork` には添えません。`/fork` の元は同じ端末に残って `←` の detach で戻れるので id が要らず、そもそも上記のとおり fork の子は `forkedFrom` を持たないため抜き元がありません。

## パフォーマンス

- **バックグラウンド更新**: Git (5秒)・Subscription 種別 (3600秒)・usage-credits (300秒) の 3 つをサブシェルで非同期更新。stale キャッシュを即座に返すため出力をブロックしない。**`( … ) >/dev/null 2>&1 & disown` の `>/dev/null 2>&1` が非同期化の必須条件** — 付けないとサブシェルが親の stdout (Claude Code が読む pipe) を継承したまま生き、読み手は最後の fd 保持者が終わるまで EOF を見ない (実測: 冷キャッシュの大リポで 50ms → 300ms、遅い `curl` で 3.1s)
- **単一 jq 呼び出し**: stdin JSON を `eval` + `@sh` で一括抽出（フィールドごとの再パースなし）
- **時刻はすべて同じゾーン・同じ書式**（既定はこのマシンのローカル TZ の 24 時間表記）。**ゾーン名は表示しない** — 例外が無いので情報が増えない（v1.78.0 で `JST 19:31` を試して v1.79.0 で撤去）
- **`timeFormat` / `timeZone` に追従する**（Claude Code 2.1.257+、v1.88.0）。本体の時計と表記をずらさないためだけの機能で、ゾーン名を出す方針は変えていない。実装の要点:
  - **設定は既存の 1 回の jq に相乗りさせる** — `--rawfile _settings <path>` で**生文字列として**渡し、`fromjson?` で開ける。`--slurpfile` だと jq が JSON としてパースするので、**壊れた settings.json で抽出が丸ごと abort し statusline が空白になる**（settings は人が手で編集するので現実に壊れる）。存在しないときは `/dev/null`（`--rawfile` は実在パスを要求し、空文字列は `fromjson?` が捨てる）
  - **読むのはユーザー設定 1 枚だけ**（`<config dir>/settings.json`）。上流の優先順位は managed > CLI > project local > project > user だが、**project 側のパスは `workspace.current_dir` に依存する = この jq が返す値**なので jq 起動前には決められない（`--rawfile` のパスは起動時に固定）。`/config` の Display 系はユーザーファイルに書かれるので実用上ここで足りる。取りこぼしても**従来どおりのローカル 24 時間表記に倒れるだけ**で、誤った書式を出す経路にはならない
  - **ゾーンは `export TZ` 1 本で通す** — `date -j` も jq の `strflocaltime`（背景 subshell が継承）も同じゾーンになるので、時刻を作る箇所ごとに引数を配らない。Line 3 の last commit も同じゾーンに乗る（git の出力は `%ct` = epoch なので TZ 非依存で、整形する `date -j` 側だけが乗る）
  - **git facts キャッシュには `tz` を入れない**（意図的）。名前は `md5(dir)` だけ、`GIT_FMT` にも `tz,tf` を持たせていない。同一リポを別 config dir（別 `timeZone`）の 2 ペインで開くと **5s の TTL の間だけ**相手のゾーンで書かれた commit 時刻を読み、5s ごとに `mv` が churn する。それでも入れないのは ① ネットワークが無く 5s で収束する ② `usage_spend` と違って「別アカウントの課金額」のような性質の値を持たない ③ タグを増やすと旧キャッシュの捨て合いが 1 つ増える、の 3 つ。再検討条件は **TTL を伸ばしたとき**
  - **不正なゾーン名は必ず落とす** — libc は不正な `TZ` を**黙って UTC にする**が、上流は Intl で検証してシステムのゾーンに戻す。落とさないと「UTC の時刻をローカルだと思って読む」= 誤読になる。判定は `/usr/share/zoneinfo/<名前>` の実在チェック（fork ゼロ）＋ **名前の形**（`..` / 先頭 `/` / 先頭 `:` を先に弾く）。**形の判定が必須** — `../zoneinfo/UTC` は実在するので `-e` を通ってしまう
  - **書式はサニタイズする** — 値はユーザー settings 由来の任意文字列で `date` の書式にそのまま渡る。`%n` / `%t` / 生の改行タブは**5 行契約を壊し**（Line 5 が 2 行に割れる）、US/RS はリセットメモのレコードを割る。上流の `stn()` と同じく落として 100 文字で切る
  - **`24-hour-utc` は `timeZone` より強い**（上流 `F0e()` が timeZone を読む前に return する）。`Z` がリセット時刻に付くので、**そこだけは表記自体が UTC を示す**（Line 3 の last commit は書式が固定なので `Z` は付かない。ゾーンは同じ）
  - **`auto` は追わない** — 上流の `auto` は locale の hourCycle に従うが、BSD の `date` に「この locale の時刻書式」を安全に出させる指定が無い（`%X` は秒まで付く）。24 時間表記の locale では現行の `%H:%M` と一致するので、**明示的に選ばれた 3 preset とパターンだけ**を追う
  - **メモとキャッシュはゾーン・書式・ロケールでキーし直す** — `resets<config dir>`（`RESET_FMT` に `tz,tf,loc`）と `usage_spend<config dir>`（`USAGE_FMT` に `tz,tf,loc`）は epoch → **表示文字列**の写像なので、**描画結果を変える入力は全部キーに入れる**（設定を変えた直後に epoch だけ一致すると古い文字列が居座り、週間枠ならリセットまで最大 1 週間）。不一致なら捨てて取り直す = 誤表示の経路が無い
  - **`loc` を入れるのは `%a` / `%A` / `%p` がロケール依存だから** — `date` も jq の `strflocaltime` も `LC_ALL` → `LC_TIME` → `LANG` の順で見るので、ここが変わると `Sat 16:00` が `土 16:00` に変わる。ゾーンと書式だけをキーにしていた版で、`LANG` を `en_US.UTF-8` から `ja_JP.UTF-8` に変えたら**週間枠だけ英語の曜日が残った**（Ghostty が入れる `LANG` を `.zshenv` で上書きした実例）。読むのは環境変数だけなので fork ゼロ
  - **`usage_spend` と `subscription` のファイル名に config dir を混ぜた**（`resets` と同じ `CFG_KEY`。`subscription` は Keychain のサービス名が config dir ごとに変わる = レコードがアカウント固有なのに共有されていて、**TTL 3600s なので取り違えが最も長く居座る**箇所だった）。`CACHE_BASE` は UID 単位なので、混ぜないと `CLAUDE_CONFIG_DIR` を分けた 2 アカウントが 1 つのレコードを共有し、① **別アカウントの `credits:$` と枠が画面に出る** ② 片方に `settings.json` が無いだけで互いに「形式違い」と判定し合い **毎レンダー curl + mv**（2 アカウント交互 8 レンダーで curl 8 回を実測）。旧 `usage_spend` は参照されなくなるが `TMPDIR` 配下なので OS の掃除に任せる
  - **失敗時の延命 `touch` は「書式が変わっていないとき」だけ** — ゾーン/書式が変わった直後に fetch が失敗すると `touch` ではレコードの `tz,tf` が古いままなので、次の描画でまた不一致になり **TTL を無視して毎描画 curl = storm**（Wi-Fi 断中に `/config` で Time format を変えると踏む）。この場合だけ「読めた cents + 新しい tz/tf + 枠 0 件」で書き直して不一致そのものを解消する。**古い書式の枠は持ち越さない**（違う書式の時刻を並べると誤読）
  - **不正なゾーンの判定は実在チェックだけでは足りない** — `-e` はディレクトリ（`America` / `Asia`）もゾーンでない実ファイル（`zone.tab` / `iso3166.tab` / `+VERSION`）も通し、libc はどれも解釈できず黙って UTC に落ちる（実測でローカル 12:23 が 03:23 になった）。**先頭 4 バイトの `TZif` マジック**で判定する（`read -r -n 4` なので fork ゼロ。ディレクトリは `read` が失敗して空になるので同時に弾ける）
  - **書式のサニタイズは出力側にも必要** — 入力側の禁止リストは strftime の修飾子に追いつけない。`${tf//%n/}` は 1 パスの非重複置換なので `%%nn` が `%n` に化け、BSD strftime は `E`/`O` 修飾子を受けるので `%En` / `%Ot` が改行タブになる（どちらも実測で 5 行が 6 行になった）。最後の砦は `format_reset` と背景 jq の**出力**から制御文字を落とすこと
  - **`fromjson?` だけでは足りず `| objects` が必須** — `?` が吸うのは構文エラーだけなので、`[]` / `"x"` / `5` のような**有効な JSON で object でない値**は通り抜け、`$cfg.timeFormat` が `Cannot index array` で rc=5 = 抽出が丸ごと死ぬ（実測で Line 1 が `jq error`、5 行が 3 行になった）。`--rawfile` はディレクトリで rc=2 abort するので、gate は `-r` ではなく `-f` + `-r`
- **共有タイムスタンプは jq から取る** (v1.82.0): `_NOW` は既に 1 回だけ走っている jq の `now|floor` から受け取り、`date` は 1 個も起動しない (実測 -3.0ms、中央値。UTC epoch なので TZ 非依存)。取れなかったときだけ `date +%s` に落ちる — `_NOW=0` のままだと `cache_stale` は安全側 (「古くない」) に倒れるが、リセットの `now` 判定と commit age が誤表示になる
- **mtime はまとめて 1 回の `stat` で取る** (`prefetch_mtimes`、v1.81.0): 鮮度を見るキャッシュは 3 つ (git / subscription / usage-credits) あり、`cache_stale` がそれぞれ `stat` を fork していた (実測 9.802ms → 3.146ms = **-6.7ms**、暖まった描画の 16%)。`stat -f '%N %m'` の出力（「パス 空白 mtime」の行）を**そのまま表として持ち、行頭でキーを引く** — パスを出さずに `%m` だけ並べると、欠損ファイルがあると行がずれて**別ファイルの mtime を読む** (実測で確認: 中央を欠損させると 3 番目の値が 2 番目に入る)。まとめ取りに無いファイルは従来どおり個別 `stat` に落ちる
- **hot path では here-string (`<<<`) を使わない**: bash 3.2 では一時ファイルを作るので、`read` への 1 回が実測 1.679ms (パラメータ展開なら 0.083ms)。`render_git` のレコード分解はパラメータ展開のループにする。**stdin は変数に読まず jq に直接継承させる** — 変数に読むと渡し直す口（here-string = 一時ファイル / プロセス置換 = subshell）が必要になるが、`$( )` は stdin を継承するのでどちらも要らない。背景 subshell の中（`build_git` / 各 fetch）は毎描画の予算に乗らないので `<<<` を残している
- **キャッシュ**: `${TMPDIR:-/tmp}/claude-statusline-$UID/{git/<md5>,subscription,usage_spend,resets*}`（**形式の判定はレコード先頭の形式タグ**＝フィールド一覧そのもの。一致しなければ値を捨てて即取り直す。ファイル名に版を持たせないので孤児が出ない。v1.77.0） (mkdir 700、親も含めて owner-only) に保存。`CLAUDE_STATUSLINE_CACHE_DIR` で差し替え可 (テスト密閉の seam)。固定の共有パスは共有 Mac で書けず curl storm になるため v1.52.0 でユーザー単位に変更
- **未追跡の行数には件数上限 (500)**: 数えるコストは未追跡の**総バイト数**に比例するので、`node_modules` などを無視設定に入れていないリポ (実測 30,000 件で **5.17 秒**) では `GIT_CACHE_MAX_AGE=5` を超えて「書き終えた時点で既に stale」= 毎レンダー全走査 + 背景 job の積み上がりになる。超えたら未追跡ぶんを数えない (途中までの合計は「間違った数」なので要素ごと落とす)。**上限は件数なので近似指標**（コストはバイト数側）
- **最新版の取得はローカル読みだけ**: Claude Code 自身が `<config dir>/cache/changelog.md` に changelog をキャッシュしているので、その冒頭の `## X.Y.Z` を読めば最新リリースが分かる (ネットワーク・キャッシュ書き込み・fork すべてゼロ)。**読む行数に上限 (20 行)** — 見出し形式が変わった瞬間に 513KB を毎レンダー読み切り、描画が実測 42ms → 110-121ms になる (上限つきなら 41ms)
- **Git worktree 対応**: stdin JSON の `worktree.name` または `workspace.git_worktree` (Claude Code 2.1.97+) を検出して 🌲 を表示。`.claude/worktrees` 配下ではパスをリポ root で切り worktree 名を 🌲 直後に表示（パス末尾のランダム名でリポ dir が埋まるのを防ぐ）

## Line 4 / Line 5: セッション と アカウント

**Anthropic** (rate_limits が届く場合)
- Claude Code 2.1.80+ の stdin JSON `rate_limits` フィールドから直接取得
- 表示は **2 行**: **Line 4 (このセッション)** = コンテキストバー + % + 分母 → セッション経過時間(単位1つ `41m`/`4h`。**画面で唯一の相対表記** — 時刻ではなく期間なので絶対時刻と混ざらない。**実体は「このセッションを開いてからの壁時計」でアイドル時間を含む** — 上流は `Math.max(0, Date.now() - <ledger 開始>)`、docs も "Total wall-clock time since the session started"。実働時間は `cost.total_api_duration_ms` 側なので、この値を「Claude が働いていた時間」と読ませない) → セッションコスト → プロンプトキャッシュ（**`warm`/`cold` と `hit_ratio` の 2 つだけ**。上流 docs 自身が「短い status line は 1〜2 個で、`warm` と `hit_ratio` が状態を最も直接に要約する」と書いており、操作が変わるのはこの 2 つだけ。残る 10 項目は累計か静的値で、金額は `$` で既に見え、詳細は `/usage` の `Prompt cache (main)` 行が持つ。**`expires_at` を出さない**のは ① 上流が `max(lastRequest.at, touchedAt) + ttl` で毎リクエスト前へずらすので cold のとき過去の時刻が「これから切れる」と読める ② 同じ理由でメモが当たらず毎描画 `mv` を 1 個増やすだけだった実測がある、の 2 つ。時刻を出さないので **`date` fork はゼロ**）。**Line 5 (アカウント)** = 5hバー + % + リセット時刻(`19:31`、曜日なし) → week:% + リセット(`土 16:00`、曜日つき) → モデル別週間枠 → usage-credits実課金（**モデル別枠は 0% を出さない** — `week:` が `> 0` で 0 を落とすのと揃える。上流は 2.1.236 で「まだ何も使っていない枠」も返すようになった）
- **リセット時刻はメモ化する** — epoch は次のリセットまで動かないので `${CACHE_BASE}/resets<config dir>` に `epoch US 表示文字列` を持ち、epoch が一致する限り `date` を呼ばない（実測 `date -j` 1 回 4.15ms。呼び出しは 1 描画 3 回 → 1 回。なお**残っていた「制限あり/なし 約 8ms」の差はメモ化漏れではなく `stat` の 3 回 fork**で、v1.81.0 のまとめ取りで消えた。描画時間の絶対値は同時に動いている処理で振れるので、回帰は新旧の交互 A/B で見る）。使用率は使うたび変わるのでメモしない。**epoch 一致時しか cache の値を使わない**ので誤表示の経路が無く、ファイル名に config dir を混ぜて複数アカウント併用時の書き合いを避ける
- **スコープで行を分ける**（v1.74.0）。1 行に混在していた頃は 7 要素・弱め表示が 7 割で「どこまでが制限の話でどこからがこのセッションの話か」が読めなかった。特に週間リセット（dim の時刻）の直後にセッション経過（dim の時刻）が並び、経過が「週間制限の続き」に見えて属し先が消えていた。区切り記号を足すのではなく意味の境界で行を割った。**セッション行を上（4 行目）**に置くのは毎ターン変わるのがこちらだから（制限は数時間〜1 週間単位）。`credits:` は枠を超えた分の課金なのでアカウント行、セッションコストはこのセッションの API 換算額なのでセッション行
- Pre-2.1.80 ではレート制限部分が非表示（graceful degradation）

**Bedrock / Vertex AI / Foundry**
- `rate_limits` フィールドは届かないため、コンテキストバーとコストのみ表示（usage-credits も Anthropic 限定なので非表示）

**モデル別の週間制限** (`Fable:39% 土 16:00`、Anthropic のみ)
- **stdin には来ない** — docs の完全 JSON スキーマで `rate_limits` は `five_hour` と `seven_day` の 2 つだけ。モデル別の枠は `/usage` レスポンスの `limits[]` にある（`credits:$` と同じ curl の結果なので**追加のネットワークも fork もゼロ**）
- 実測した要素の形: `{"kind":"weekly_scoped","group":"weekly","percent":39,"severity":"normal","resets_at":"2026-08-15T07:00:00.346608+00:00","scope":{"model":{"id":null,"display_name":"Fable"}},"is_active":true}` — claude.ai の「週間制限 / Fable / 39% 使用済み」と一致
- **読むのは `limits[]` だけ** — レスポンスのトップレベルには `nimbus_quill` / `amber_ladder` / `tangelo` / `iguana_necktie` 等のコードネーム鍵があるが feature flag 名で churn するので使わない。`limits[]` は消費者向けに整形済み
- **`is_active` / `severity` で絞らない** — 各 1 観測しかなく意味論が不明（未文書フィールドを列挙する罠）
- **`resets_at` は ISO8601 文字列**で epoch ではない。jq の `fromdateiso8601` は小数秒（`.346608`）と `+00:00` オフセットを受け付けないので剥がしてから渡し、`?` と `// ""` で形式が変わった枠だけ落とす
- **リセット時刻は背景側で表示文字列まで作る** — epoch をキャッシュして描画側で `format_reset` を呼ぶと **枠 1 つあたり `date` 1 fork** がレンダーごとに乗る（枠は複数ありうるうえ `refreshInterval` で 30s ごとに再実行される。値は 300s しか変わらない）。`strflocaltime` の出力は `date -j -r EPOCH +"%a %H:%M"` と一致する（`Sat 16:00` / `土 16:00` の両方で実測）。これで `render_scoped_limits` は **fork ゼロ**
- **分単位に丸める** — `resets_at` は毎リクエスト再計算されて**分境界をまたぐ**（実測: 同じリセットが `06:59:59.987654+00:00` と `07:00:00.155204+00:00` の両方で返る）。切り捨てだけだと表示分が `15:59` / `16:00` で揺れ、300s キャッシュのたびに変わる。表示は `%H:%M` なので分丸めが必要な精度そのもの。stdin 由来の `week:` は安定した epoch が来るのでこの問題は無い
- **`display_name` に空白が入ると 2 語のトークンになる**（`Opus 5:12%` — 後半の語が `:12%` を抱える）。宛名でやったダブルクリック選択の条件は満たさないが、コピーして使う値ではないので許容している（表示専用）
- **型ガードを通す** — 1 枠の型不正で jq が abort すると同じ jq が運ぶ cents まで消える（subagent の全 abort と同じクラス）
- 表示は `Fable:39%`。**モデル名は Line 1 と同じ `model_color`**（Fable なら FABLE_PAL の多色、flat 色のモデルはその色）。`:39%` は無色の通常輝度（数値が沈むため dim は却下）、リセット時刻は `week:` と同じ dim — どちらも週間制限で二次情報という位置づけを揃える
- 全体の週間制限（stdin の `seven_day`）と**併存**する。別の制限なので置き換えない
- 再検討条件は **stdin が per-model の `rate_limits` を渡してきたとき**（`/check-claude-code-update` の確認項目に入れてある）

**usage-credits 実課金** (`credits:$X.XX`、gold `38;5;220`、Anthropic のみ)

- `fetch_usage_spend()` が `/usage` OAuth エンドポイント (`api.anthropic.com/api/oauth/usage`) の `spend.used` を取得 — **stdin に無い唯一の課金情報**で、usage-credits の実消費額（参考値の session cost と別物）
- **このスクリプト唯一のネットワーク呼び出し**。背景 subshell + 300s キャッシュで hot path をブロックしない。OAuth トークンは `curl -H @-`（stdin）で argv 非露出
- Fable は 7/7 以降 usage-credits 課金に移行するため「実際に溶けた額」を出す実益が大きい
- データ無し / 取得失敗 / `$0.00` は非表示。`CLAUDE_STATUSLINE_NO_NET=1` で fetch 自体を無効化（オフライン / プライバシー）。エンドポイントは非公式なので変わりうる前提の graceful degradation

> 画面のラベルは `credits:` です。上流は Claude Code 2.1.144 で "extra usage" を **"usage credits"** に改名し（`/extra-usage` → `/usage-credits`）、以後の CLI コピーは全部そちらなので、画面の語彙をそちらに合わせています。**`/usage` の応答側の鍵名は今も `extra_usage`** なので、API を読むときの綴りと画面の語彙は一致しません。

**セッションコスト** (`$X.XX`、通常輝度、最右)
- stdin JSON `cost.total_cost_usd` をそのまま表示。Claude Code がキャッシュ区分 (cache read/write) 込みで計算済みの API 換算額
- subscription (Max 等) 利用時は実請求ではなく参考値 — 優先度の低い情報として最右に置く (色は付けない。v1.55.0 で dim をやめ通常輝度へ)
- `$0.00` (セッション開始直後) とフィールド欠落 (旧 Claude Code) では非表示
- トークン数は引き続き非表示（Claude Code の `total_input_tokens` がキャッシュトークンを含まず誤解を招くため）

## クラウドプロバイダー検出

| プロバイダー | 検出条件 |
|---|---|
| Bedrock | `model.id` プレフィックス (`global.`/`jp.`/`us.`/`us-gov.`/`eu.`/`au.`/`apac.`) or `CLAUDE_CODE_USE_BEDROCK=1` or `CLAUDE_CODE_USE_MANTLE=1` |
| Vertex AI | `CLAUDE_CODE_USE_VERTEX=1` |
| Foundry | `CLAUDE_CODE_USE_FOUNDRY=1` |
| Anthropic | 上記以外 |

### プラン名とレート枠 (`Anthropic(Max 5x)`)

Anthropic 直接利用のときだけ、`fetch_subscription()` が Keychain（fallback は securestorage ディレクトリの `.credentials.json`）の `claudeAiOauth` から 2 つを **1 回の jq** で取り、US 区切りで 3600s キャッシュする。

**Keychain のサービス名は設定ディレクトリごとに変わります。** 名前は `Claude Code-credentials` に、設定ディレクトリの sha256 先頭 8 桁を `-` で付けた形です（suffix の元は `CLAUDE_SECURESTORAGE_CONFIG_DIR` が定義済みならその値、未定義なら `CLAUDE_CONFIG_DIR` の値。どちらも空／未設定なら suffix 無し）。docs も CHANGELOG も触れていない挙動で、2.1.238 のバイナリで実測しました。上流は env の値を NFC 正規化してから hash し、パスの解決や末尾スラッシュの除去はしません（＝相対パスでも綴りが同じなら一致します）。読み出しは account 属性込み（`security find-generic-password -s <名前> -a <ユーザー> -w`）です。

帰結として、**`CLAUDE_CONFIG_DIR` を設定して走るセッションでは、その設定ディレクトリ専用の Keychain 項目が必要**になります。無い場合はプラン名と `credits:$` が出ません（決め打ちの名前で引いて既定アカウントの値を出す方が危険なので、算出できないときは Keychain ごと飛ばします — 無表示 < 誤読）。

| フィールド | 用途 | 実測値 |
|---|---|---|
| `subscriptionType` | 契約種別 → 公式プラン名に畳む | `pro` / `max` / `team` / `enterprise` |
| `rateLimitTier` | レート枠 → suffix が `Nx` なら添える | `default_claude_max_5x` / `default_claude_max_20x` / `default_claude_ai`（Pro 相当、`Nx` 無し）/ 欠損 |

公式プラン名は Free / Pro / **Max 5x** / **Max 20x** / Team / Enterprise（[claude.com/pricing](https://claude.com/pricing)、[Max プラン](https://support.claude.com/en/articles/11049741-what-is-the-max-plan)）。生値は小文字なので `plan_label`（lib.sh、fork ゼロ）が畳む。

- **`rateLimitTier` の値は列挙しない** — 未文書フィールドなので suffix が `Nx` の形かだけを見る。`default_claude_ai` は枠なしに落ち、未知の `50x` や prefix 変更でも動く
- **枠は契約種別と独立** — 実測で Enterprise 契約が `default_claude_max_5x` を持つ（契約は Enterprise、レート枠は Max 5x 相当）。Team/Enterprise 専用の値を知らなくても壊れない
- 未知の契約種別は生のまま出す（graceful degradation）。credentials が読めなければ `Anthropic` だけ
- 旧形式キャッシュ（1 フィールド）を読んでも契約名だけ出て枠が空になるので、ファイル名の版は上げていない
