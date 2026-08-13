# Changelog

## [1.70.0] - 2026-08-13

### Changed

- Built against を Claude Code 2.1.229 に追従（1.69.0 と同日リリース）。契約面の変更なし — stdin JSON・subagent per-task 13 フィールド・statusLine 設定（`padding` / `refreshInterval` / `hideVimModeIndicator`）とも 2.1.226 から不変で、docs の版ゲート注記も最新が 2.1.214 のまま。2.1.227〜2.1.229 で関連キーワードに当たった 6 件はいずれも無関係（Vertex/Bedrock の SSE keepalive、MCP OAuth の redirect URI を `127.0.0.1` へ、self-hosted runner の git credential、`/login` の `CLAUDE_CODE_OAUTH_TOKEN` 警告、cross-session message の送信者表示）。2.1.229 の「`ListAgents` が切断中の Remote Control セッションを `offline`、クラウドセッションを `cloud` と表示」は一覧表示側の変更で、宛名として読む `~/.claude/sessions/<pid>.json` の `name` / `nameSource` には影響しない（1.69.0 の実測はこの版で取得済み）。1.68.0 から持ち越していた 2.1.221「rename 経路のセッション名 sanitize」はマーカー実測（`(Branch)` / `⑂`）への影響を要観察のまま継続

## [1.69.0] - 2026-08-13

### Changed

- Version (`v2.1.x`) を Line 1 の**最後**へ移動（従来は Agent 名の直後）。Claude Code 自体の版は「今このセッションで何をするか」に効かない参照情報なので、モデル / effort / 宛名 / 出自といった行動に効く要素を先に読ませる。溢れて truncate されるとき最初に削られてよい要素でもある（`…` は末尾から効く）

### Added

- Line 1 に宛名 — cross-session messaging（`SendMessage` / `ListAgents`、2.1.224+）でこのセッションを指すアドレスを常時表示。`~/.claude/sessions/<pid>.json` の `name` を stdin の `session_id` で照合して読む。**アドレスは session id でも右上のタイトルでもなく cwd 由来の derived name**（2.1.229 実測: customTitle が `v2について` のセッションでも `name` は `my-project-b6` / `nameSource` は `derived` のまま）。タイトルは 2 系統あり `aiTitle` が Claude Code の自動生成（会話内容から、直近 40 transcript で 26 件）・`customTitle` が `/rename` と `/branch <名前>` によるユーザー由来（14 件）で、**どちらも会話内容由来**なので cwd 由来の宛名と食い違う = **宛名はどこにも出ていなかった**。同一リポで複数セッションを開くと suffix だけが違う（実測 `…-my-project-41` / `-5c`）ので、どの端末がどれかは宛名を見ないと判別できない（ただし resume で pid が変わると suffix も変わるため固定 ID ではない。実測 `…-74` → `-1d`）。**`/branch <名前>` の形では出さない** — これは `customTitle` と `name` の両方にその名前を書き、このとき `nameSource` キー自体が消えるので、右上と宛名が同じ文字列になる（`"nameSource":"derived"` の明示がある時だけ出す許可リストで切り分ける。messaging 自体が 2.1.224+ なのでキー不在の古い版で出す意味は無く、倒すと `/branch <名前>` で誤表示する）。記号も囲みも付けないので、要素間のスペースが単語境界になりダブルクリックで名前だけ選択できる（`@` は境界文字でないため記号ごと選択されて貼り付けに手間が出る。`branch:<uuid>` 側は `:` が境界かつ `-` が非境界なので対応不要）。読み取りは fork ゼロ（glob + `read` のリダイレクトのみ、実測 1.2ms / `grep` 版 5.9ms）なのでキャッシュを持たない。`~/.claude/sessions/` は docs にも CHANGELOG にも無い内部ファイルなので、読めなければ宛名だけ落として他は出す graceful degradation

## [1.68.0] - 2026-08-10

### Changed

- Built against を Claude Code 2.1.226 に追従。契約面の変更なし — stdin JSON・subagent per-task 13 フィールド・statusLine 設定（`padding` / `refreshInterval` / `hideVimModeIndicator`）とも 2.1.222 から不変で、スクリプト変更は無い。docs の版ゲート注記は最新でも 2.1.216（resume 時の二重実行の修正で、契約ではない）。2.1.223 の「gateway が `bedrock/anthropic.claude-*` / `vertex_ai/claude-*` 形の model id を隠していた不具合の修正」は、そうした id が来ても `model_key` の tier 部分一致で色は正しく出るので無対応とした（provider バッジだけ Anthropic に落ちる。`model.id` にこの形が来た実測がなく、同じ版の `modelOverrides` 修正は canonical id への正規化を示唆するため。再検討条件は実測でプロバイダ接頭辞形の `model.id` を観測したとき）。2.1.224 の `ANTHROPIC_BEDROCK_REGION_PREFIX` も、値が既にカバー済みの region prefix 群で `CLAUDE_CODE_USE_BEDROCK=1` と併用される前提なので無対応。2.1.221 の「rename 経路のセッション名 sanitize」はマーカー実測（`(Branch)` / `⑂`）への影響を要観察のまま持ち越し

## [1.67.0] - 2026-08-05

### Added

- `branch` バッジに元セッションの id を添える（`branch:3052272d-8e61-4a0c-a506-bfd8d3206d73`）。`/branch` の元セッションは別の端末で resume されるので、この id をコピーして `claude --resume <id>` で元の会話へ戻れる（元の transcript が残っている場合。実測では派生した子 26 件中 3 件が既に親を失っていた）。裏取りに使う transcript の `forkedFrom` 記録が親 id を持っているため、追加の I/O も fork も無い。**id は切り詰めない** — `--resume` は先頭 8 桁のような短縮形を `is not a UUID and does not match any session title` で弾き、prefix 解決をどこにも持たない（full uuid では `No conversation found with session ID:` = UUID として受理された上での不一致になり、エラーの種類が違う。2.1.222 実測）ので、短縮すると「コピーできるのに戻れない id」になる。`fork` には添えない — `/fork` の元は同じ端末に残り `←` の detach で戻れるうえ、fork の子は `forkedFrom` を持たない（2.1.222 実測: 子 transcript の全 47 行に 0 件）。逆方向（元 → 先の id）は出さない: 全 transcript の逆引きが実測 721ms で hot path に載らず、子が複数ありうるため 1 つに絞れず、fork の子は逆引きでも見つからない。1.66.0 と同日リリース

### Changed

- README の Installation に「動作確認」を追加し、Development の冒頭がコントリビュータ向けであることを明記。インストールを依頼された coding agent が、README で唯一コピペ可能な実行コマンドである `bats test.bats` に引き寄せられ、bats 未導入・bash 3.2 のみの環境で「インストールは成功しているのに失敗したように見える」事例が報告されたため。副作用が無くインストールの成否を実際に示す fixture 流し込み 1 行を、検証手段として Installation 側に置いた

## [1.66.0] - 2026-08-05

### Changed

- Built against を Claude Code 2.1.222 に追従（1.65.0 と同日リリース）。契約面の変更なし — stdin JSON・subagent per-task 13 フィールド・statusLine 設定とも 2.1.220 から不変で、スクリプト変更は無い。2.1.222 の「`/fork` が親の checkout ではなく自前の worktree を作る」変更を受けて README の fork バッジ注記を版条件付きに更新済み（`9c8fe4f`）。2.1.221 の「session names from every rename surface are now sanitized」はマーカー実測（`(Branch)` / `⑂`）への影響を要観察

## [1.65.0] - 2026-08-05

### Fixed

- **元の会話に戻っても `branch` バッジが消えなかった**のを修正。`/branch` は分岐した子だけでなく**元セッションの名前にも** ` (Branch)` を書き込むため（2.1.221 実測。元・子・元を resume した実体の 3 つが同名 `… (Branch)` になる）、名前のマーカーだけでは「本当に分岐した側」を見分けられなかった。`transcript_path` の冒頭 20 行に `"forkedFrom":{` があるかで裏取りするようにし、元セッションではバッジを出さない。1 行でなく 20 行なのは、冒頭に custom-title 等のヘッダ記録が積まれて `forkedFrom` が 7 行目に来る transcript が実在するため（実測 23 件中 1 件）。needle が `":{` 付きなのは、JSON 文字列値の中では `"` が必ずエスケープされるので生の並びが構造上のキーとしてしか現れないため。読み込みは `read` のリダイレクトなので fork は増えない。`transcript_path` が来ない環境では従来どおり名前だけで判定する
- **2 本目以降の分岐 (`(Branch 2)`) でバッジが出なかった**のを修正。同じ会話から複数回 `/branch` すると連番が付く（2.1.220 実測）が、`(Branch)` の完全形しか見ていなかった。マーカーの受理形は実測どおり `(Branch)` / `(Branch N)` に限定し、`(Branch protection rules)` のような名前が transcript を読めない環境で誤爆しないようにした

### Note

- `/fork` の `⑂` には裏取りを掛けない。`⑂` は transcript の `customTitle` には書かれず実行時の名前にだけ付くので元セッションへ伝播せず、かつ fork の子が `forkedFrom` を持つ保証が実測で取れていないため、掛けると「出るべき `fork` が出ない」副作用のほうが重い

## [1.64.0] - 2026-08-04

### Fixed

- **OSC 8 ハイパーリンクの URL に区切り文字が生で入っていた**のを修正。`osc8` が URL 側の `%` `;` `#` `?` を percent-encode する（表示テキストは素のまま）。`;` は OSC 8 の `OSC 8 ; params ; URI ST` のパラメータ区切り、`#`/`?` は URI の fragment/query 区切りで、どれも git のブランチ名と macOS のパスには入りうる — `#` は特に「無言で別の対象を開く」（`/Users/x/notes#1/repo` が `/Users/x/notes` になる）。`%` を**最初に**処理するので `feat/a%3Bb` が `feat/a;b` に畳まれて別ブランチを指すこともない。空白と非 ASCII は現に動いているので生のまま（壊れた実測が出たら対象に足す）。外部レビューでの指摘
- **`install.sh --dry-run` が settings.json とその親ディレクトリを作っていた**のを修正。未初期化のときだけ起きるが、「差分を見せて確認するまで一切書き込まない」という install.sh の約束を `--dry-run` 自身が破っていた。設定の中身を変数で持ち回す形にして、実書き込みの経路（`cp -p` / `stat` が実ファイルを要求する）でだけ作る

## [1.63.0] - 2026-08-04

### Fixed

- **背景更新がレンダーをブロックしていた**のを修正。`( … ) & disown` だけでは背景化にならず、subshell が親の stdout（= Claude Code が読む pipe）を継承したまま生きるため、**読み手は最後の fd 保持者が終わるまで EOF を見ない**。`>/dev/null 2>&1` が背景化の必須条件で、3 箇所すべてに必要だった。実測で冷キャッシュの大リポ 300ms → 50ms、遅い `curl`（`-m 4` は最大 4 秒粘る）3.1s → 50ms。CLAUDE.md が掲げていた「statusline 出力を絶対にブロックしない」が実は成立していなかった。内側の `> "${_gc}.tmp-$$"` では足りない（問題は subshell が fd を保持し続けること）
- **サブスクリプション種別が取れない環境で毎レンダー Keychain 読みが走っていた**のを修正。`fetch_subscription()` は値が取れないときキャッシュを書かなかったため、`cache_stale` が「ファイル不在 = stale」と判断して再取得を繰り返していた。credentials を持たない API キー / env 運用のユーザーが恒常的に踏む。extra-usage 側と同じ「取れなくても必ず書く」不変条件を適用した（空を書いても表示は非表示に倒れる）
- `install.sh` が**空白や glob 文字を含む clone 先で壊れ、同時に正当なパスを拒否していた**のを修正。`{a,b}` の brace 展開や `*` の glob は素通りして「試走は通るのに登録すると真っ白」になり、逆に `~/Documents/Projects (old)/` のようなパスは拒否していた。拒否リストを足すのではなく `printf %q` で引用し、発生条件そのものを消した
- `install.sh` が**自分自身の登録を「別のツール」と誤警告していた**のを修正。判定をスクリプト名で行い、`printf %q` の引用や README 主経路の `~/…` 形でも自分の登録と認識する
- `install.sh` の試走がユーザーの実キャッシュ（`$TMPDIR/claude-statusline-<uid>/git/`）にエントリを作っていたのを修正。`CLAUDE_STATUSLINE_NO_NET=1` は git キャッシュには効かないため、試走専用の `mktemp -d` に隔離した
- 読めない `~/.claude/.credentials.json`（root 所有 / mode 000）で stderr にエラーが出ないよう、gate を `-f` から `-r` に変更した

