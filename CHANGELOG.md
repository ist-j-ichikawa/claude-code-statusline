# Changelog

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