### Added

- **`/fork` した複製セッションを Line 1 に `fork`（黄）で表示**し、`/branch` の `branch` と出し分けるようにした。Claude Code 2.1.220 実測で `/fork` は session_name 末尾に `⑂`（U+2442）を付ける（`(Fork)` は付かない）。`fork` が出ているときは親セッションが並走しているので、作業ディレクトリを共有していれば Line 3 の変更が自分のものとは限らない、という警告として読める。2.1.77 より前の `(Fork)` は現行 `/branch` のエイリアスなので `branch` 扱いにする。両マーカーが付いた場合（`/branch` した会話を `/fork` した `foo (Branch) ⑂`）は fork を優先

### Changed

- OAuth トークンの受け渡しを `curl --config -` から **`-H @-`** に変更した。`--config` は各行を設定ディレクティブとして解釈するため、改行を含むトークンが `output = <path>` の注入になりえた。`-H @-` なら各行は必ずヘッダなので構造的に化けず、字種の拒否リストが不要になる（argv 非露出は維持）
- README の主経路を「固定 clone 先 `~/.claude/statusline` + `settings.json` に 2 キーをコピペ」に変更した。`command` はシェル経由で実行される（docs: "The `command` field runs in a shell"）ため `~` は展開され、**「絶対パスでないと動かない」という旧 README の前提は誤りだった**。Installation 章は 119 行から 26 行になり、`install.sh` は「settings.json を自分で触りたくない人向け」の補助として折りたたみに移した

## [1.62.0] - 2026-07-29

### Fixed

- **最終コミットが 7 日以上前のリポで Line 3 がブランチ名だけになっていた**のを修正。`build_git()` は 7 日超（`604800` 秒）で `age` を空にしていたが、`render_git()` の gate が `[[ -n "$age" && -n "$msg" ]]` と `elif [[ -n "$age" ]]` の 2 本しかないため、**`age` が空だと `msg` も連鎖して落ちていた**。`msg` は計算・20 字切り詰め・キャッシュまでされてから捨てられていた。安定リポ・アーカイブ・他人のリポを読む時に「コミットが無いのか古いだけなのか」も区別できなかった
- `render_git()` に gate を足すのではなく、**空の `age` が生まれる条件そのものを消した** — `w`（30 日未満）/ `mo`（365 日未満）/ `y` を足し、どの古さでも `age` を必ず埋める。facts/presenter 分離（v1.53.0）で「3 パス問題」を構造的に解消したのと同じ方針
- commit age の単位は引き続き常に 1 つ（`41m` / `4h` / `2d` / `2w` / `2mo` / `1y`）。Line 4 の経過（`41m` / `4h`）とは 24 時間以降で分かれる（経過は `27h` のまま丸めない）

## [1.61.0] - 2026-07-29

### Added

- **サブエージェント行に effort を表示**（Claude Code 2.1.214+ の per-task `effort`、`EFFORT` light purple でモデルの直後）。**セッションの effort を継承している行では payload 側が absent** なので、出るのは「このサブエージェントだけ effort が違う」時だけ — 安いエージェントに `low` を割り当てた時などが一目で分かる
- 値はレベル文字列（`low`/`medium`/`high`/`xhigh`/`max`）か**数値のトークン予算**の両方が来るので、数値は `fmt_ctx_size` で `8k` 形に畳む

### Changed

- **`effort` を「スパースだから不採用」としていた判断を撤回した**。撤去済みの context% / 経過（v1.51.0）は**全行に出て値が揃う**から情報量が無かったのに対し、`effort` は**違う時だけ出る**ので差分そのものがシグナルになる。同じ「スパース」という言葉で両者を却下していたのは、測るべき性質を間違えていた
- `effort` 抽出に**型ガード**を入れた（`if type == "string" or type == "number"`）。非スカラーは空に倒すので、生 JSON が行に出ない。ネストした `{"level":..}` 形で来た場合も `level` を拾う（主 statusline の `effort.level` と同形のため）
- `effort` の数値は `10#` で明示基数指定して畳む（`08000` のようなゼロ埋めを 8 進数と解釈して `0` を出していた）
- **`effort` だけでは行を上書きしない** — 説明も名前もモデルも無い task で effort だけ出すと「effort 語だけの行」になり、Claude Code 既定描画（`名前 · 説明 · トークン数`）より情報が減るため

### Fixed

- `docs/internals.md` のセッションコストの輝度記述が 1 箇所だけ `dim` のまま残っていた（v1.55.0 で通常輝度に変えた分の取りこぼし）。3 箇所すべてをコードに合わせた
- 行レイアウトの記述を `subagent-statusline-command.sh` と `test.bats` のヘッダコメントにも反映（README / `docs/internals.md` だけ直して in-repo のコメント 2 箇所を落としていた）

## [1.60.0] - 2026-07-29

### Changed

- **セッション経過時間の表記を単位 1 つに変えた**（`4h01m` → `4h`）。旧版は 1〜24 時間の帯だけ分をゼロ埋めしており、**同じリポの中で時間表記が 3 つ**あった: Line 3 の commit age は `4h`、Line 4 の経過は `4h01m`、Line 4 の 5h リセット残は `4:01`。`fmt_elapsed` は自分のコメントで「Line 3 の commit age と同じコンパクト表記」と主張していたのに、まさにその帯だけ食い違っていた
- `4h01m` の**分のゼロ埋めは業界慣行のどれとも一致しない**（k8s `4h1m` / Go `4h1m0s` / starship `4h 1m`）。用途は「何時間回してる?」なので時未満の分は判断に効かない
- **H:MM (`4:01`) は採らなかった** — `uptime`/`top` の標準ではあるが、同じ Line 4 の 5h リセット残が既に `4:01` なので**同じ行に `4:01` が 2 個並び、残りと経過が区別できなくなる**
- 表記: `41m` → `41m`（変化なし）/ `4h30m` → `4h` / `27h` → `27h`（変化なし）。分岐が 3 本から 2 本に減った

## [1.59.0] - 2026-07-29

### Changed

- **モデル色のサポート下限を 4.x に定めた**。3.x 系は Anthropic API から全廃止済み（Sonnet 3.5 = 2025-10-28、Opus 3 = 2026-01-05、Sonnet 3.7 / Haiku 3.5 = 2026-02-19、Haiku 3 = 2026-04-19）で、Claude Code 自身も Opus 4 / 4.1 を pin したユーザーを 4.6 へ自動移行させる。存在しないモデルのために `model_key` が**毎レンダーの最初に**旧形式専用の正規表現（版が tier より前、`claude-3-5-sonnet-…`）を評価していたのをやめた
- 下限未満のモデルは **generic tier 色に落ちるだけで無色化も文字化けもしない**ので、Bedrock で古い inference profile を pin していても壊れない。唯一の実害は Sonnet 3.5 が amber ではなく teal になること
- **正規形を常に `tier N[.N]` に揃えた**。minor を持たない tier の dated id（`claude-opus-4-20250514` / `claude-opus-5-20260101`）では第 2 キャプチャが `-20250514` になり、正規形が `opus 4.20250514` という非正規な形になっていた。5 桁以上を日付とみなして捨てるので、同じモデルが `display_name` 形でも dated id 形でも同一キーに畳まれる。これで `model_color` の arm は完全一致 1 行で足り、「**新モデルはパレット 1 行 + arm 1 行**」という docs の約束が実際に成立する（従来は dated な 5 系が静かに generic 単色へ落ちる危険があり、それを検出するテストも無かった）
- 日付付きの現行 id（`claude-haiku-4-5-20251001` / `claude-sonnet-4-5-20250929`）が版として正しく畳まれること、dated な 5 系が多色 arm に着地することをテストで固定した

### Removed

- `model_color` の amber arm から `"sonnet 3.5"` を削除（`"sonnet 4.5"` のみ）

## [1.58.0] - 2026-07-27

### Changed

- **モデル tier の判定を `model_key` による正規化に置き換えた**。`model_key VARNAME MODEL_SHOW [MODEL_ID]` が display_name / model id / Bedrock inference-profile / 旧形式（版が tier より前）を `opus 5` / `sonnet 4.5` / `fable` / `""` の正規形に畳み、`model_color` は**その完全一致**で分岐する。旧実装は 4 tier に **15 個の glob** と「5 世代を generic より前に置く」暗黙の順序で成り立っており、次に `Haiku 5` や `Opus 6` を足すときスペース形（`"opus 6"`）とダッシュ形（`"opus-6"`）の両方を正しい位置に挿さないと**エラーではなく静かに前世代の色**になる作りだった（しかも display_name が空の Bedrock でだけ再現するので最も見つけにくい）。今は残る順序ルールが「generic tier の arm を最後に置く」1 つだけで、**新モデルはパレット 1 行 + arm 1 行**で足せる
- 正規形は必ず小文字になる（tier 名をループのリテラルから取るので bash 4+ の `${var,,}` が不要）

### Fixed

- **旧形式の model id を単独で渡すと色が間違っていた**のを修正。`claude-3-5-sonnet-20241022` を `display_name` 側だけで受けると `*sonnet*3-5*` に当たらず **teal（Sonnet 4.6 の色）**になっていた。従来 amber で出ていたのは、判定キーが `display_name|model_id` の連結で**同じ文字列が 2 回並ぶ**ため「片方の `sonnet` と他方の `3-5`」が偶然マッチしていたからで、意図した動作ではなかった。正規化により `sonnet 3.5` → amber と確定する
- **1 文字のモデル名で statusline が丸ごと空白になるバグを修正**（v1.54.0 以降。bash 3.2 限定）。`_paint` のスイープ添字を三項演算子で書いていたが、**bash 3.2 は未選択の分岐も評価する**ため 1 文字（分母 0）で "division by 0" を出し、呼び出し側の変数が未設定のまま `set -u` に当たっていた。`if` で書き直した（bash 4+ では再現しないクラス）

### Added

- **`install.sh --uninstall`** — `statusLine` / `subagentStatusLine` の 2 キーだけを外す（`padding` 等の個人設定や他のキーには触らない）。登録時と同じ安全策（差分表示 + y/N 確認、タイムスタンプ付きバックアップ、冪等）が効き、**clone を消した後でも動く**（スクリプトの存在確認と試走をスキップするため、孤児設定の掃除に使える）
- `format_reset_remaining` / `format_reset_absolute` のテスト（従来 0 件だった唯一の未検証領域）。5h 残りの `H:MM`・0 埋め・期限切れの `now`・欠落/null、週間の `date -j` 整形を pin
- `/render` の fixture 6 個を現行モデル（Opus 5 / Sonnet 5・Claude Code 2.1.220）に更新。プレビュー道具が実運用の表示を映すようにした

### Removed

- **`TODO.md` を削除**。残っていた 2 件を消化した: `build_git()` のデータ/表示分離は v1.53.0 で実施済み、**Go/Rust リライトは「やらない」判断**を CLAUDE.md の Key Constraints に移した（実測 50-60ms はタイムアウトから十分遠く、warm cache の fork は 4 個で床。バイナリ配布になれば `git pull` だけで更新できる今の運用を失う）

## [1.57.0] - 2026-07-27

### Changed

- **コンテキストの分母を常時表示にした**（`48%/200k`・`48%/1M`）。v1.56.0 までは既定の 200k だけ無印にしてノイズを避けていたが、それは**読み手が「無印 = 200k」という既定値を記憶している前提**になる。`%` だけでは絶対量が読めないという当初の問題は 200k でも同じなので、値が来ていれば常に出す形に統一した。分母を出さないのは `context_window_size` が来ていないとき（旧 Claude Code）だけ
- 判定が `> 0` の 1 条件になり、「既定値の特別扱い」という分岐そのものが消えた

## [1.56.0] - 2026-07-27

### Changed

- **コンテキストの分母を「既定 200k 以外なら出す」に一般化した**。v1.55.0 は `>= 1000000` で判定し `size / 1000000` を整数除算していたため、公式 docs が定める 200k / 1M の 2 値以外が来ると**黙って間違えていた**: `500000` は 1M 未満なので**何も出ず 200k と区別できない**（実際は 2.5 倍違う）、`1500000` は切り捨てで **`/1M` と誤表示**。判定を「`> 0` かつ `!= 200000`」に変え、表記は新ヘルパー `fmt_ctx_size`（既存 `format_tokens` に委ね、分母では邪魔な `.0` だけ落とす）に任せた。`500k` / `1M` / `1.5M` / `2M` が正しく出る
- 既定の 200k は引き続き無印（大多数がそれなのでノイズにしない）。フィールド欠落（旧 Claude Code）も無印

## [1.55.0] - 2026-07-27

### Changed

- **弱め表示（dim）の棚卸しを実施し、2 箇所だけ通常輝度へ上げた**。全 15 箇所を「① ラベルだけ弱め・値は通常輝度（`gh:` + owner/repo）」「② 要素まるごと二次情報」「③ 不在・プレースホルダ」の 3 役に分類して 1 件ずつ確認した結果、①②③ の使い分けは一貫しており大半は現状維持が妥当と判断した。変更したのは意味の取り違えが起きていた 2 箇所のみ:
  - **コンテキストの分母 `/1M` を `%` と同じ色に**（使用率に応じて緑/黄/赤）。dim だと「% を修飾する分母」ではなく「別の補助情報」に見えていた。`88%/1M` が一体で読めるようになった
  - **セッションコスト `$18.07` を通常輝度に**。弱め要素が並ぶ Line 4 右端で「いくら使ったか」は目に入れたい値。色は付けない — Line 4 には既にサンド（レート制限）/ 緑黄赤（使用率）/ 金（extra-usage 実課金）の 3 系統があり 4 つ目を足すと色の意味が薄まる。とくに**金色は使わない**（`extra:$` は実際に課金される額、セッションコストはサブスクでは請求されない参考値で、同色にすると区別が消える）。bold も使わない（このリポの bold は vim mode バッジ専用）
- セッション経過時間・`week:` レート制限・`base:`・last commit・`from:`・`🌲worktree 名`・`(+N dirs)`・`no git`・`-%`・untracked `?N`・`v2.1.220` は**すべて現状維持**（1 件ずつ確認済み）

### 計測メモ

- 弱め表示は全体の 42.7%（218 字中 93 字）。行別は Line 1=16.3% / Line 2=38.9% / **Line 3=68.0%** / Line 4=46.2%。Line 3 で通常輝度なのは `owner/repo` だけで、これは「repo/branch が主役、他は補助」という設計の帰結。**弱め要素をこれ以上増やさない上限**として記録する
- 「弱め」の機構は 3 系統: `DIM`（SGR 2 = faint 属性、15 箇所）/ `DIMVER`（`38;5;248`、version・untracked）/ `DRAFT`（`38;5;245`、PR draft）。245 と 248 の知覚明度差は 30.0 で見分けられる範囲なので併存は問題なし。`DIM` は色を指定しない属性なので**混色事故が起きうる**が、全 15 箇所が `${DIM}…${RST}` で閉じていることを確認済み
- `DIM`（SGR 2）は端末依存。faint 未対応の端末では該当 51 字が通常輝度に潰れて階層が消える（Ghostty は対応）

## [1.54.0] - 2026-07-27

### Changed

- **`display_name` の `(1M context)` を名前から剥がし、コンテキスト量は Line 4 の分母として `48%/1M` で出すようにした**。従来は Line 1 のモデル名が `Opus 5 (1M context)` と 14 文字長くなる一方で、**Line 4 の `48%` からは 1M か 200k かが読めなかった**（絶対量は 5 倍違う）。つまり % を修飾する情報が別の行に貼られていた。加えて `display_name` 由来なので**Bedrock では表示されず**（display_name が空で model id にフォールバックするため）、provider によって出る/出ないが食い違っていた。`context_window.context_window_size` から自前で導出することで 3 つとも解決する: % の隣で分かる / Bedrock でも同じ表示 / Line 1 が 14 文字短く subagent 行の表記と揃う。**分母は 1M 以上のときだけ出す**（既定の 200k は大多数なので無印。ノイズを増やさない）。剥がす対象は「context を含む末尾の括弧」だけで、`Opus 5 (preview)` のような他の括弧付き display_name は触らない
- **5 系の多色パレットを知覚明度で組み直した**。`OPUS5_PAL` は 5 → 3 ストップ（`130` dark orange → `173` CORAL → `215` gold）、`SONNET5_PAL` は 6 → 4 ストップ（`28` → `70` → `148` → `154`）。旧パレットは**隣接ストップの知覚明度差が 8.5 しかない組が含まれ**（Opus 5 の `130`/`166` と `173`/`209`、Sonnet 5 の `70`/`106`）、見分けられないストップにスロットを使っていた（Opus 5 は 5 ストップで実質 3 段）。すべての隣接差を 28 以上に取り直し、少ないストップで同じ明度レンジを稼ぐ形にした
- **スイープの添字を四捨五入にした**。切り捨てだと**最終ストップが末尾 1 文字にしか載らず**、一番明るい色がほぼ見えなかった（35 字の Bedrock 生 id で `130`×9 → `166`×8 → `173`×9 → `209`×8 → `215`×**1** 字）。四捨五入により帯が均等になる（`Opus 5` は 2/2/2 字、`Sonnet 5` は 2/2/2/2 字）
- Fable の `rainbow()` は**変更なし**。循環（明度ランプではなく色相の多様性が目的）で、`Fable 5` の 7 文字に 7 色がちょうど 1 周する

## [1.53.0] - 2026-07-27

### Changed

- **`build_git()` が「事実」だけをキャッシュし、表示は `render_git()` に一元化した**（内部構造の変更で、表示は変わらない）。従来は**レンダリング済みの ANSI 文字列**をキャッシュしており、それが 2 つの Gotcha の共通の根だった:
  - **「Line 3 の 3 パス問題」** — 表示要素を足すたびに (1) `build_git` 非 detached (2) `build_git` detached (3) cold-start の 3 経路すべてで同じ条件で gate しないと、5 秒のキャッシュ populate 前後で表示が変わるフリッカーになっていた。専用の `line3-three-path-auditor` agent まで用意して人力で守っていた
  - **cross-session 汚染** — cache key が `md5(dir)` だけなので、stdin 由来値（`pr.review_state` 等）を `build_git` 内で描くと、同一 dir で動く別セッションが最大 5 秒間**相手の値**を表示しうる
- 新構造では `build_git()` が US(`0x1f`) 区切りの 13 フィールド（branch / detached / repo_id / remote / base / dirty 4 種 / ahead / behind / age / msg）を返し、`render_git()` が facts + stdin 由来値から `line_git` を組む。**cold-start は「多くのフィールドが空の facts」を合成して同じ presenter に通す**だけになり、gate を揃えるという概念自体が消えた。stdin 値は cache に一切入らないので汚染も構造的に起こらない
- 副作用として `line3-three-path-auditor` agent と CLAUDE.md の Gotcha 2 項が不要になった。キャッシュのファイル名に `-v2` を付けたので、旧キャッシュを facts として誤読することはない（移行処理は不要、初回だけ 5 秒遅れる）
- `repo_id` は cache には origin 由来の事実を持たせ、**表示時に stdin の `workspace.repo`（fork ゼロ）を優先**する。`build_git` は background 実行なので、事実確定のための `git remote get-url` 1 fork は hot path に乗らない

## [1.52.0] - 2026-07-27

### Added

- **セッション経過時間を Line 4 に追加**（`cost.total_duration_ms`、dim、セッションコストの直前）。長時間の agentic セッションや複数セッション並走で「これ何時間回してる?」は瞬間的に見たい情報だが、Claude Code に常駐表示がない。stdin に既にある値なので **fork ゼロ**。表記は `3m` / `1h01m` / `27h`（24 時間超は分を落とす）。**60 秒未満は非表示** — 開始直後の `0m` はノイズなので出さない。フィールド欠落（旧 Claude Code）も jq default 0 で同じく非表示に倒れる

### Changed

- **キャッシュ置き場をユーザー単位にした** — `/tmp/ist-j-ichikawa-claude-statusline` 固定から `${TMPDIR:-/tmp}/claude-statusline-$UID` へ（`CLAUDE_STATUSLINE_CACHE_DIR` で差し替え可）。固定の共有パスには 3 つの実害があった: (1) **共有 Mac の別ユーザーは 700 のディレクトリに書けず**、git 行が永久 cold-start になるうえ `usage_spend` も書けないので毎レンダー refetch = コード内コメントが「致命的」と呼ぶ curl storm、(2) **テストが本物のキャッシュを触っていた** — `bats` 実行中に作者のライブ statusline へ偽の値（`extra:$5.00`）が一瞬出得た、(3) 公開ツールなのに他人の `/tmp` に個人名のディレクトリが生える。macOS の `TMPDIR` は既にユーザー単位なので (1)(3) が消え、env override がテスト密閉の seam になる（テストは `$BATS_TEST_TMPDIR/cache` を使うよう変更）
- **既存ユーザーの移行作業は不要**（初回だけ Git 情報が 5 秒遅れて出る）。旧ディレクトリは放置しても macOS が定期的に掃除する

### Fixed

- **キャッシュディレクトリの親が 755 で作られていた**（Security ルール「cache dirs は `mkdir -p -m 700`」の違反）。BSD の `mkdir -p -m` は**最後に作るディレクトリにしか mode を当てない**ため、`mkdir -p -m 700 <base>/git` では `<base>` が umask の 755 で残っていた（実測: 旧キャッシュは base 755 / `subscription` ファイルが 644）。親も operand に並べて両方 700 にした
- `dur_sec` の事前初期化漏れを修正 — `eval` が `|| true` で失敗した時に `set -u` で即死する規約違反だった（jq 抽出変数は必ず事前初期化する）

## [1.51.0] - 2026-07-27

### Added

- **`install.sh` を追加**。`git clone` して `./install.sh` を叩けば `~/.claude/settings.json` に `statusLine` / `subagentStatusLine` が登録される。従来はユーザーが clone 先の絶対パスを自分で JSON に書き写す必要があり（`~` が展開されないため相対で書けない）、既存 settings.json への手動マージも要るのが導入の壁になっていた。既存キーは保ったままマージし、`refreshInterval` / `hideVimModeIndicator` は**ユーザーが既に決めていればその値を尊重**（未設定時だけ推奨値 `30` / `true` を入れる）。登録前にスクリプトを試走して動かなければ何も書かずに中止。`--main-only` / `-n, --dry-run` / `-y, --yes` と、書き込み先を差し替える `CLAUDE_SETTINGS=<path>`（テストもこの seam を使う）
- **install.sh はグローバル設定を触るので、既定で「差分を見せて y/N 確認」するまで一切書き込まない**。加えて次の 3 つを設計に入れた: (1) **バックアップはタイムスタンプ付きの別名** — 固定 `.bak` だと 2 回目の実行で「変更後の状態」を上書きし元の設定が失われる、(2) **`settings.json` が symlink（dotfiles 管理）ならリンクを壊さず実体に書く** — リンクへ `mv` すると実体との繋がりが切れ「設定したのに反映されない」になる、(3) **既存 `statusLine` が別ツール（ccstatusline 等）を指す場合は名指しで警告**してから確認を求める（無警告で奪わない）。非対話環境で `--yes` 無しの時は確認を飛ばさず中止する。冪等で、既に同内容ならバックアップも作らず「変更なし」で終わる
- `CLAUDE_STATUSLINE_NO_NET` が `fetch_subscription()` の **Keychain 読みも止める**ようにした。ネットワークではないが macOS のアクセス許可ダイアログを出しうる外部参照であり、install.sh の試走やテストがユーザーの Keychain に触るのは意図しない副作用だった（この seam を「外部への問い合わせをしない」の意味に統一）
- install.sh に **macOS 以外での門前払い**を追加（`stat -f` / `md5 -q -s` 依存なので Linux では動かない。公開の玄関になった以上、失敗するより先に一言で断る）
- install.sh の追加の防御（レビューで検出）: **元のファイルパーミッションを引き継ぐ**（`settings.json` は `env` の API キーを持ちうるため、`600` で固めた設定が umask の `644` に緩むのを防ぐ）、**登録するスクリプトの存在確認と試走を subagent 版にも広げる**（欠けていても登録され「存在しないコマンドを毎行実行」になっていた）、**試走を `CLAUDE_STATUSLINE_NO_NET=1` で回す**（インストールが OAuth 通信・Keychain 読み・共有キャッシュ書き込みを副作用で起こさない）+ 出力が空でないことも確認、**clone 先パスに空白があれば登録を断る**（設定値が分割されて「入れたのに真っ白」になる）、`${BASH_SOURCE%/*}` と `${settings%/*}` の**スラッシュ無し fallback**（`bash install.sh` 起動や `CLAUDE_SETTINGS=settings.json` でディレクトリを誤作成していた）、**空ファイルの settings.json は初期化**（「不正な JSON」で突き返していた）、**末尾に改行を付ける**（dotfiles の git diff を汚さない）、Ctrl-D での中止を `set -e` の即死ではなく中止メッセージ経路に流す

### Fixed

- **stale worktree（親リポが消えた `.git` ファイルが残った状態）で statusline が完全に空白になっていた**のを修正。`line_git` が空配列になり `"${line_git[*]}"` の展開が bash 3.2 の `set -u` で即死して exit 1 していた。同じ経路で**壊れた JSON を渡した時の `jq error` 表示も出ずに空白**になっていた（`line2=()`/`line3=()` の空配列展開）。macOS の `/bin/bash` は 3.2 固定なので**本番だけで起きる**バグで、bash 4+ では再現しない
- **テストが本番と違う bash で走っていたのを修正** — `test.bats` の全 120 箇所超が PATH の `bash`（homebrew 5.x）でスクリプトを起動していたため、このリポの最重要制約「bash 3.2 互換」を 140 件のテストが一切検証していなかった。`/bin/bash` 起動に統一したところ**上記の空白バグが即座に露出**した（v1.51.0 の空パレット即死も同じ穴を通り抜けてリリースされ、レビューでしか見つかっていない）。字句レベルの bash4-ism grep（PostToolUse hook）は空配列展開のような**意味論の差**を掬えないので、実 3.2 での実行が唯一の網になる
- **Bedrock の実 model id (`-v1:0`) から版接尾辞を剥がせておらず、サブエージェント行が `Opus 5.v1:0` と表示されていた**のを修正。実際の AWS の id は常に `:N` を伴う（`global.anthropic.claude-opus-5-v1:0`）が、`${m%-v[0-9]}` は `:0` 付きにマッチせず素通りしていた。README / CLAUDE.md の「`-vN` 接尾辞も剥がす」という記述と実挙動が食い違っていた（v1.49.0 からの潜在バグ）
- **空パレットで色ヘルパーを呼ぶと statusline 全体が空白になりうる**のを修正。bash 3.2 の `set -u` は空配列の `"${a[@]}"` 展開で即死するため、`_paint` の「パレット未指定なら無色 degrade」ガードに到達する前にスクリプトが落ちていた（ガードが謳う保護が実際には効いていなかった）。呼び出しを `${PAL[@]+"${PAL[@]}"}` に変更

### Removed

- **サブエージェント行から context% バーと経過時間を撤去**。行本文は **説明 + モデル(tier 色) + [注意状態] + [🌲worktree]** だけになった。実運用で並走させると 3 行が `9% 5m` / `5% 5m` / `8% 6m` のように**どれも似た値**になり（同じタスクを分担するので当然）、行が伸びるだけで「どれを見るべきか」の判断に効いていなかった。差を見たい時は Claude Code 既定描画のトークン数か `/context` の方が精度が高い
- 撤去に伴い `tokenCount` / `contextWindowSize` / `startTime` の jq 抽出、`fmt_elapsed()`、**経過時間用の `date` fork** がまとめて落ちた（スクリプトは実質 21 行減。残る fork は入出力の jq 2 回のみ）

## [1.50.0] - 2026-07-27

### Changed

- **Opus 5 を多色スイープ描画に変更**（`130` dark rust → `166` rust → `173` CORAL → `209` salmon → `215` gold）。Fable（蝶標本の多色循環）と Sonnet 5（植物モチーフの緑スイープ）が多色なのに Opus 5 だけ flat という不統一を解消。発表アートワークは**鳥卵標本図版のコラージュで数字「5」を組む**構図で、Opus 4.x の「粘土コーラル」のような支配色がなく artwork 由来の単色を選べないため多色にした。**構造は Sonnet 5 と同じ「単色相を暗→明にスイープ」で、色相を Opus の coral 一族に取る** — アートワーク実測に忠実な低彩度の tan/olive で組んだ初版は、ターミナル上でくすんで「グラデーション」に見えず地味だった（Sonnet 5 の見栄えは `28`→`154` の広い明度レンジ由来）。彩度と明度レンジを稼ぐ方を優先し、両端とも mid/high 彩度に留めて light テーマでも飛ばないようにした。Opus 4.x は flat coral のまま。判定は `*"opus 5"*` / `*"opus-5"*`（`*opus*5*` は "Opus 4.5" にも誤マッチするため使わない）で、generic `*opus*` より前に置く
- `CORAL` を `CORAL_N=173` から組み立てるようにし、`OPUS5_PAL` も同じ定数を参照するようにした（coral の再調整が片方だけに効く手動同期を廃止）
- **`model_color` が tier 判定に `display_name` と `model_id` の両方を使うように変更**（`model_color VARNAME MODEL_SHOW [MODEL_ID]`、描画は MODEL_SHOW のみ）。`display_name` が版を含まない形（`Opus (1M context)` 等。公式 docs の JSON 例も `id: claude-opus-5` に対し `display_name: "Opus"`）で来ると Line 1 は flat coral に落ちるのに、id しか持たない subagent 行はスイープになる — モデル色を一元化した目的そのものが崩れる食い違いだったので、id を副次ヒントとして渡すようにした。副産物として `display_name: "Sonnet"` + `id: claude-sonnet-4-5` のような取りこぼしも拾えるようになった
- **`rainbow()` / `gradient()` がパレットを引数で受けるように変更**し、共通の `_paint` に統合した（`rainbow`=循環 / `gradient`=スイープ の 1 行ラッパー）。パレットは `FABLE_PAL` / `SONNET5_PAL` / `OPUS5_PAL` として色定数の隣に集約 — 多色モデルが増えても描画ヘルパーは増やさずパレット配列だけ足す形にした。パレット未指定時は無色テキストに degrade する（`braille_bar` 等 lib.sh の他ヘルパーと同じ入力検証方針。ゼロ除算・負添字で statusline 全体が空白になるのを防ぐ）
- Built against Claude Code 2.1.220。2.1.219 で `claude-opus-5` が追加され Opus の既定モデルになったが、色分けの `*opus*` ワイルドカードと `prettify_model` の「先頭セグメント = tier 名」規則により**無改修で `Opus 5` 表示になっていた**ことを確認済み（上記の色変更は不統一の解消であり、追従の必須対応ではない）。`/fast` の対象が Opus 5・4.8 に変わった点も既存の `fast_mode` 表示でそのまま追従。サブエージェント行のネスト深度が 1 → 3 になった件は `tasks[]` のフィールド構成が不変のため影響なし

## [1.49.0] - 2026-07-23

### Changed

- **サブエージェント行の「実行中」表示を Claude Code のネイティブ描画に委ね、独自グリフを廃止**。Claude Code は各行の先頭に `○`／スピナーを自前で描くため、こちらの `↑`(伸び中) / `▪`(頭打ち) / `✓`(完了) は重複だった。加えて statusline は refresh tick ごとの再実行で連続アニメーションできず、tick 駆動の擬似スピナーは CC の本物より劣る。よって `↑`/`▪`/`✓` と `tokenSamples` のトレンド判定を全廃し、行本文は **説明 + モデル + コンテキスト%バー + [注意状態の status 語] + 経過 + [🌲worktree]** の静的情報に絞った。`needs_input` 等の注意が要る状態のみ黄色い語で表示（実行中は CC の `○` が示す）。副次的に `tokenSamples` を index しなくなり、型不正による jq abort リスクも消滅

### Fixed

- **Bedrock の inference-profile model id が整形されず生表示される問題を修正**。`jp.anthropic.claude-opus-4-8`（`<region>.anthropic.` prefix 付き）等が `prettify_model` を素通りして生 id のまま出ていた。prefix と `-vN` 接尾辞を剥がすようにし、`Opus 4.8`（coral）に整形されるようにした（Bedrock 運用で毎行 raw id が出ていた）

## [1.48.0] - 2026-07-23

### Fixed

- **`/code-review` で見つかったサブエージェント行の不具合を修正**（`/simplify` の cleanup も同時反映）:
  - **1 件の不正な `tokenSamples`（非配列）で agent panel の全行が既定描画に戻る**問題を修正。トレンド判定の jq が配列前提で index して abort → `|| exit 0` で全出力が消えていた。`type == "array"` を確認してから index するようにし、型不正の task があっても他の task の描画は保たれる
  - **完了タスクに経過時間が伸び続けて表示され「まだ実行中」に見える**問題を修正。`completed` には経過を出さない（`✓` のみ）。経過は `now - startTime` で終了時刻を持たないため、完了後は伸び続けていた
  - **起動直後の実行中タスクが誤って `▪`（停滞）表示になる**問題を修正。`tokenSamples` が 2 点未満/非配列でトレンドが不明な時は状態グリフを出さない（Claude Code の `◯` に委ねる）。`▪` は「頭打ち」を確認できた時だけ
  - **旧形式の model id（`claude-3-5-sonnet-…` など版が tier より前）が `prettify_model` で文字化けする**問題を修正。先頭セグメントが tier 名の新形式のみ整形し、旧形式は cleaned id をそのまま出す
  - **`label` が空のとき content 先頭に余分な空白が付く**問題を修正。行組み立てを `add()` ヘルパーに統一し、先頭要素以外にのみ 2 スペース区切りを付与

### Changed

- worktree marker 文字列 `/.claude/worktrees/` を `lib.sh` の共有定数 `WT_MARKER` に集約（主 statusline とサブエージェント statusline の 2 ファイル 3 箇所に散在していた外部契約文字列の drift を防止）
- サブエージェント statusline の出力を `printf | jq` から here-string 供給（`jq … <<< "${_out%$'\n'}"`）に変更し、入力側と同じく `printf` の subshell fork を回避（fork 3→2）。text フィールド全て（`id`/`label`/`model`/`status`/`cwd`）の改行・タブを `gsub` で空白化して 1 行 = 1 task を堅牢化

## [1.47.0] - 2026-07-22

### Changed

- Built against を Claude Code 2.1.218 に追従（`/check-claude-code-update` で `4d07874`〜2.1.218 = 2.1.217 / .218 の 2 版を分析）。**stdin JSON フィールド・`subagentStatusLine` payload・`statusLine` 設定・モデル・プロバイダー・認証への変更はゼロ**でロジック改修なし。subagent 系の変更（2.1.217 で同時実行数の上限 default 20＝`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`・ネスト spawn の既定無効化＝`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`・`--max-budget-usd` での停止、2.1.218 で `/code-review` の background subagent 化・`context: fork` skill の既定 background 化）はいずれも実行制御／挙動の変更で、agent panel の各行に来るフィールドは不変（＝v1.46.0 のサブエージェント行描画に影響なし）。2.1.217 の footer PR badge の hyperlink 化（`FORCE_HYPERLINK`）は Claude Code 組み込み footer レイヤーの話で、本スクリプトの OSC 8 リンクとは独立
- 公式 docs 突き合わせ（Step 2.5）: statusline の stdin フィールド一覧と subagentStatusLine の per-task フィールドを実装と全照合し、削除・リネーム・新規フィールドなしを確認

## [1.46.0] - 2026-07-22

### Changed

- **サブエージェント行を再設計**（v1.45.0 の初版から、既存 statusline と協調するデザインへ）。実際の `subagentStatusLine` ペイロードを観測して判明した事実（`type` は総称 `local_agent`／`name` は多くの場合 null・意味ある識別子は `label`＝`description`／セッション effort はペイロードに来ない／`startTime` は epoch ミリ秒／`tokenSamples` はトークン数の履歴配列）に基づく。新デザインは `説明(先頭) + モデル(pretty-name・tier色) + context%バー + 状態グリフ + 経過 + [🌲worktree]`:
  - **`⚡` プレフィックスを廃止** — agent panel という場所自体がサブエージェントを示すため、独自グリフはミニマル方針に反すると判断
  - **モデルは Line 1 と同じ表記に整形** — ペイロードは id 形式（`claude-opus-4-8[1m]`）で来るので `prettify_model` で `Opus 4.8` 風にし、`model_color` で tier 色（Fable=rainbow 等も id 形式にマッチ）
  - **context% は Line 4 と同じ** braille バー＋閾値色（同一閾値: 黄 ≥80% / 赤 ≥90%）
  - **状態グリフ**（`status`＋`tokenSamples` のトレンド）: 実行中で伸びていれば `↑`、頭打ちなら `▪`、完了は `✓`、それ以外（入力待ち等の未知の status 値）は生の値を黄で表示（PR review_state と同じ色付き単語の作法で取りこぼさない）
  - **経過時間**を `startTime` から算出し dim・コンパクト表記（Line 3 の commit age と協調）
  - **worktree 隔離**エージェントは `cwd` から `🌲名` を表示（Line 2 の worktree 表示と協調）
  - 端末幅での切り詰めはしない方針を踏襲（全要素フル出力・折り返し/切れは端末に委ねる）
- 抽出・出力とも**単一 jq**を維持（区切りは非空白の US `0x1f` で空フィールド桁ずれを回避、トレンド判定も同 jq 内）。経過用の `date` はループ前に 1 回のみ。bats のサブエージェント系テストを新デザイン（状態グリフ4種・pretty-name・経過・worktree・⚡不在）に刷新

## [1.45.0] - 2026-07-21

### Added

- **サブエージェント行の独自描画 (`subagent-statusline-command.sh`)**。Claude Code の `subagentStatusLine` 設定に対応する新コマンドを追加し、agent panel に並ぶ各サブエージェントの行をメイン statusline と同じ配色で描画できるようにした。各行は `⚡名前`（`label` 優先）+ モデル色（tier 色）+ コンテキスト使用率バー（`tokenCount / contextWindowSize` を braille バー + %）+ effort + 説明（端末幅で切り詰め）。`settings.json` の `subagentStatusLine` から参照（任意設定。省略すれば Claude Code 既定行のまま）。`model` / `contextWindowSize` は Claude Code 2.1.205+、`effort` は 2.1.214+ で提供される。model/effort/contextWindowSize 欠落・tasks 空・不正 JSON でも exit 0（graceful degradation）

### Changed

- **共有ライブラリ `lib.sh` を新設**し、メイン statusline とサブエージェント statusline が色定数と presentation ヘルパー（`has_val` / `osc8` / `editor_url` / `rainbow` / `gradient` / `model_color` / `braille_bar` / `color_by_threshold` / `format_tokens`）を単一ソースで共有するようにした。特に**モデルの tier 色分けを `model_color` 関数に一元化**し、両 statusline で同一の色になるようにした（従来 `statusline-command.sh` に inline had）。`model_color` は `Sonnet 4.5` のような display_name に加え `claude-sonnet-4-5` のような **model id 形式にもマッチ**する（サブエージェントの `model` は id 形式で来るため）。`lib.sh` はネットワーク / キャッシュ / `date` 等の副作用を持たず、それらは `statusline-command.sh` 側に残す。両スクリプトは同じディレクトリの `lib.sh` を `source` する（相対起動でも解決できるよう fallback 付き）。表示・挙動の変更はなく（既存テスト 105 件そのまま通過）、内部構造のリファクタ + サブエージェント機能追加でテストは 113 件に

**Note:** `~/.claude` に直接ダウンロードして使っている場合は、`statusline-command.sh` と同じディレクトリに `lib.sh` も配置する必要があります（README「代替」参照）。

## [1.44.0] - 2026-07-21

### Added

- **Line 1 に fast mode インジケータを追加**。stdin JSON の `fast_mode`（boolean、`/fast` 有効時に true。Claude Code 2.1.216 の docs で確認、CHANGELOG 非掲載）が true のとき、effort / think の隣に greenyellow（`FAST`=`38;5;190`）の `fast` を表示する。fast mode は Opus 専用機能なので Line 1 で model coral と同居するが、色相が離れているため衝突しにくい。色は effort / think と同じくモデル色との衝突回避のため選んだ非ブランドの識別色で、tunable。`fast_mode=false` / キー欠落（旧 Claude Code）では非表示（graceful degradation）。effort / think / fast が複数あるときは半角スペース区切りで併記（`high think fast`）。bats に fast on / off / キー欠落 / 併記の 4 ケースを追加

## [1.43.0] - 2026-07-21

### Changed

- Built against を Claude Code 2.1.216 に追従（`/check-claude-code-update` で `67f390c`〜2.1.216 = 2.1.214 / .215 / .216 の 3 版を分析。2.1.213 は欠番）。**stdin JSON フィールド・`statusLine` 設定・モデル・プロバイダー・認証への破壊的変更はゼロ**でロジック改修なし。subagent 周りの変更（2.1.214 で `subagentStatusLine` payload に per-task `effort` フィールド追加＝定義 frontmatter か invocation の reasoning effort、文字列レベルか数値 token budget、session effort 継承時は absent／2.1.216 で resume 時に background subagent が起動直後にキャンセルされる・resume で default agent に戻る等のバグ修正）はいずれも `subagentStatusLine`・agent 管理レイヤーの話で、本スクリプト（主 statusLine）は未採用のため影響なし。表示に好影響の修正が 1 件: 2.1.216「resume 時に statusline コマンドが 2 回走り最初の結果がちらつく問題の修正」（docs にも `min-version: 2.1.216` 注記が追加。本スクリプトが resume 直後に二重実行されていた無駄が解消される方向）
- 公式 docs 突き合わせ（Step 2.5）で新フィールド **`fast_mode`**（boolean、fast mode 有効か。CHANGELOG 非掲載・docs のみ＝取りこぼしパターン。absent リストにも無く常在）を確認。Line 1 の effort/think と同じセッション状態系トグルだが、ミニマル方針のため採用は別途判断（未採用）。他の抽出依存フィールドの削除・リネームは無し

## [1.42.0] - 2026-07-17

### Changed

- **Line 2: `from:HEAD` を再表示（1.41.0 の抑止を撤回）**。1.41.0 で「detached HEAD から作成した worktree の `from:HEAD` は情報ゼロ」として非表示にしたが、「detached から切った」事実自体がシグナルであり、Line 3 の `base:`（切った元ブランチ）が reflog の GC で欠けた場合には唯一の切り元情報になりうる。ユーザー判断で `HEAD` の特別扱いをやめ、`worktree.original_branch` があれば値によらず `from:<branch>` を表示する方針に戻した（`from:main` 等の実ブランチ名は 1.41.0 でも表示されていたので、変わるのは `from:HEAD` の 1 ケースのみ）。Line 2 のパス分割・Line 3 の `gh:owner/repo` 通常輝度化・detached cold-start フリッカー修正（すべて 1.41.0）はそのまま維持。bats の該当ケースを「非表示」から「表示」に反転

## [1.41.0] - 2026-07-17

### Changed

- **Line 2: worktree パスの分割表示**。パスが `<repo>/.claude/worktrees/<name>` で終わる場合、パス本文をリポジトリ root までで切り、worktree 名を `🌲<name>`（dim）として表示するようにした。従来は worktree セッションのパス末尾がランダムな worktree 名（例: `sprightly-scribbling-melody`）で占領され、リポジトリのディレクトリ名がパス中程に埋まって「どこの repo にいるのか」が読み取りにくかった。OSC 8 リンクはパス部分がリポ root、worktree 名部分が worktree ディレクトリを開く。worktree 内サブディレクトリ滞在や既定外配置ではフルパス表示に fallback（分割しない）
- **Line 2: `from:HEAD` を非表示**。worktree を匿名 HEAD から作成した場合の `worktree.original_branch` = `HEAD` は情報ゼロのノイズのため表示しない。Line 3 の `base:HEAD` 抑止と同じ扱い（`from:main` 等の実ブランチ名は従来どおり表示）
- **Line 3: `gh:owner/repo` の `owner/repo` を dim から通常輝度に変更**。repo 識別の一次情報に昇格 — ローカルのディレクトリ名と origin のリポジトリ名が食い違うケース（例: dir は `MyApp`、origin は `myapp-core`）はここでしか判別できないため。`gh:` プレフィックスは dim のまま。非ブランド色（デフォルト前景色）なので視認性調整は自由
- **Line 3: cold start の detached HEAD で `gh:` が一瞬表示されて消えるフリッカーを修正**。cold start（cache 未生成）は `gh:` を無条件に出していたが、`build_git()` の detached パスは `gh:` を出さないため、5 秒後の cache 生成時に `gh:` が消えて見えた。cold start 側も HEAD が ref のときだけ `gh:` を出すよう gate を統一。bats にワークツリー分割 3 ケース・detached cold start・gh: 輝度のテストを追加・更新

## [1.40.0] - 2026-07-17

### Changed

- Built against を Claude Code 2.1.212 に追従（`/check-claude-code-update` で `d4d8fbb`〜2.1.212 = 2.1.208〜2.1.212 の 5 版を分析）。**stdin JSON フィールド・`statusLine` 設定・モデル・プロバイダー・認証への破壊的変更はゼロ**でロジック改修なし。表示に好影響の Claude Code 側修正が 2 件: 2.1.211「`/clear` が session cost をリセットしない問題の修正」（Line 4 のセッションコストが `/clear` 後に $0 から正しく再スタート。docs の `cost.total_cost_usd` にも min-version 注記が追加）、2.1.208「CLI 自動更新後に context window size が一時的に 200k へリセットされ 100% 使用と誤表示される問題の修正」（Line 4 のコンテキストバーの誤表示が減る方向）
- 2.1.212 で `/fork` が「会話を background session へコピーする」別機能として復活（従来の in-session subagent 起動は `/subtask` に改名）。新 `/fork` のコピーはプロンプト由来の名前が付く仕様で、session_name への `(Fork)` マーカー付与は確認されていない。`(Fork)` 検出は旧セッション互換のため残置 — マーカーが付かない場合は黄色 `branch` 表示が出ないだけで実害なし（graceful degradation）
- 公式 docs 突き合わせ（Step 2.5）: statusline の stdin フィールド一覧を jq 抽出と全照合し、依存フィールドの削除・リネームなしを確認。新発見: `subagentStatusLine` 設定（CHANGELOG 非掲載・docs のみ。per-task `model`/`contextWindowSize` は 2.1.205+）— agent panel のサブエージェント行を独自描画する別系統の statusline で、本スクリプトとは独立した別コマンドが必要。未採用（採用可否は別途検討）

## [1.39.0] - 2026-07-12

### Changed

- Line 3 の PR review_state で `draft` を専用のニュートラルグレー（`DRAFT`=`38;5;245`）で表示するようにした。従来は明示 case が無く `pending`(黄) 以外の未知値と同じ dim にフォールバックしていたが、draft PR（レビュー依頼前の下書き）を `pending`（レビュー待ち）や未知値と色で区別できるようにした。`approved`=緑/`changes_requested`=赤/`pending`=黄/`draft`=グレー/他（`commented` 等）=dim。色は GitHub の draft バッジのニュートラルグレーに準拠する非ブランド識別色で、公式色が現れれば追従する。1.38.0 の docs 突き合わせで `pr.review_state` の docs enum が `approved`/`pending`/`changes_requested`/`draft` に更新され `draft` が dim フォールバック中と記録した件への対応。bats に draft=グレー のケースを追加

## [1.38.0] - 2026-07-03

### Changed

- Built against を Claude Code 2.1.201 に追従（`/check-claude-code-update` で `1322e9b`〜2.1.201 を分析）。新規は 2.1.201 の1件のみ「Claude Sonnet 5 セッションが harness reminder に mid-conversation system role を使わなくなった」で、Claude Code 内部のプロンプト注入方式の変更。stdin JSON フィールド・モデル・プロバイダー・認証・`statusLine` 設定のいずれにも無関係で **statusline 影響ゼロ・ロジック改修なし**

## [1.37.0] - 2026-07-03

### Changed

- Built against を Claude Code 2.1.200 に追従（`/check-claude-code-update` で `75709ea`〜2.1.200 を分析。新規版は 2.1.199 / .200）。**statusline に影響する stdin JSON フィールド・`statusLine` 設定・モデル・プロバイダー・認証の変更はゼロ**でロジック改修なし。2.1.199（skill stacking・SSL/429 リトライ・background daemon 修正多数・subagent の partial 返却・hook stderr 表示・`claude agents` の PR リンクを bare `#N` 化）／2.1.200（permission mode の "Manual" 化・`AskUserQuestion` の auto-continue 廃止・MCP config crash 修正・tmux 3.4+ の synchronized output・screen-reader 改善）は全て UI／CLI／エージェント管理／hook／a11y 系で表示要素に無関係。`claude agents` の PR リンク変更は agents ビュー行の話で、当スクリプトの `pr.review_state`（Line 3）とは別レイヤー
- 公式 docs 突き合わせ（Step 2.5）: statusline の stdin フィールド一覧を当スクリプトの jq 抽出と全照合し、依存フィールドの削除・リネームなし／新規 `statusLine` 設定なしを確認。参考: `cost.total_lines_added`/`cost.total_lines_removed`（コード行増減）が stdin に存在する（没にした git 行差分は git 呼び出し不要で stdin から取れる）が、ミニマル方針で不採用のまま

## [1.36.0] - 2026-07-03

### Added

- Line 4 に **extra-usage（usage-credits）の実課金額** を `extra:$X.XX`（gold `SPEND`=`38;5;220`、非ブランド）で表示。weekly レート制限と session cost の間に配置。session cost が全モデル合算の *参考値*（subscription では実請求なし）なのに対し、extra-usage は account の *実 credits 消費額* で **stdin JSON に無い唯一の課金情報**。Fable が 2026-07-07 以降 extra-usage 課金に移行するため「実際に溶けた額」を出す実益が大きい
- 取得用に `fetch_usage_spend()` を追加 — `/usage` OAuth エンドポイント（`api.anthropic.com/api/oauth/usage`、header `anthropic-beta: oauth-2025-04-20`）の `spend.used.amount_minor`/`exponent` を jq で cents に正規化して受ける（bash float 演算を回避）。**本スクリプト初のネットワーク呼び出し**だが、`fetch_subscription()` と同じく背景 subshell（`& disown`）+ 300s キャッシュ（`USAGE_CACHE`、atomic `.tmp`+`mv`）で hot path をブロックしない。OAuth トークンは `curl --config -` で stdin 経由に渡し argv/`ps` 露出を防ぐ。**Anthropic provider のみ**（Bedrock/Vertex/Foundry では fetch も表示もしない）
- `CLAUDE_STATUSLINE_NO_NET=1` でネットワーク取得を無効化できる（オフライン/プライバシー用途、およびテストの決定性 seam）。データ無し/取得失敗/`$0.00`/旧 Claude Code は非表示（graceful degradation）。エンドポイントは非公式（statusline docs 未記載）のため変わりうる前提

## [1.35.0] - 2026-07-02

### Added

- 公式ブランド色が未発表のモデルを、発表アートワークからサンプリングした色で一目識別する `rainbow()` / `gradient()` ヘルパーを追加（`display_name` を 1 文字ずつ着色、`$(...)` フォークゼロの bash builtin・bash 3.2 互換）
  - **Fable**（Mythos-class）を多色化。従来のスチールブルー単色（`38;5;74`、暫定色）を廃し、発表アートワーク（ヴィンテージの蝶標本プレート）の実測色を 1 文字ずつ循環させる `rainbow()` に変更。パレットは実アートワークの色分布（暖色主体・青はほぼ皆無）に忠実な gold→amber→rust→red→olive→green→teal の 7 色（`178`/`172`/`130`/`167`/`143`/`107`/`66`）
  - **Sonnet 5**（Claude Code 2.1.197 で追加、`claude-sonnet-5`）を緑グラデーション化。従来は generic `*sonnet*` フォールバックで Sonnet 4.6 と同じ flat teal だったが、発表アートワークの植物モチーフ由来の緑パレット（`28`→`154`）を文字列全体で 1 回スイープする `gradient()` で 4.6 と差別化。判定は `*"sonnet 5"*` / `*"sonnet-5"*`（`*sonnet*5*` は "Sonnet 4.5" にも誤マッチするため不使用）で行い、generic `*sonnet*`（=4.6 teal）より前段に配置。両モデルとも claude.ai に公式色が現れたら flat 単色へ追従する

### Changed

- Opus のモデル色を coral `38;5;209`（鮮やか）→ `38;5;173`（発表アートワーク実測の粘土コーラル）に変更。全モデル色を公式アートワーク基準で見直した結果、Opus 4.x のアートワークは 4.x 世代で唯一 artwork 由来の色（コーラル 46.5%）を持つため実測に忠実な 173 へ寄せた。Sonnet 4.6（teal）/ 4.5・3.5（amber）/ Haiku（lavender）は 4.x 共通の黒線画＋coral 背景テンプレで固有色が無く、識別用の非 artwork 色として現状維持
- Built against を Claude Code 2.1.198 に追従（`/check-claude-code-update` で `01f1617`〜2.1.198 を分析。新規版は 2.1.196 / .197 / .198）。上記 Sonnet 5 のモデル色対応以外に statusline へ影響する stdin JSON フィールド・設定変更はなし。各版の評価: 2.1.196（`/model` の org/role default 表示・起動時の可読な auto session 名・`claude mcp list/get` が self-approve MCP を起動しない修正・Bedrock `/context` 0-token 修正・`prompt_id` フィールド追加）／2.1.197（Sonnet 5 導入・default 化・native 1M context window）／2.1.198（Claude-in-Chrome GA・background-agent の `Notification` hook・`/dataviz` skill・Claude Platform on AWS `anthropicAws`）は、Sonnet 5 のモデル色を除き UI／CLI／エージェント管理／hook 系で表示要素に無関係。新規 `prompt_id`（2.1.196、現行プロンプトの UUID）も非表示要素

## [1.34.0] - 2026-07-02

### Changed

- Line 3（git info）の「切った元ブランチ」ラベルを `from:<parent>` → `base:<parent>` に変更。Line 2 の worktree インジケータ `from:original_branch`（セッションを開始したときに乗っていた元ブランチ）と同じ `from:` 語を使っていたため、隣接する Line 2 / Line 3 で意味の異なる 2 つの `from:` が並び、値が食い違うケース（元ブランチ ≠ git の分岐元）で「どちらが本当の分岐元か」が紛らわしかった。git の実際の分岐元（reflog `branch: Created from` パース）を `base:` に改称し、語で役割を分離した（Line 2 `from:` = セッションの出所 ／ Line 3 `base:` = git ブランチの土台）。reflog パース・表示ゲート条件は不変でラベル文字列のみの変更。README / docs/internals.md / CLAUDE.md も追従

## [1.33.0] - 2026-06-27

### Changed

- Built against を Claude Code 2.1.195 に追従（`/check-claude-code-update` で 2.1.182〜2.1.195 を分析。掲載は 2.1.183 / .185 / .186 / .187 / .190 / .191 / .193 / .195、それ以外は欠番）。stdin JSON フィールド・モデル・プロバイダー・認証のいずれにも変更がなく `statusline-command.sh` のロジック改修はなし。各リリースの statusline 影響評価: 2.1.186 の「usage-based Enterprise/Team 契約者で session cost が表示されなかったのを修正」は Claude Code 側が `cost.total_cost_usd` を populate する範囲が広がる変更で、Line 4 のコスト表示が**より多くのユーザーで出る方向**（当スクリプトは既に `cost.total_cost_usd` を扱い `$0.00`／欠落は非表示にしているため改修不要）。その他（2.1.183 auto-mode の破壊的 git ブロック・`attribution.sessionUrl`・`/config` トグル挙動、2.1.185 stream-stall ヒント文言、2.1.187 `sandbox.credentials`・org モデル制限、2.1.191 `/rewind` の `/clear` 前再開・hook の comma 区切り matcher 修正、2.1.193 `autoMode.classifyAllShell`・OTel `assistant_response`、2.1.195 `CLAUDE_CODE_DISABLE_MOUSE_CLICKS`・hook matcher の exact-match 化・日本語等スペース無し言語の音声 auto-submit 修正）は全て UI／CLI／エージェント管理／hook／認証ポリシー系で stdin スキーマ・表示要素に無関係
- 公式 docs 突き合わせ（Step 2.5）: `pr.review_state` の docs 記載 enum が `approved` / `pending` / `changes_requested` / `draft` に更新（旧記載の `commented` は脱落）。当スクリプトの `pr_state_color()` は `approved`=緑／`changes_requested`=赤／`pending`=黄、それ以外を `*)` デフォルトで dim にフォールバックするため `draft` も無破壊で dim 表示（改修不要）。新規 stdin フィールド・新規 `statusLine` 設定オプション（`type` / `command` / `padding` / `refreshInterval` / `hideVimModeIndicator`）の取りこぼしもなし

## [1.32.0] - 2026-06-18

### Fixed

- Line 2 のパス表示を `workspace.current_dir` に統一。従来は `${project_dir:-$current_dir}` で `workspace.project_dir`（Claude Code を起動した時点のディレクトリ）を優先していたため、`/cd` 後に古いパスを表示し、worktree セッションでは `worktree.path` 上書き（d618e5d の fix）を project_dir が打ち消して original repo のパスを出しうる問題があった。current_dir は worktree 上書き済み・Claude Code 2.1.176+ で `/cd` にも追従するので一貫して正しい。未使用になった `project_dir` の jq 抽出・初期化も削除（fork 最小化方針）

### Changed

- Built against を Claude Code 2.1.181 に追従（2.1.180 は欠番）。stdin JSON フィールドの変更はゼロでロジック改修不要。2.1.181 の注目点: fullscreen モードの URL オープンが Cmd+click（macOS）/ Ctrl+click 必須に変更（当スクリプトの OSC 8 リンクのクリック操作に関わる UX 変化だが出力は不変）、AWS `awsCredentialExport` 系の修正（Bedrock 認証まわりで、subscription 取得に使う Anthropic OAuth/Keychain とは別系統）— いずれも影響なし
- 公式 docs 突き合わせで `hideVimModeIndicator` 設定（CHANGELOG 未掲載・docs のみ）を発見し対応。本スクリプトは `vim.mode` を Line 1 先頭で目立つバッジに自前描画するため、`settings.json` の `statusLine.hideVimModeIndicator: true` を推奨（組み込みの dim な `-- INSERT --` との二重表示を解消、自前バッジは残る）。README / CLAUDE.md に推奨を明記し、`/check-claude-code-update` skill に docs 突き合わせステップ（Step 2.5）を追加

## [1.31.0] - 2026-06-17

### Changed

- Built against を Claude Code 2.1.179 に追従 (`/check-claude-code-update` で 2.1.175〜2.1.179 を分析、2.1.177 は欠番)。stdin JSON フィールドの変更はゼロのため `statusline-command.sh` のロジック変更はなし (docs のみ)。各リリースの statusline 影響評価: 2.1.175 (`enforceAvailableModels` 管理設定) はモデル許可リストの話で stdin スキーマ不変、2.1.176 の `footerLinksRegexes` は **Claude Code 組み込みフッター行**のリンクバッジ設定でカスタム statusline 出力とは別レイヤー (既存の `prUrlTemplate` PR badge と同じく住み分け済み)、同 2.1.176 の「`/cd`・worktree 移動後に前ディレクトリの git ブランチを報告するバグ」修正は Claude Code 側が stdin に渡す `workspace.current_dir` / git 情報が正しくなる方向の改善で追従不要、2.1.178 の「statusline リンクのカスタム URI スキーム (`vscode://` 等) が `claude agents` でクリックで開けるよう修正」は本スクリプトが OSC 8 を `file://` 固定にしている方針 (端末側の URI スキーム対応に依存しない) のため影響なし、2.1.179 は接続断・スクロール・sandbox 系のバグ修正で stdin 無関係。表示例の version 文字列も `v2.1.179` に同期 (issue #2 の `footerLinksRegexes` 住み分け検討の結論を含む)

## [1.30.0] - 2026-06-12

### Fixed

- Bedrock 検出の model.id プレフィックスに `us-gov.` (AWS GovCloud) を追加。Claude Code 2.1.174 で GovCloud リージョンの inference profile prefix が `global` → `us-gov` に修正され、`us-gov.anthropic.claude-...` 形式の model.id が届くようになったため。既存の正規表現は `us` の直後に `.` を要求するので `us-gov.` にマッチしなかった。実利用では `CLAUDE_CODE_USE_BEDROCK=1` の環境変数検出が先に効くため防御的 fallback の補完。Built against を Claude Code 2.1.174 に追従（他の変更は statusline に影響なし）

## [1.29.0] - 2026-06-11

### Added

- セッションコストを Line 4 最右に dim の `$X.XX` で表示するようにした。stdin JSON `cost.total_cost_usd` (Claude Code が cache read/write 区分込みで計算済みの API 換算額) をセント単位に四捨五入してそのまま $ 表示する。円換算は為替レートの入手手段（ネットワーク呼び出しゼロ方針との衝突）を要するため見送り。subscription 利用時は実請求なしの参考値なので、優先度の低い情報として最右・dim 配置。`$0.00`（セッション開始直後）とフィールド欠落（旧 Claude Code）では非表示。bash は float 演算ができないため jq 側で `* 100 | round` してセント整数で受け、表示は `printf -v` の整数演算のみ（fork ゼロ）

### Changed

- Built against を Claude Code 2.1.173 に追従 (`/check-claude-code-update` で 2.1.172〜2.1.173 を分析)。stdin JSON フィールドの変更はゼロ。2.1.173 の「Fable 5 の `[1m]` サフィックス正規化」は `*fable*` ワイルドカードマッチに影響なし（むしろ Line 1 が短くなる方向）

## [1.28.0] - 2026-06-10

### Added

- Fable モデル (Claude Code 2.1.170 で登場した Mythos-class の `claude-fable-5`) を Line 1 でスチールブルー (`FABLE` = `38;5;74`) で色分け表示するようにした。従来は `*opus*`/`*sonnet*`/`*haiku*` のどのワイルドカードにもマッチせず無色フォールバックだった。公式ブランド色が発表ページに記載されていないため、ヒーローアートワーク（ヴィンテージ標本画調の蝶で構成された「5」）の主役である大型のモルフォ蝶風の青から導出。74 `rgb(95,175,215)` は既存の青系 (VTEX=33, FNDY=39 の鮮やかなブルー / THINK=117 の淡い水色 / TEAL=79 のミント) と判別可能。claude.ai の UI に公式色が現れたらそちらに追従する。`*fable*` ワイルドカードなので将来の Fable 5.x も自動カバー

### Changed

- Built against を Claude Code 2.1.170 に追従 (`/check-claude-code-update` で 2.1.161〜2.1.170 の 9 リリースを分析)。stdin JSON フィールドの変更はゼロ。2.1.169 の「カスタム statusline 使用時にフッターヒントが出ない」バグは Claude Code 側で修正済みでスクリプト対応不要。表示例のモデル名と version 文字列も Fable 5 / v2.1.170 に同期

## [1.27.0] - 2026-06-02

### Changed

- Built against を Claude Code 2.1.160 に追従。別 PC 作業で upstream tracking リポ (`anthropics/claude-code` の CHANGELOG) が未同期だったため `/check-claude-code-update` での影響分析は未実施 — バッジ数値のみ更新し、`statusline-command.sh` のロジックは変更していない。あわせて README のドリフトを点検・修正: ① カラーテーマ表に vim mode バッジの色 (`INSERT`=黒文字/ライムグリーン bg `1;30;48;5;148`、`VISUAL`・`V-LINE`=黒文字/ゴールド bg `1;30;48;5;214`) を追記 (1.24.0 で追加した機能なのに表から欠落していた)、② スクリプト構造の Line 1 説明で VISUAL を「橙 bg」と誤記していたのを実定数どおり「ゴールド bg」に修正し `V-LINE` 短縮も明記、③ 表示例の version 文字列を `v2.1.146` → `v2.1.160` に同期

### Added

- Installation 手順を再構成。**リポジトリを直接参照する運用 (clone → settings.json に clone 先スクリプトの絶対パスを指定) を推奨手順に**昇格させた。コピーを作らないので single source of truth が保たれ `git pull` だけで更新が反映される (CLAUDE.md の「no copy / single source of truth」方針と整合)。公開リポジトリ (PUBLIC) からの `curl` 直接ダウンロードは「clone せず `~/.claude` に置く」**代替**として併記 — この方法はコピーなので更新が手動になる旨を明記

## [1.26.0] - 2026-05-28

### Changed

- Cold-start パス (`build_git()` の cache populate 前) で `.git/HEAD` の中身が `ref: refs/heads/.invalid` の時、`.invalid` をそのまま branch 名として表示せず dim の `(empty)` に置換するようにした。`.invalid` は Git が空リポジトリ (`git init` 直後、clone 途中失敗、`ghq get` の fetch 失敗残骸など) の HEAD placeholder として使う RFC 6761 予約名で、ユーザーから見れば「異常状態」を意味するノイズ。`(empty)` ラベルに翻訳することで、`(no git)` と同じ dim 表示で「ここは git だが commit が無い」状態を即視認できるようにする。`build_git()` 側は `git branch --show-current` が空リポで empty を返して early return するため修正不要、cold-start パスのみで完結

## [1.25.0] - 2026-05-25

### Changed

- Built against を Claude Code 2.1.150 に追従。2.1.147→2.1.150 の差分 (4 リリース分) を `/check-claude-code-update` で確認したが、statusline-command.sh に影響する変更は無し: 2.1.147 の `/simplify` → `/code-review` リネームは slash コマンド側の話で stdin スキーマ不変、2.1.149 の「skill/agent frontmatter の effort が status bar に反映」修正は Claude Code 側のバグ修正で既存の `.effort.level` 抽出ロジックで自動的に正しく動く、2.1.148 (Bash exit 127 regression fix) と 2.1.150 (internal) も無関係、その他は Windows / PowerShell / plugin / UI 系で macOS 専用本スクリプトに影響なし

## [1.24.0] - 2026-05-21

### Added

- Line 1 の**最左**に vim mode バッジを新規追加。Claude Code の vim mode (interactive-mode で `Esc` → `i` 等で操作可、4 モード: NORMAL/INSERT/VISUAL/VISUAL LINE) を stdin `.vim.mode` から取得し、`INSERT` は緑 bg、`VISUAL` / `VISUAL LINE` は橙 bg のバッジ (bold + 黒 fg) で表示。`VISUAL LINE` は `V-LINE` に短縮。**NORMAL とフィールド欠落時は非表示** (デフォルト状態のノイズ削減 + vim mode 無効セッションの graceful degradation)。Claude Code 組み込みフッターの `-- INSERT --` 表示は dim テキストで見落とされやすいため、bg 色 + bold + 最左配置で意図的に圧倒的に目立たせる住み分け設計。bats 5 ケース追加 (INSERT/VISUAL/VISUAL LINE→V-LINE 短縮/NORMAL 非表示/フィールド欠落 graceful)

## [1.23.0] - 2026-05-21

### Added

- Line 3 (git info) に PR review_state テキスト表示を新規追加。Claude Code 2.1.145+ の stdin `pr.review_state` を branch 直後に **色付きテキスト** で表示する: `approved`=緑/`changes_requested`=赤/`pending`=黄/`commented` 他=dim。**PR 番号と URL は表示しない方針** — Claude Code 組み込みフッターの PR badge (`PR #1234` リンク) が既に提供しているため重複させず、こちらはフッターが出さない review_state のみを提供して住み分ける。PR が無いブランチでは何も出さない (graceful degradation)。bats に approved / changes_requested / pending / state 空 / PR 番号非表示 の 5 ケース追加

## [1.22.0] - 2026-05-21

### Changed

- Line 3 の `gh:owner/repo` 取得を **Claude Code 2.1.145+ の stdin `workspace.repo.{host,owner,name}` 優先**に変更。Anthropic が 2.1.145 で statusline JSON に GitHub repo 情報を含めるようになったので、これを使えば ① cold start でも `gh:` を即表示できる (従来は 5s background cache populate 後)、② `git remote get-url origin` の fork が 1 回減る、③ SSH/HTTPS 正規化のロジックを bypass、というメリットがある。2.1.144 以前と origin が GitHub 以外 (GitLab 等) のケースでは従来通り `git remote` 正規化に fallback して graceful degradation。bats に新規 2 ケース追加 (`workspace.repo` あり cold-start で gh: 表示 / `workspace.repo.host=gitlab.com` で gh: 非表示)。Built against を Claude Code 2.1.146 に追従

## [1.21.0] - 2026-05-19

### Changed

- Line 2 の要素並び順を `path → (+N dirs) → 🌲 from:branch` から `path → 🌲 from:branch → (+N dirs)` に変更。🌲 は「このパスが worktree であること」を示す情報なので path 直後に置くのが自然で、`(+N dirs)` は worktree とは独立した補助情報なので末尾に回した。CLAUDE.md と README (表示レイアウト / 表示例 / スクリプト構造の 3 箇所) も併せて更新

## [1.20.0] - 2026-05-19

### Added

- Line 3 (git info) の先頭に `gh:owner/repo` (dim) を追加表示 — origin が `https://github.com/...` または `git@github.com:...` の GitHub リポジトリの場合のみ、`git remote get-url origin` を SSH/HTTPS 両形式から正規化して `owner/repo` を抽出し、ブランチ名の直前に dim で出す。`.git` サフィックスは除去。非 GitHub remote (GitLab 等) や origin 未設定では表示しない。「GitHub に上げたっけ」を即答するためのインジケータ。public/private (visibility) は GitHub API / `gh repo view` 依存で完全ローカルでは判定不能なため軽い版に留め、表示しない方針 (`gh` の active account が `gh auth switch` で切り替わると複数 org にまたがる環境では false negative を出すリスクが大きく、トレードオフが見合わないと判断)。既存の tree URL リンク生成と remote 正規化ロジックを共有してフォーク数を増やさない。detached HEAD でも origin 情報自体は有用なので統一的に表示するよう、`HEAD@*` 判定の前に remote 正規化を移動するリファクタを同時実施。Built against を Claude Code 2.1.144 に追従

## [1.19.0] - 2026-05-14

### Added

- README に「Recommended Terminal: Ghostty」セクションを追加。Claude Code 公式の [terminal-config](https://code.claude.com/docs/en/terminal-config) でも紹介されている [Ghostty](https://ghostty.org/) は、本ステータスラインの全要件 (ANSI 256 色 + truecolor、OSC 8 ハイパーリンク、低レイテンシ描画) を満たすため、推奨ターミナルとして明記。Claude Code 運用で特に効果のある機能 (OSC 8 でブランチ名/パスのクリック遷移、shell integration による cwd 自動継承と `jump-to-prompt`、`⌘D`/`⌘⇧D` の splits + `⌘T` の新規タブ、`toggle_quick_terminal` ユーザー割当の Quick Terminal、`⌘⇧,` の config hot-reload、Metal GPU レンダリング) を bullet で列挙。設定ファイルパス (`~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`) と、他ターミナル使用時に OSC 8 リンクが平文表示になり得る注意書きも併記

## [1.18.0] - 2026-05-14

### Added

- Line 3 (git info) に「切った元ブランチ」を `from:<parent>` (dim) で追加表示。`git reflog show <branch>` の最古エントリ (`branch: Created from <ref>`) をパースして取得し、worktree インジケータの `from:original_branch` と同じスタイルで揃える。reflog の GC 期間 (~90日) を超えた古いブランチや clone 直後のローカルチェックアウトされていないブランチでは表示されない (graceful degradation)。`Created from HEAD` (匿名 HEAD から作成) と detached HEAD では非表示。`build_git()` 内で従来 3 箇所に散らばっていた `[[ "$branch" != HEAD@* ]]` ガードを 1 つの if-else に集約するリファクタを同時実施。Claude Code 2.1.141 の "multi-line statusline overflow" 修正に伴い `added_dirs` の挙動を再検証したが、修正は「行落ち」を「右端切り詰め」に変えただけで狭い端末では情報が見えないままなので、`(+N dirs)` 集約表示は維持

## [1.17.0] - 2026-05-11

### Changed

- README をスクリプト実装と一致させる全面メンテナンス。カラーテーマ表の Git 記号を実装通り (`A`/`M`/`U`/`?` の git standard symbols) に修正し、欠けていた色エントリ (Agent pink `38;5;213`、version gray `38;5;248`、Git brand orange `38;5;202`、branch セッション黄、untracked gray `38;5;248`) を追加。パフォーマンスセクションのバックグラウンドキャッシュを「Usage API (300秒)」→「Subscription 種別取得 (3600秒)」に訂正、worktree 検出は `git-dir`/`git-common-dir` 比較ではなく stdin JSON の `worktree.name` / `workspace.git_worktree` (Claude Code 2.1.97+) であることを明記。Requirements を `Bash 4+` → `Bash 3.2+` (macOS 標準) に訂正し、`curl` の用途を `fetch_subscription()` 専用と明確化、macOS 専用 (`stat -f %m` / `md5 -q -s`) であることも追記。`build_git()` の説明から未実装の `stash` を削除し、Claude Code badge と表示例のバージョンを `2.1.139` に追従

## [1.16.0] - 2026-05-11

### Changed

- Effort/thinking indicator format simplified — `effort:high·think` → `high think`. プレフィックス `effort:` と中黒区切り `·` を削除し、レベル名そのまま (`low`/`high`/`max`) と `think` を半角スペース区切りで並べる。識別は色分け (`EFFORT=38;5;105` light purple、`THINK=38;5;117` light cyan) に委ねる方針。表示が短くなり Line 1 の他要素 (`Anthropic(enterprise)` 等) と視覚密度が揃う。中間変数 `_et` と `${_et:+ }` 条件区切りトリックも撤去し、`line1+=()` 2行に簡略化
- Agent indicator on Line 1 — `⚡<name>` から記号を取って `<name>` のみのピンク (`AGENT=38;5;213`) 表示に。Claude Code 2.1.139 で `claude agents` (Research Preview, agent view) が追加され、そこから起動したセッションには stdin JSON の `.agent.name="claude"` が流れてくるため、`⚡claude` が常時出るのが冗長だった。色だけで識別できるので記号は不要と判断。サブエージェント名 (`security-reviewer` 等) の表示も同形式に統一
- Context バーの低水準カラーを標準 ANSI 緑 (`GRN=\033[32m`) から bright lime green (`CTX_OK=\033[38;5;82m`) に変更 — Bedrock teal (`BDCK=38;5;72`) や暗いターミナルテーマ下での標準緑と区別がつきにくく、13% 程度の低使用率時に視認性が悪かった。`color_by_threshold` を Context バー専用関数化（`<80%`=lime / `>=80%`=黄 / `>=90%`=赤）。Git staged (`A3`) と ahead (`↑2`) は引き続き標準 ANSI 緑のまま（小さい記号なので視認性問題は出ない）

## [1.15.0] - 2026-05-07

### Added

- Branch name on Line 3 is now an OSC 8 hyperlink to the GitHub `tree/<branch>` page — クリックでブランチをブラウザで開ける。Claude Code 組み込みのフッター PR badge は PR への遷移を担うので、ここでは tree URL のみ提供して役割分担。`git remote get-url origin` を SSH (`git@github.com:owner/repo`)、SSH URL (`ssh://git@github.com/owner/repo`)、HTTPS いずれの形式からも正規化、non-GitHub remote (GitLab 等) と detached HEAD はリンク化スキップ。`gh` への依存はなくネットワーク呼び出しゼロを維持

### Fixed

- `build_git()` の dirty state カウント (`grep -c .`) に付いていた `|| echo 0` を削除 — `grep -c .` は no-match でも "0" を出力してから exit 1 するため、`|| echo 0` を付けると pipefail 環境下で stdout が "0\n0" になり、`((staged > 0))` 等が syntax error を吐いて空のバックグラウンドキャッシュが書かれる事故が起きていた。`grep -c` 単体で意図通り動く

## [1.14.0] - 2026-05-07

### Changed

- Line 3 (git info) now always shows branch only — previously, when the current directory's basename differed from the repo name (e.g. browsing a subdirectory), Line 3 prefixed the output with the repo name (`claude-code main` instead of `main`). The location-dependent format was hard to remember and surprised the user every time they hit a subdirectory. Repo identification lives entirely on Line 2 (path), which already shows the full path; Line 3 is now a consistent branch-info-only row

### Removed

- `repo_name` derivation in `build_git()` and the caller-side basename comparison + string-stripping logic — eliminates 2-3 `git rev-parse` forks (`--git-dir`, `--git-common-dir`, `--show-toplevel`) per cache refresh. The new `[[ -z "$branch" ]] && return` early-return additionally short-circuits 4 git forks (diff/ls-files/rev-list/log) for non-git directories that previously executed before silently producing nothing

## [1.13.0] - 2026-05-07

### Added

- Effort and thinking indicator on Line 1 — `effort:high·think` between model and version. Reads `.effort.level` and `.thinking.enabled` from stdin JSON (Claude Code 2.1.119+). Claude Code stopped showing effort natively in recent versions, so the statusline surfaces it again. Colors chosen to avoid collision with model tier colors (CORAL/TEAL/AMBER/LAVENDER): `EFFORT=38;5;105` (light purple), `THINK=38;5;117` (light cyan). Level severity (`low`/`medium`/`high`/`xhigh`/`max`) is conveyed by the text — color is single-hue per indicator. Older Claude Code versions without these fields render unchanged

## [1.12.0] - 2026-04-30

### Changed

- `added_dirs` indicator reverted from per-basename enumeration (`+foo +bar`) back to aggregate count (`(+N dirs)`) — with 3+ added directories, Line 2 overflowed the terminal width, wrapping the line and pushing Line 3 (git) and Line 4 (rate limit + context) below the visible statusline viewport. Aggregate count keeps Line 2 in one physical row regardless of how many directories were added; basename details remain recoverable from settings/`/add-dir` history

## [1.11.0] - 2026-04-21

### Changed

- Statusline layout expanded from 3 lines to 4 — path and git info are now on separate lines (Line 2: path/worktree, Line 3: git info). Previously, long paths + long git output combined on Line 2 often overflowed and got hidden
- `added_dirs` indicator changed from count (`(+2 dirs)`) to explicit basename enumeration (`+foo +bar`) — know at a glance which directories were added
- Parentheses removed from standalone indicators: `(branch)` → `branch`, `(+N dirs)` → `+N ...`, `(no git)` → `no git`. Parens reserved for within-element separation (e.g. `Anthropic(enterprise)`)
- Branch names in git info dropped parentheses: `(main)` → `main`, `(HEAD@abc1234)` → `HEAD@abc1234`. Git orange color already distinguishes the branch visually
- Untracked count `?N` color changed from DIM attribute to gray 248 — DIM rendering is terminal-dependent and blended visually with the adjacent DIM commit message; gray 248 is a fixed 256-color value that reliably distinguishes them

### Removed

- Terminal width adaptation — `COLUMNS`/`tput cols` detection, all `((_cols >= N))` conditionals, and width-based element hiding removed. Every element is now always shown at full length regardless of terminal width
- `_truncate_bytes` byte-level safety-net helper and its calls — no longer needed without width control
- Unreachable day branch in `format_reset_remaining` — 5h rate limit window never exceeds 5 hours, so the `%dd%dh` format was dead code

## [1.10.0] - 2026-04-13

### Removed

- Vim mode indicator (`[I]`/`[N]`) from Line 1 — Claude Code displays `-- INSERT --` / `-- NORMAL --` natively at the bottom of the screen, making the statusline indicator redundant

## [1.9.0] - 2026-04-10

### Changed

- Branch name color on Line 2 changed from green to Git brand orange (`38;5;202`, Pantone 1788C `#F03C2E`) — distinguishes branch from staged count (`A`, green) which previously blended together

## [1.8.0] - 2026-04-09

### Added

- Mantle provider detection — `CLAUDE_CODE_USE_MANTLE=1` is now detected as Bedrock (Claude Code 2.1.94+, "Amazon Bedrock powered by Mantle")
- Git linked worktree indicator — `workspace.git_worktree` (Claude Code 2.1.97+) shows 🌲 for manual `git worktree add` worktrees, not only Claude Code `--worktree` sessions
- `refreshInterval: 30` recommended in README settings example (Claude Code 2.1.97+ auto-reruns statusline every N seconds)

### Changed

- Built against badge updated from Claude Code 2.1.76 to 2.1.97

## [1.7.0] - 2026-04-06

### Added

- `/add-dir` indicator on Line 2 — shows `(+N dirs)` when directories are added via `/add-dir` (Claude Code 2.1.78+ `workspace.added_dirs`)
- OSC 8 clickable path links via `file://` on Line 2

### Changed

- Line 3 now shows only rate limits and context — removed token counts and session cost (Claude Code's `total_input_tokens` excludes cache tokens, making the display misleading)

- Dirty state symbols now use git standard: `A` (staged), `M` (modified), `?` (untracked), `U` (conflicts) — was `+`, `~`, `?`, `!`
- Worktree origin indicator changed from `←branch` to `from:branch` for clarity
- Line 3 reordered: 5h rate limit → context → ↑tokens → ↓tokens → $ → weekly (rate limit moved to leftmost for quick glance)
- Directory path is now displayed in full (no truncation); git info is truncated from the right when terminal width is limited

### Removed

- `(no name)` indicator for unnamed sessions — Claude Code shows session name natively
- Subdirectory display (`→ current_dir`) — project root is sufficient
- Stash count display — not relevant to Claude Code sessions
- Unused `session_id` jq extraction
- Dead `truncate_path` function

## [1.6.1] - 2026-04-03

### Fixed

- Worktree sessions now show the correct path and git branch — `worktree.path` from stdin JSON overrides `workspace.current_dir` which points to the original repo

## [1.6.0] - 2026-03-27

### Added

- Vim mode indicator on Line 1 — `[I]` (green) for INSERT, `[N]` (dim) for NORMAL; hidden when vim is disabled (Claude Code 2.1.84+ `vim.mode` field)
- Worktree indicator on Line 2 via stdin JSON `worktree.name` / `worktree.original_branch` — replaces git-command-based detection (zero fork, instant on cold start)
- Session cost and token counts now displayed for all providers (was Bedrock/Vertex/Foundry only) — Anthropic sessions show cost + tokens + rate limit together on Line 3

### Changed

- Worktree 🌲 detection moved from `build_git()` git commands to stdin JSON API (no git fork needed)

## [1.5.2] - 2026-03-24

### Fixed

- Line 1 width adaptation — narrow terminals progressively drop subscription type (<45), agent name (<45), and model version suffix (<35) to prevent line wrapping that blanks all statusline rows
- Skip `fetch_subscription` on narrow terminals (<45 cols) to avoid unnecessary `stat` fork

## [1.5.1] - 2026-03-24

### Changed

- Replace `vscode://file/` URI scheme with `file://` in OSC 8 path links — clicks now open Finder (editor-agnostic) instead of requiring VSCode

## [1.5.0] - 2026-03-23

### Added

- Terminal width adaptation — narrow terminals progressively drop low-priority elements (version, session indicator, weekly rate limit, git info) to prevent line wrapping that hides Line 2/3
- Path truncation (`truncate_path`) — keeps the informative tail with `…` prefix when path exceeds 40% of terminal width
- Byte-level safety-net truncation (`_truncate_bytes`) on all output lines with ANSI escape cleanup

## [1.4.0] - 2026-03-21

### Changed

- Replace `progress_bar` (10-char ●○) with `braille_bar` (5-char braille dots ⣀⣄⣤⣦⣶⣷⣿) — 40 steps of precision in half the width
- Merge Line 3 (context) and Line 4 (rate limit / cost) into a single Line 3 — output reduced from 3-4 lines to always 3

### Fixed

- Initialize all jq variables before `eval` — prevents `set -u` instant death on jq failure
- Add numeric guards (`^[0-9]+$`) to all arithmetic functions — non-numeric input returns safe fallback instead of crashing
- Show `jq error` (red) on Line 1 when stdin JSON is unparseable, with exit 0

## [1.3.1] - 2026-03-21

### Fixed

- Parse `resets_at` as Unix epoch seconds — Claude Code 2.1.80 stdin uses epoch (not ISO 8601 like the old OAuth API), restoring reset time and weekly info on Line 4
- Add `floor` guard on `resets_at` jq extraction to handle potential float epochs

### Changed

- Remove `iso_to_epoch()` — saves 2 forks per render by accepting epoch directly in `format_reset_remaining`/`format_reset_absolute`

## [1.3.0] - 2026-03-20

### Changed

- Migrate Anthropic rate limit from undocumented OAuth API to Claude Code 2.1.80+ stdin `rate_limits` field
- Remove `get_oauth_token()`, `fetch_usage()`, and usage cache — ~50 lines deleted, 1 fewer jq fork
- Pre-2.1.80 Claude Code gracefully degrades (Line 4 empty for Anthropic)

## [1.2.0] - 2026-03-17

### Added

- Show session cost and token counts on Line 4 for Bedrock/Vertex/Foundry — `$0.42 ↑125.0k ↓8.5k` (amber/teal/coral)
- Anthropic users continue to see rate limit bars as before

### Changed

- `format_tokens()` now displays one decimal place with lowercase suffix (e.g., `133.5k`, `1.5M`)

## [1.1.0] - 2026-03-17

### Changed

- Rename fork indicator to branch — detect both `(Branch)` (2.1.77+) and legacy `(Fork)`, display as `(branch)`

## [1.0.1] - 2026-03-16

### Fixed

- Suppress false "(no git)" on cold start for git repositories — use pure-bash `.git` check instead of relying on empty cache

## [1.0.0] - 2026-03-16

### Added

- Provider detection (Anthropic/Bedrock/Vertex/Foundry) with brand colors
- Model display with Anthropic brand colors (Opus=coral, Sonnet 4.6=teal, Sonnet 4.5/3.5=amber, Haiku=lavender)
- Git info: dirty state (+staged/~modified/?untracked/!conflicts), ahead/behind, stash count, last commit age+message, detached HEAD, worktree indicator
- Rate limit display for Anthropic provider
- Subscription type display from Keychain/credentials
- Session info: fork indicator (yellow), no-name indicator (dim), context window usage bar
- Background async refresh for I/O operations (git 5s, subscription 3600s)
- bats test suite with t-wada style naming (Japanese)
