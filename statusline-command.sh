#!/bin/bash
# Claude Code Statusline — see README.md for details
# https://code.claude.com/docs/en/statusline
set -uo pipefail

# Shared colors + presentation helpers (also used by subagent-statusline-command.sh)
# 相対起動 (bash statusline-command.sh) では BASH_SOURCE にスラッシュが無く %/* が縮まないため "." に fallback
_selfdir="${BASH_SOURCE%/*}"; [[ "$_selfdir" == "$BASH_SOURCE" ]] && _selfdir="."
source "$_selfdir/lib.sh"

# --- Main-only constants ---
# キャッシュはユーザー単位に隔離する。固定の共有パスだと (1) 共有 Mac の別ユーザーが 700 の
# ディレクトリに書けず git 行が永久 cold-start + usage_spend も書けず毎レンダー refetch (curl storm)、
# (2) テストが本物のキャッシュを触ってライブ statusline に偽の値を出す。macOS の TMPDIR は既に
# ユーザー単位。CLAUDE_STATUSLINE_CACHE_DIR はテスト/install の密閉 seam。
readonly CACHE_BASE="${CLAUDE_STATUSLINE_CACHE_DIR:-${TMPDIR:-/tmp}/claude-statusline-$UID}"
# 設定ディレクトリは 1 箇所で解決する — `.credentials.json` / `sessions/` / `cache/changelog.md` /
# リセットのメモキーが全部ここから派生する。展開を各所に複製すると「CLAUDE_CONFIG_DIR 対応漏れ」
# (過去に 3 箇所を 1 つずつ踏んだ) を機械的に潰せない。メタテストが直書きを禁じている以上、
# 展開そのものを共有するのが筋。
readonly CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
readonly GIT_CACHE_DIR="${CACHE_BASE}/git"
readonly GIT_CACHE_MAX_AGE=5
# untracked の行数を数える上限。**コストは総バイト数に比例するのに上限は件数なので近似指標**
# (「500 件以下なのに遅い」を上限のせいと誤診しないための注記)。実測と理由は build_git の
# untracked の節 (④) に 1 箇所だけ置いてある。
readonly UNTRACKED_FILE_CAP=500
readonly _NOW=$(date +%s)

# --- Main-only helpers (generic presentation helpers — has_val/osc8/editor_url/
# rainbow/gradient/model_color/braille_bar/color_by_threshold/format_tokens — live in lib.sh) ---

# pr_state_color STATE VARNAME — sets VARNAME to ANSI color for PR review state (no subshell)
pr_state_color() {
  case "$1" in
    approved)          printf -v "$2" '%s' "$GRN" ;;
    changes_requested) printf -v "$2" '%s' "$RED" ;;
    pending)           printf -v "$2" '%s' "$YLW" ;;
    draft)             printf -v "$2" '%s' "$DRAFT" ;;
    *)                 printf -v "$2" '%s' "$DIM" ;;
  esac
}

# cache_fmt_is FILE TAG — FILE の先頭フィールドが TAG なら rc=0（`read` のみ = fork ゼロ）。
# **延命 touch の前に必ず通す** — 形式違いのファイルを touch すると「新鮮だが使えない値」が
# 居座り、表示が TTL 分だけ欠ける。subscription と usage で同じ判定を別々に書いていたので
# 1 本に寄せた（`/simplify` 指摘）。
cache_fmt_is() {
  local _f=$1 _tag=$2 _cur=""
  [[ -r "$_f" ]] || return 1
  IFS=$'\037' read -r _cur _ < "$_f"
  [[ "$_cur" == "$_tag" ]]
}

# prefetch_mtimes FILE... — **1 回の `stat` で mtime をまとめて取る**。`cache_stale` はこの結果を
# 使うので、3 つの stale 判定で `stat` を 3 回 fork しない（実測 9.802ms → 3.146ms = **-6.7ms**、
# 暖まった描画の 16%。「制限あり 41.5ms / なし 31.0ms」の差はほぼこれだった）。
# **`stat` の出力をそのまま表として使う**（`%N %m` = 「パス 空白 mtime」の行）— 自前の区切りに
# 詰め直すと、書く側と読む側で区切りの綴りを一致させ続ける必要が出るだけで何も増えない。
# **キーは行頭でアンカーする**（先頭に `\n` を 1 個足す）— 名前で引くので、欠損ファイルで行が
# ずれて**別ファイルの mtime を読む**罠に当たらない（`%m` だけだと実測で 3 番目の値が 2 番目に入る）。
# map に無いファイルは `cache_stale` が個別 `stat` に落ちる（= 従来の挙動）。
prefetch_mtimes() {
  _MTIME_AT_START=""
  # 末尾改行が無くても `read` は内容を入れる（rc は見ない。このリポで繰り返し踏んでいる罠）
  IFS= read -r -d '' _MTIME_AT_START < <(stat -f '%N %m' "$@" 2>/dev/null) || true
  _MTIME_AT_START=$'\n'"$_MTIME_AT_START"
}

cache_stale() {
  local cache=$1 max_age=${2:-$GIT_CACHE_MAX_AGE} _mt=""
  # キーは 1 回だけ組む（3 度綴ると 1 つ typo しても黙って個別 `stat` に落ちるだけでテストは緑）。
  # **`local` を別行にする** — bash 3.2 は `local a=$1 b="…$a…"` を先に全部展開するので、
  # 同じ `local` 行で `$cache` を参照すると `set -u` で "unbound variable" になる。
  local _k=$'\n'"$cache "
  # **`-f` が「不在」と「通常ファイルでない」を 1 箇所で吸う**（まとめ取りの前に置く）—
  # `stat` はディレクトリや FIFO にも成功するので map にも入る。後ろに置くと、`md5` が PATH に
  # 無く `_gc` が git/ ディレクトリに落ちた時だけ判定を素通りする。
  [[ -f "$cache" ]] || return 0
  # まとめ取りの結果があれば fork ゼロで引く（行頭アンカーなので行ずれの影響を受けない）
  if [[ "${_MTIME_AT_START:-}" == *"$_k"* ]]; then
    _mt="${_MTIME_AT_START#*"$_k"}"; _mt="${_mt%%$'\n'*}"
  else
    _mt=$(stat -f %m "$cache" 2>/dev/null)
  fi
  # **ファイルはあるが mtime が読めない時は「古くない」に倒す**（`/code-review` 指摘）—
  # `return 0` にすると `stat` が壊れた環境で 3 つのキャッシュが毎レンダー stale になり、
  # 背景 git + `curl` が `refreshInterval` ごとに走る storm になる（このリポが名指しで
  # 避けている破綻）。鮮度が分からないなら取り直さないほうが安全。
  [[ "$_mt" =~ ^[0-9]+$ ]] || return 1
  (( _NOW - _mt > max_age ))
}

# --- キャッシュの形式タグ ---
# **フィールド一覧そのものをタグにして、レコードの先頭に入れる**（v1.77.0）。
# 読み側はタグが一致しなければ「キャッシュ無し」として扱い、**その場で取り直す**。
#
# 以前はファイル名に `-vN` を付けていたが 3 つ問題があった: ① 製品版 (`version-1.76.0`) と
# 紛らわしい ② git が `-v4` / 他が `-v2` で**意味のない序列**が見える ③ **番号を上げるのは
# 手作業で、実際に忘れて出荷した**（v1.74.0 の subscription。既存ユーザー全員が旧形式を
# 新コードで読み、レート枠が最大 1 時間欠けた）。さらに旧ファイルが孤児として並ぶので、
# どれが現行か名前から読めなかった。
#
# タグを中に入れると: 名前が安定して**孤児が出ない**（同じ名前を上書き）/ 形式を変える人は
# **必ずこの一覧を編集する**ので番号より忘れにくい / 一致しなければ即取り直すので
# 「古い形式のファイルが TTL 分だけ表示を欠かせる」が起きない。読みは fork ゼロのまま。
readonly GIT_FMT='branch,detached,repo,remote,ins,del,conf,ahead,behind,age,msg,op'
# `render_git` が使う変数名の列（宣言と分解の 2 箇所を 1 本から作る）。**`GIT_FMT` とは別に持つ** —
# 名前がずれており（`repo`/`conf` 対 `repo_id`/`conflicts`）、揃えて導出させると**ディスクの形式タグを
# 編集した人が bash のローカル変数名を暗黙にリネームする**ことになり、関数本体は旧名を参照して
# `set -u` で statusline が丸ごと空白になる。別々なら、タグ編集は「facts を捨てて cold-start」に倒れる。
readonly GIT_FIELDS='branch detached repo_id remote ins del conflicts ahead behind age msg op'
readonly SUB_FMT='type,tier'
readonly USAGE_FMT='cents,limits'
readonly RESET_FMT='e5,t5,e7,t7'

# git_cache_file DIR — sets _gc (no subshell)
git_cache_file() {
  [[ -d "$GIT_CACHE_DIR" ]] || mkdir -p -m 700 "$CACHE_BASE" "$GIT_CACHE_DIR"
  # 名前はディレクトリの md5 だけ。形式の判定はレコード先頭のタグ (`GIT_FMT`) が行う
  _gc="${GIT_CACHE_DIR}/$(md5 -q -s "$1")"
}

# --- Credentials blob (Keychain → file fallback) ---
get_credentials_blob() {
  if command -v security &>/dev/null; then
    local blob
    blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
    # `printf '%s'` を使う — blob は外部文字列で、`echo` は先頭が `-n`/`-e` の値を食う
    if [[ -n "$blob" ]]; then printf '%s\n' "$blob"; return 0; fi
  fi
  # `CLAUDE_CONFIG_DIR` を尊重する — docs は「credentials on Linux and Windows」もこの下と明記
  # (macOS は Keychain が主で、ここはその fallback)。ハードコードすると別 config dir で
  # subscription と extra-usage が無言で消える (宛名と同じ根本原因)。
  local creds="${CONFIG_DIR}/.credentials.json"
  # gate は `-f` ではなく **`-r`** — root 所有や mode 000 の credentials では `$(<file)` が
  # "Permission denied" を stderr に吐く (旧 `cat file 2>/dev/null` は黙っていた)。
  # **`$(<file 2>/dev/null)` と書いてはいけない** — bash 3.2 では `$(<file)` の特殊構文が壊れて
  # **常に空文字**になり、subscription と extra-usage が丸ごと死ぬ (bash 5 では動くので手元で気付けない)。
  [[ -r "$creds" ]] && printf '%s\n' "$(<"$creds")"
}

# --- Subscription type (cached, background refresh) ---
# 形式の判定はレコード先頭のタグ (`SUB_FMT`) が行うので、**ファイル名は安定**（孤児が出ない）。
# v1.74.0 は形式を変えたのに名前を据え置き、旧形式を読んだ**既存ユーザー全員が最大 1 時間
# `Anthropic(Max)`**（枠が欠けた形）になった。v1.74.1 で `-v2` を付け、v1.77.0 でタグ方式へ。
readonly SUB_CACHE="${CACHE_BASE}/subscription"
readonly SUB_CACHE_MAX_AGE=3600

# fetch_subscription — sets _sub_type (no subshell)
# `CLAUDE_STATUSLINE_NO_NET` は「外部への問い合わせをしない」seam なので Keychain 読みもここで止める
# (ネットワークではないが、macOS のアクセス許可ダイアログを出しうる外部参照。install.sh の試走・テストが
# ユーザーの Keychain に触らないための入口でもある)
fetch_subscription() {
  _sub_type="" _rate_tier=""
  [[ -n "${CLAUDE_STATUSLINE_NO_NET:-}" ]] && return
  [[ -d "$CACHE_BASE" ]] || mkdir -p -m 700 "$CACHE_BASE"
  # **先にキャッシュを読んでタグを検証する** — 形式が違えば値を捨てるだけでなく
  # **「古い」と同じ扱いにして即取り直す**（TTL 3600s を待たせない = v1.74.0 の症状を作らない）。
  # **read の rc は見ない** — 末尾改行が無く rc=1 でも内容は入る (宛名スキャンと同じ罠)。
  # gate は `-r`（`read < "$f" 2>/dev/null` は入力側の失敗を黙らせられない）。
  local _fmt=""
  if [[ -r "$SUB_CACHE" ]]; then
    IFS=$'\037' read -r _fmt _sub_type _rate_tier < "$SUB_CACHE"
  fi
  if [[ "$_fmt" != "$SUB_FMT" ]]; then _sub_type="" _rate_tier=""; fi
  if [[ "$_fmt" != "$SUB_FMT" ]] || cache_stale "$SUB_CACHE" "$SUB_CACHE_MAX_AGE"; then
    (
      local blob record="" sub_type="" _stf="${SUB_CACHE}.tmp-$$"
      blob=$(get_credentials_blob)
      if [[ -n "$blob" ]]; then
        # blob は accessToken を含む。here-string (`<<<`) は bash 3.2 では一時ファイル経由に
        # なるのでパイプで渡す (トークンを argv に出さないのと同じ理由でファイルにも落とさない)。
        # subscriptionType (契約種別) と rateLimitTier (レート枠) を **1 回の jq** で US 区切りで取る。
        record=$(printf '%s' "$blob" | jq -r '"\(.claudeAiOauth.subscriptionType // "")\u001f\(.claudeAiOauth.rateLimitTier // "")"' 2>/dev/null)
        sub_type="${record%%$'\037'*}"
      fi
      # 取れなくても必ず書く — 書かないと cache_stale がファイル不在で毎レンダー背景 fetch を起こし、
      # Keychain 読みの storm になる (extra-usage と同じ理由。credentials を持たない API キー /
      # env 運用のユーザーは恒常的に踏む)。空を書いても display は has_val で非表示に倒れる。
      # 既存値があるときは潰さず touch で延命する (Keychain が一時的に読めないだけで表示が消えるのを防ぐ)。
      # 延命判定は **契約種別が取れたか**で見る (レート枠だけ欠けても契約名は出せる)。
      # 延命は**現行タグのファイルに対してだけ**（`cache_fmt_is` が判定を持つ）
      if [[ -z "$sub_type" ]] && cache_fmt_is "$SUB_CACHE" "$SUB_FMT"; then
        touch "$SUB_CACHE"          # 既存値は潰さず延命する
      else
        printf '%s\037%s' "$SUB_FMT" "$record" > "$_stf" && mv "$_stf" "$SUB_CACHE"
      fi
    # `>/dev/null 2>&1` が **背景化の必須条件** — 付けないと subshell が親の stdout を継承したまま
    # 生き続け、statusline を捕捉する側 (Claude Code) は最後の fd 保持者が終わるまで EOF を見ない。
    # `& disown` だけでは「出力をブロックしない」は成立しない (実測: 冷キャッシュの大リポで
    # 50ms → 300ms、遅い curl で 3.1s。3 箇所すべてに必要)。stderr も閉じるのは、
    # 背景の警告 (Keychain 不許可等) が statusline 出力に混ざらないようにするため。
    ) >/dev/null 2>&1 & disown
  fi
}

# --- Extra-usage spend (usage-credits, cached, background refresh) ---
# stdin に無い唯一の課金情報。/usage OAuth エンドポイントの spend.used を cents で取得。
# `CLAUDE_STATUSLINE_NO_NET` を設定するとネットワーク取得を止める (オフライン/プライバシー用)。
# 形式の判定は 1 行目のタグ (`USAGE_FMT`) が行うので、**ファイル名は安定**（孤児が出ない）。
readonly USAGE_CACHE="${CACHE_BASE}/usage_spend"
readonly USAGE_CACHE_MAX_AGE=300

# fetch_usage_spend — sets _usage_cents と _scoped_limits (background curl; hot path はキャッシュ読みのみ)
#
# **モデル別の週間制限も同じレスポンスから取る** — stdin の `rate_limits` は `five_hour` と
# `seven_day` の 2 つだけで (docs の完全スキーマで確認)、`weekly_scoped` は来ない。`/usage` の
# `limits[]` に入っているので、**追加のネットワークも fork もゼロ**で足せる。
# 読むのは消費者向けに整形済みの `limits[]` だけ — トップレベルの `nimbus_quill`/`amber_ladder`/
# `tangelo` 等のコードネーム鍵は feature flag 名で churn するので使わない。
# `is_active`/`severity` でも絞らない (各 1 観測しかなく意味論が不明 = 未文書フィールド列挙の罠)。
#
# キャッシュ形式: 1 行目が cents、2 行目以降が `モデル名 US % US リセット epoch` の 1 行 1 枠。
# 旧形式 (cents 1 行だけ) を読んでも枠が 0 件になるだけなのでファイル名の版は上げない。
# **NO_NET の効き方が `fetch_subscription` と非対称**（意図的）: あちらは Keychain 読みごと止めて
# 空に倒すが、こちらは **fetch だけ止めてキャッシュは読む** — extra:$ と枠は「前回取れた値」を
# 出しても害が無く、オフラインでも直近の値が見えるほうが有用。テストもこの差に依存している。
fetch_usage_spend() {
  _usage_cents=""; _scoped_limits=""
  [[ -d "$CACHE_BASE" ]] || mkdir -p -m 700 "$CACHE_BASE"
  # 1 行目 = `タグ US cents`、2 行目以降 = モデル別週間枠。**タグが違えば値を捨てて即取り直す**
  # (SUB_CACHE と同じ作法。TTL を待つと形式変更のたびに 300s 欠ける)
  local _u_fmt=""
  if [[ -r "$USAGE_CACHE" ]]; then
    { IFS=$'\037' read -r _u_fmt _usage_cents; IFS= read -r -d '' _scoped_limits; } < "$USAGE_CACHE"
  fi
  if [[ "$_u_fmt" != "$USAGE_FMT" ]]; then _usage_cents=""; _scoped_limits=""; fi
  if [[ -z "${CLAUDE_STATUSLINE_NO_NET:-}" ]] \
     && { [[ "$_u_fmt" != "$USAGE_FMT" ]] || cache_stale "$USAGE_CACHE" "$USAGE_CACHE_MAX_AGE"; }; then
    (
      local blob token out cents=0 limits="" _usable=""
      blob=$(get_credentials_blob)
      # here-string ではなくパイプ — bash 3.2 の `<<<` は一時ファイルを作るので、
      # トークンを含む blob をディスクに落とさない (argv 露出を避けるのと同じ理由)
      token=$(printf '%s' "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
      if [[ -n "$token" ]]; then
        # ヘッダは **`-H @-`** で stdin から渡す。argv には `@-` しか出ないので `ps` 漏れは無く、
        # **各行が必ずヘッダとして解釈される**のでトークンに何が入っていても curl のオプションには化けない。
        # `--config -` を使っていた頃は各行が設定ディレクティブだったので、`"` や改行を含む値が
        # `output = <path>` の注入になりえた。字種の拒否リストで守るのではなく、
        # ディレクティブとして読まれる面そのものを無くす方針 (install.sh の `printf %q` と同じ)。
        out=$(printf 'Authorization: Bearer %s\nanthropic-beta: oauth-2025-04-20\n' "$token" \
          | curl -s -m 4 -H @- https://api.anthropic.com/api/oauth/usage 2>/dev/null)
        # **`NA` を返させて「使える応答か」を判別する** — `curl -s` は `-f` を付けていないので
        # 401/429/5xx の**エラー JSON も本文として来る**。`// 0` の既定値があるため、それでも
        # 数値 `0` が出てしまい「取得成功・課金 0」と区別できない（`/code-review` 指摘）。
        # `.spend.used.amount_minor` の有無で分岐すれば追加の fork なしで判別できる。
        cents=$(jq -r 'if (.spend.used.amount_minor? // null) == null then "NA"
                       else ((.spend.used.amount_minor) / pow(10; (.spend.used.exponent // 2) - 2)) | round end' <<< "$out" 2>/dev/null)
        if [[ "$cents" =~ ^[0-9]+$ ]]; then _usable=1; else cents=0; fi
        # モデル別の週間枠。**`resets_at` は ISO8601 文字列**で epoch ではない。jq の
        # `fromdateiso8601` は小数秒 (`.346608`) と `+00:00` オフセットを受け付けないので剥がしてから
        # 渡し、`?` と `// ""` で形式が変わった枠だけ落とす (全体を abort させない)。
        # **型ガードを通す** — 型不正の枠が 1 つあると jq が abort し、**枠が全滅する**
        # (subagent の全 abort と同じクラス)。cents は別の jq 呼び出しなので巻き込まれない
        # (2 回に分けているのはこの隔離のため。1 回にまとめると枠の abort が cents を消す)。
        # **名前から改行・タブ・US を落とす** — US 区切りのレコードに生の改行や US が入ると
        # 1 枠が 2 行に割れて桁がずれ、その枠も次の枠も落ちる (subagent 側の gsub と同じ理由)。
        # **リセット時刻はここで表示文字列まで作る** — epoch を置いて描画側で `format_reset`
        # を呼ぶと **枠 1 つあたり `date` 1 fork** がレンダーごとに乗る。枠は複数ありうるうえ
        # `refreshInterval` で 30s ごとに再実行されるので、300s しか変わらない値のために fork を
        # 払い続けることになる。`strflocaltime` の出力は `date -j -r EPOCH +"%a %H:%M"` と一致する
        # (ロケール挙動も同じ。`Sat 16:00` と `土 16:00` の両方で実測して突き合わせ済み)。
        # **分単位に丸める** — `/usage` の `resets_at` は毎リクエスト再計算されて分境界をまたぐ
        # (実測: 同じリセットが `06:59:59.987654+00:00` と `07:00:00.155204+00:00` の両方で返る)。
        # 小数を切り捨てるだけだと表示分が `15:59` / `16:00` で揺れ、300s キャッシュのたびに変わる。
        # 表示は `%H:%M` なので分丸めが必要な精度そのもの。stdin 由来の `week:` は安定した epoch が
        # 来るのでこの問題は無い (揺れるのは `/usage` 側だけ)。
        limits=$(jq -r '
          (.limits // []) | map(select(
              (type == "object") and (.group? == "weekly")
              and ((.scope?.model?.display_name? // "") != "")
              and ((.percent? | type) == "number")))
          | map("\(.scope.model.display_name | gsub("[\r\n\t\u001f]"; " "))\u001f\(.percent | round)\u001f\(
              (((.resets_at // "") | tostring
                | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z")
                | fromdateiso8601? | (. / 60 | round) * 60
                | strflocaltime("%a %H:%M")?) // ""))")
          | .[]' <<< "$out" 2>/dev/null)
      fi
      # **必ず何かは書く** — 書かないと cache_stale が (ファイル不在=stale で) 毎レンダー refetch して
      # curl storm になる (extra-usage 0 のユーザーが大多数なので致命的)。
      # **ただし取得できなかったときは既存値を touch で延命する** (`fetch_subscription` と同じ作法) —
      # Wi-Fi 断や `curl -m 4` のタイムアウトで `out` が空になると cents=0 / 枠 0 件になり、
      # 上書きすると **ディスクに良い値があるのに extra:$ と全枠が 300s 消える**。
      # touch なら storm も防げて表示も保たれる (取れた時だけ内容を差し替える)。
      # 中間ファイル名に PID を入れる — 固定名だと同一 dir の並走セッション (refreshInterval で
      # 定期再実行 × 複数ペイン) が同じ .tmp に同時書き込みし、mv が atomic でも内容が混ざる
      # 1 行目 = cents、2 行目以降 = モデル別週間枠。枠が 0 件でも 1 行目は必ず書く。
      # 延命は**現行タグのファイルに対してだけ**（`cache_fmt_is` が判定を持つ）。
      # 判定は **パース結果**（`fetch_subscription` と同じ作法）— 応答が空でも、
      # エラー本文が来た場合でも「使えなかった」なら既存値を残す
      if [[ -z "$_usable" ]] && cache_fmt_is "$USAGE_CACHE" "$USAGE_FMT"; then
        touch "$USAGE_CACHE"
      else
        printf '%s\037%s\n%s' "$USAGE_FMT" "$cents" "$limits" > "${USAGE_CACHE}.tmp-$$" \
          && mv "${USAGE_CACHE}.tmp-$$" "$USAGE_CACHE"
      fi
    # `>/dev/null 2>&1` は必須 (継承 stdout で捕捉側の EOF が遅れる。fetch_subscription の注記参照)。
    # ここが最も効く — `curl -s -m 4` は最大 4 秒粘るので、無いとレンダーが 4 秒止まる
    ) >/dev/null 2>&1 & disown
  fi
}

# render_scoped_limits — _scoped_limits の各行を line_lim に足す (**fork ゼロ**)。
# `Fable:39%` の形で、**モデル名は Line 1 と同じ model_color** (Fable なら FABLE_PAL の多色)。
# `:N%` は**無色の通常輝度**（宛名やパス名と同じ扱い）。リセット時刻だけ week: と同じ dim。
# 3 番目のフィールドは**背景側で整形済みのリセット表示文字列**なので、ここで `date` を呼ばない
# (枠 1 つあたり 1 fork × refreshInterval ごとの再実行になる)。
render_scoped_limits() {
  [[ -n "$_scoped_limits" ]] || return
  local _rest="$_scoped_limits" _line _tmp _name _pct _reset_txt _col
  while [[ -n "$_rest" ]]; do
    _line="${_rest%%$'\n'*}"
    if [[ "$_rest" == *$'\n'* ]]; then _rest="${_rest#*$'\n'}"; else _rest=""; fi
    [[ -n "$_line" ]] || continue
    _name="${_line%%$'\037'*}"
    _tmp="${_line#*$'\037'}"
    _pct="${_tmp%%$'\037'*}"
    _reset_txt="${_tmp#*$'\037'}"
    # 名前と % が揃わない行は落とす (形式が変わっても他の枠と cents は生きる)
    [[ -n "$_name" && "$_pct" =~ ^[0-9]+$ ]] || continue
    model_color _col "$_name"
    # **`:N%` は無色の通常輝度**（宛名やパス名と同じ扱い）。dim だと数値が沈んで読めない。
    # 閾値色（緑/黄/赤）は試したうえで却下 — モデル名が既に色を持つので 1 要素に 2 系統の色が
    # 入って賑やかになる。色はモデルの識別に使い、数値は輝度で立てる。
    # `model_color` は末尾に RST を付けて返すので、ここで重ねない
    line_lim+=("${_col}:${_pct}%")
    [[ -n "$_reset_txt" ]] && line_lim+=("${DIM}${_reset_txt}${RST}")
  done
}

# --- Reset-time memo (stdin 由来の epoch → 表示文字列) ---
# **`date` を叩くのは epoch が変わったときだけ** = 5h / 7d に 1 回。従来は毎レンダー 2 回叩いていて、
# 実測で `date -j` 1 回 4.15ms を 1 描画に 2 回 = 約 8ms 払っていた。
# リセット時刻の epoch はリセットまで動かないので、整形結果を覚えておけば丸ごと省ける
# (使用率そのものは使うたび変わるのでキャッシュ不可 — 覚えるのは epoch→時刻の写像だけ)。
#
# **cache の値は epoch が一致したときしか使わない**。だから「cache に stdin 由来値を置かない」
# 不変条件に触れない — 不一致は `date` に落ちるだけで、他セッションの値が表示に出る経路が無い。
#
# **ファイル名に config dir を混ぜる** — `CACHE_BASE` は UID 単位なので、`CLAUDE_CONFIG_DIR` で
# 複数アカウントを併用して同時に走らせると 5h の epoch が違い、互いに上書きし合って
# **毎レンダー date + mv** になり最適化前より遅くなる。fork ゼロの文字列置換でキーを分ける。
_rc_key="$CONFIG_DIR"
readonly RESET_CACHE="${CACHE_BASE}/resets${_rc_key//\//_}"

# format_reset EPOCH FMT — sets _reset を `date` の FMT で整形した文字列にする (1 fork: date)
# 5h は `%H:%M`（時刻のみ）、週間は `%a %H:%M`（曜日つき）で、**曜日の有無が両者の区別**になる
# (`19:31` = 5h / `土 16:00` = 週間。5h の窓は最大 5 時間なので曜日は要らない)。
# **呼ぶのは `_memo_reset` からだけ** — あちらが epoch でメモ化するので、この fork は
# リセットを跨いだ時にしか走らない。ユーザーが絶対時刻を選択。2026-08-15。
format_reset() {
  _reset=""
  # `""` / `null` も数値マッチで落ちるので、別途の空判定は要らない
  [[ "$1" =~ ^[0-9]+$ ]] || return
  _reset=$(date -j -r "$1" +"$2" 2>/dev/null)
}

# _memo_reset EPOCH CACHED_EPOCH CACHED_TEXT FMT OUTVAR — sets OUTVAR と `_memo_dirty`
# **5h と週間で同型なので 1 本にする** — arm を複製すると「過ぎた epoch は `now`」のような
# 全枠に効くべき判定を片方だけに書いてしまう (実際に 5h だけに入れて非対称になった)。
_memo_reset() {
  local ep="$1" cep="$2" ctxt="$3" fmt="$4" out="$5"
  printf -v "$out" '%s' ""
  [[ "$ep" =~ ^[0-9]+$ ]] || return
  # **過ぎた epoch は `now`** — 絶対時刻だけ出すと `14:03` や `土 16:00` が「これからリセット」と
  # 読めてしまい、実際は過ぎている (窓がロールオーバー済み / stdin の値が遅れている) のに
  # 「あと N 時間」と誤読させる。曜日つきの週間側ほど強く効く。
  # **メモには入れない** — 時間で変わる値を覚えると、epoch が一致する限り hit して古い表示が残る。
  if ((ep <= _NOW)); then printf -v "$out" '%s' "now"; return; fi
  if [[ "$ep" == "$cep" && -n "$ctxt" ]]; then printf -v "$out" '%s' "$ctxt"; return; fi
  format_reset "$ep" "$fmt"
  printf -v "$out" '%s' "$_reset"
  # **書くのは値が取れた時だけ** — 空を覚えると `-n "$ctxt"` を自分で満たせず、毎レンダー
  # `date` + `mv` を払い続ける (メモ化がコスト増になる唯一の経路)
  [[ -n "$_reset" ]] && _memo_dirty=1
}

# resolve_resets FIVE_EPOCH SEVEN_EPOCH — sets _five_txt / _seven_txt
resolve_resets() {
  local fe="$1" se="$2" c5="" t5="" c7="" t7=""
  _memo_dirty=0
  # **read の rc は見ない** — 末尾改行が無いので rc=1 でも内容は入る (宛名スキャンと同じ罠)。
  # gate は `-r`（`read < "$f" 2>/dev/null` は入力側の失敗を黙らせられない）。
  local mfmt=""
  if [[ -r "$RESET_CACHE" ]]; then
    IFS=$'\037' read -r mfmt c5 t5 c7 t7 < "$RESET_CACHE"
  fi
  # 形式が違えばメモを空扱いにする（`date` に落ちるだけなので誤表示の経路は無い）
  [[ "$mfmt" == "$RESET_FMT" ]] || { c5="" t5="" c7="" t7=""; }
  # **タイムゾーン名は出さない**（v1.79.0 でユーザー選択。v1.78.0 で `JST 19:31` と出していた）—
  # 画面の時刻は**すべて例外なくこのマシンのローカル TZ** なので、ゾーン名は情報を増やさない。
  # Claude Code 自身も専用の TZ 設定を持たず OS のゾーンを使うので、両者が食い違うこともない。
  # 「どのゾーンか」は README / docs に書く（1 度読めば済む話を毎描画に置かない）。
  _memo_reset "$fe" "$c5" "$t5" "%H:%M" _five_txt
  _memo_reset "$se" "$c7" "$t7" "%a %H:%M" _seven_txt
  # 書くのはリセットを跨いだ時だけ。atomic mv は 1 fork だが 5h に 1 回なので影響しない
  # (中間ファイル名に PID を入れるのは並走ペインが同じ .tmp を潰し合わないため)。
  if ((_memo_dirty)); then
    [[ -d "$CACHE_BASE" ]] || mkdir -p -m 700 "$CACHE_BASE"
    printf '%s\037%s\037%s\037%s\037%s' "$RESET_FMT" "$fe" "$_five_txt" "$se" "$_seven_txt" \
      > "${RESET_CACHE}.tmp-$$" && mv "${RESET_CACHE}.tmp-$$" "$RESET_CACHE"
  fi
}

# --- 最新版から遅れているときだけ版を立てる ---
# **最新版は Claude Code 自身が置いたキャッシュから読む** — `<config dir>/cache/changelog.md` の
# 冒頭の `## X.Y.Z` が最新リリース (Claude Code が定期取得する。`~/.claude.json` の
# `changelogLastFetched` が取得時刻)。**ネットワークもキャッシュ書き込みも fork もゼロ**で、
# 「latest を知る」という本来ネットワークが要る情報を**ローカル読み 1 回**で得る。
# 却下: npm registry を背景 curl する案 — 遅れの検知は「latest との差」だけが要件で、
# Claude Code が既に取ってきた答えがディスクにあるのに 2 本目のネットワークを足す理由が無い。
# **事実 (latest) と色は分ける** — 他の要素 (build_git/render_git、model_key/model_color) と同じ
# 作法。抽出が壊れたのか色の判定が変わったのかをテストから切り分けられる。

# latest_cc_version VARNAME — sets VARNAME に changelog キャッシュ冒頭の `## X.Y.Z` (無ければ空)
# **読む行数に上限を置く** — `## ` を持たない形式に変わったとき、上限が無いと 500KB 超を毎レンダー
# 読み切る (transcript の forkedFrom スキャンと同じ cap の作法)。見出しは冒頭数行にあるので 20 行で十分。
latest_cc_version() {
  local line scan=0 cl="${CONFIG_DIR}/cache/changelog.md"
  printf -v "$1" '%s' ""
  # gate は `-r`（`< "$f" 2>/dev/null` はリダイレクトが先に評価されるので入力側の失敗を黙らせられない）
  [[ -r "$cl" ]] || return
  while IFS= read -r line; do
    # `## ` で始まる最初の行が最新版。`# Changelog` の見出しは `## ` に当たらない
    if [[ "$line" == '## '* ]]; then printf -v "$1" '%s' "${line#'## '}"; return; fi
    ((++scan >= 20)) && return
  done < "$cl"
}

# resolve_version_color VERSION — sets _ver_col
# **遅れの判定は数値比較** (`ver_older`) — 文字列比較だと `2.1.9` > `2.1.10` になる。
# 読めない / 形式が変わった / 追いついている ときは**すべて dim に落ちる** = 無表示に倒す
# （このリポの「無表示 < 誤読させる表示」。changelog は未文書の内部ファイルなので特に）。
# **窓もタイムスタンプも持たない** — 状態は「今の版 vs 最新版」だけで決まるので、更新すれば
# 次のレンダーで自然に dim へ戻る。書き込みが無い＝並走ペインの競合も無い。
resolve_version_color() {
  local latest=""
  _ver_col="$DIMVER"
  latest_cc_version latest
  ver_older "$1" "$latest" && _ver_col="$VEROLD"
}



# --- JSON extraction (single jq call) ---
# **stdin は変数に読まない** — `$( )` が継承するので、渡し直す口（here-string / プロセス置換）が要らない。

# Initialize all jq variables — prevents set -u instant death if eval fails
model="" model_id="" current_dir="." used_pct=""
exceeds_200k="false" cc_version="" session_name="" session_id="" transcript_path=""
agent_name="" ctx_window_size=0
five_pct="" five_reset_epoch="" seven_pct="" seven_reset_epoch=""
wt_name="" wt_path="" wt_orig_branch="" added_dirs_count=0 ws_git_worktree=""
ws_repo_host="" ws_repo_owner="" ws_repo_name="" ws_repo_id=""
pr_review_state=""
vim_mode=""
effort_level="" thinking_enabled="false" fast_mode="false" output_style=""
cost_cents=0 dur_sec=0
_jq_ok=1
_jq_out=$(jq -r '
  @sh "model=\(.model.display_name // "Unknown")",
  @sh "model_id=\(.model.id // "")",
  @sh "current_dir=\(.workspace.current_dir // ".")",
  @sh "used_pct=\(.context_window.used_percentage // "")",
  @sh "exceeds_200k=\(.exceeds_200k_tokens // false)",
  @sh "cc_version=\(.version // "")",
  @sh "session_name=\(.session_name // "")",
  @sh "session_id=\(.session_id // "")",
  @sh "transcript_path=\(.transcript_path // "")",
  @sh "agent_name=\(.agent.name // "")",
  @sh "ctx_window_size=\(.context_window.context_window_size // 0)",
  @sh "five_pct=\(.rate_limits.five_hour.used_percentage // null | if . == null then "" else round end)",
  @sh "five_reset_epoch=\(.rate_limits.five_hour.resets_at // null | if . == null then "" else floor end)",
  @sh "seven_pct=\(.rate_limits.seven_day.used_percentage // null | if . == null then "" else round end)",
  @sh "seven_reset_epoch=\(.rate_limits.seven_day.resets_at // null | if . == null then "" else floor end)",
  @sh "wt_name=\(.worktree.name // "")",
  @sh "wt_path=\(.worktree.path // "")",
  @sh "wt_orig_branch=\(.worktree.original_branch // "")",
  @sh "added_dirs_count=\(.workspace.added_dirs // [] | length)",
  @sh "ws_git_worktree=\(.workspace.git_worktree // "")",
  @sh "ws_repo_host=\(.workspace.repo.host // "")",
  @sh "ws_repo_owner=\(.workspace.repo.owner // "")",
  @sh "ws_repo_name=\(.workspace.repo.name // "")",
  @sh "pr_review_state=\(.pr.review_state // "")",
  @sh "vim_mode=\(.vim.mode // "")",
  @sh "effort_level=\(.effort.level // "")",
  @sh "thinking_enabled=\(.thinking.enabled // false)",
  @sh "fast_mode=\(.fast_mode // false)",
  @sh "output_style=\(.output_style.name // "")",
  @sh "cost_cents=\(.cost.total_cost_usd // 0 | . * 100 | round)",
  @sh "dur_sec=\(.cost.total_duration_ms // 0 | . / 1000 | floor)"
' 2>/dev/null) || _jq_ok=0
if ((_jq_ok)); then eval "$_jq_out" || true; fi

# Claude Code 2.1.145+ workspace.repo: precompute "owner/repo" once, share between build_git and cold-start.
# Empty unless stdin actually provided a GitHub repo identity — both call sites use this as the gate.
if [[ "$ws_repo_host" == "github.com" ]] && has_val "$ws_repo_owner" && has_val "$ws_repo_name"; then
  ws_repo_id="${ws_repo_owner}/${ws_repo_name}"
fi

# worktree sessions: workspace.current_dir points to original repo
if [[ -n "$wt_path" ]]; then
  current_dir="$wt_path"
fi

# --- Git info (5s cached) ---
# build_git DIR — git の「事実」だけを US(0x1f) 区切りで 1 行に出す (ANSI も stdin 由来値も混ぜない)。
# 表示は render_git() が一手に引き受ける。事実だけをキャッシュするのが要点:
#  - レコードは **`GIT_FMT` タグ + 12 フィールド**: branch detached repo_id remote ins del
#    conflicts ahead behind age msg op（位置で読むので、この一覧と `GIT_FMT` と `render_git` の
#    分解ループの変数列は常に同時に直す）
#  - 3 経路 (非 detached / detached / cold-start) で gate を揃える必要が消える
#    — cold-start は「多くのフィールドが空の facts」に退化するだけで、判断は presenter に 1 箇所化される
#  - cache key は md5(dir) だけなので、stdin 由来値 (pr.review_state 等) を混ぜると同一 dir の
#    別セッションが最大 5s 相手の値を出す。facts しか置かなければ構造的に起こらない
# フィールド順: branch detached repo_id remote ins del conflicts ahead behind age msg
build_git() {
  local dir=$1 branch detached=0

  branch=$(git -C "$dir" branch --show-current 2>/dev/null)
  if [[ -z "$branch" ]]; then
    branch=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
    [[ -n "$branch" ]] && detached=1
  fi
  # Not a git repo (or fresh repo with no commits): nothing to cache
  [[ -z "$branch" ]] && return

  local repo_id="" remote="" ins=0 del=0 conflicts=0
  local ahead=0 behind=0 age="" msg="" op=""

  # 進行中の git 操作 (rebase / merge / cherry-pick / revert / bisect)。
  # **`HEAD@<sha>` だけでは「sha を直接 checkout した」と「rebase 中」が区別できない** — 実測で
  # worktree が rebase 中に detached になり、Line 3 が `HEAD@3869b01` だけになって
  # 「表示が変」と読まれた (どちらも同じ見た目なので状況を取れない)。
  # git dir は worktree だと `<repo>/.git/worktrees/<name>` なので `rev-parse` で引く
  # (背景実行なのでこの 1 fork は hot path に乗らない)。**中の判定は `[[ ]]` と `$(<file)` だけ**で
  # fork を増やさない。進捗ファイルは interactive rebase が `msgnum`/`end`、
  # `git am` 系の rebase-apply が `next`/`last` (名前が違うので両方見る)。
  # **読めない / 数値でないときは番号を出さず操作名だけ** (無表示に倒す)。
  # **進捗ファイルは arm で決める** — レイアウトは排他 (interactive rebase = `msgnum`/`end`、
  # `git am` 系の rebase-apply = `next`/`last`) なので、後から 4 通り試す形にすると
  # 「どちらでもない読み落ち」をフォールバックが隠す。
  local _gd _cf="" _tf="" _cur _tot
  _gd=$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null)
  if [[ -n "$_gd" ]]; then
    # **arm はディスクレイアウト 1 つに 1 本**。操作名は arm の中で導出する — `rebase-apply` を
    # 2 arm に分けると進捗ファイルの組（`next`/`last`）が複製され、名前が変わったとき片方だけ
    # 直す事故になる（`/simplify` 指摘）
    if   [[ -d "$_gd/rebase-merge" ]]; then op="rebase"; _cf="$_gd/rebase-merge/msgnum"; _tf="$_gd/rebase-merge/end"
    elif [[ -d "$_gd/rebase-apply" ]]; then
      # `rebase-apply` は `git am` でも作られる。`applying` があれば am（`git rebase --abort` を
      # 打とうとして「am には無い」と気づく手戻りを防ぐ）
      if [[ -f "$_gd/rebase-apply/applying" ]]; then op="am"; else op="rebase"; fi
      _cf="$_gd/rebase-apply/next"; _tf="$_gd/rebase-apply/last"
    elif [[ -f "$_gd/MERGE_HEAD" ]];        then op="merge"
    elif [[ -f "$_gd/CHERRY_PICK_HEAD" ]];  then op="cherry-pick"
    elif [[ -f "$_gd/REVERT_HEAD" ]];       then op="revert"
    elif [[ -f "$_gd/BISECT_LOG" ]];        then op="bisect"
    fi
    # rebase 以外は `_cf`/`_tf` が空なので `-r` が偽 = 素通り。読めない/数値でなければ操作名だけ出す
    if [[ -r "$_cf" && -r "$_tf" ]]; then
      _cur=$(<"$_cf"); _tot=$(<"$_tf")
      [[ "$_cur" =~ ^[0-9]+$ && "$_tot" =~ ^[0-9]+$ ]] && op="${op} ${_cur}/${_tot}"
    fi
  fi

  # origin (dir の事実)。stdin の workspace.repo は使わない — cache に stdin 由来値を混ぜないため。
  # background 実行なのでこの 1 fork は hot path に乗らない (presenter 側で stdin 値を優先する)。
  remote=$(git -C "$dir" remote get-url origin 2>/dev/null)
  case "$remote" in
    git@github.com:*)        remote="https://github.com/${remote#git@github.com:}" ;;
    ssh://git@github.com/*)  remote="https://github.com/${remote#ssh://git@github.com/}" ;;
    https://github.com/*)    ;;
    *)                       remote="" ;;
  esac
  remote="${remote%.git}"
  [[ -n "$remote" ]] && repo_id="${remote#https://github.com/}"

  # Dirty state = **行数の増減** (`+470 -105`)。Claude Desktop の code 画面と同じ単位・同じ色で、
  # ファイル状態ごとの件数 (旧 `A3 M6 ?1`) は出さない (v1.74.0、ユーザー選択)。
  #
  # - `diff HEAD` は **staged と unstaged を合算**する — Desktop の「ワーキングツリー」表示と同じ範囲。
  #   分けて出していた頃の `A`(staged) / `M`(unstaged) の区別は無くなる。
  # - **untracked の行は追加側に畳む** — Desktop は untracked を `added` として扱い専用の記号を持たない。
  #   `git diff` は untracked を含まないので別途数える。`xargs -0 cat` なのでファイル数に関係なく
  #   **ファイル数に依存しない fork 数**で数える (ファイルごとに開くと N fork になる)。
  #   厳密な定数ではない — `xargs` は ARG_MAX を超える件数で grep を複数回起動する。
  #   `-z` + `-0` で空白入りパスに対応する。
  # - **binary は行数を持たない** (`numstat` が `-` を出す) のでスキップする。
  # NOTE: `grep -c .` は no-match でも "0" を出力してから exit 1 する。`|| echo 0` を付けると
  # pipefail 環境下で stdout が "0\n0" になり ((var > 0)) が syntax error を吐く。grep -c 単体で十分。
  # 行数カウントは空行も数えたいので `grep -c .` ではなく **`grep -c ''`** を使う。
  local _ni _nd _np
  while IFS=$'\t' read -r _ni _nd _np; do
    [[ "$_ni" =~ ^[0-9]+$ && "$_nd" =~ ^[0-9]+$ ]] || continue   # binary の `-` を捨てる
    ((ins += _ni)); ((del += _nd))
  done < <(git -C "$dir" diff HEAD --numstat 2>/dev/null)
  # untracked の行数。3 つの罠を同時に踏むので、素朴な `xargs -0 cat | grep -c` にはしない
  # (いずれも stderr も出ずに**黙って数が狂う / 永久に止まる**):
  #  ① **`cd "$dir"` してから数える** — `git -C dir ls-files` は dir 相対のパスを出すが
  #     `xargs` はカレントで動くので、cd しないと 1 件も読めず untracked が常に 0 になる。
  #     `-- ':/'` でリポジトリ全体を対象にする (`diff HEAD` は cwd に関係なくリポ全体を見るので、
  #     付けないとサブディレクトリ滞在時にスコープがずれる)。`:/` でもパスは cd 先からの相対なので
  #     toplevel を引く追加 fork は要らない。
  #  ② **`--` でオプション終端する** — `-n` という名の untracked ファイルは `cat -n` に化けて
  #     **その分の行が消え** (実測 5 → 3)、`--bogus` なら `illegal option` で
  #     **untracked 全体が 0 になる** (実測 4 → 0)。字種の拒否リストではなく発生条件を消す方針。
  #  ③ **regular file だけに絞る** — `ls-files --others` は **symlink を列挙する**ので、
  #     FIFO やデバイスを指す symlink があると読み込みが**永久にブロック**する (実測: 4 秒で
  #     完了せず)。build_git が完走しないと cache の mtime が更新されず、5s の `cache_stale` が
  #     毎レンダー新しい背景 job を spawn し続ける (表示は出続けるので沈黙した破綻)。
  #     git の意味論でも symlink の「内容」はリンク先パス 1 行なので、辿るのは numstat と食い違う。
  # 数えるのは `cat` ではなく **`grep -Ihc`** — `-I` が**バイナリを飛ばす**ので
  # 「バイナリは行数を持たないので数えない」(tracked 側の numstat `-` ガードと同じ約束) が
  # untracked 側でも成立し、しかも `cat` + `grep` の 2 fork が grep 1 つに減る。
  # `-h` でパスを出させない (件数だけ来るのでパスに `:` が入っても解析が要らない)。
  #  ④ **件数に上限を置く** — 数えるコストは untracked の**総バイト数**に比例するので、
  #     `node_modules` や `venv` を ignore していないリポ (実測 30,000 件) では **5.17 秒**かかる。
  #     `GIT_CACHE_MAX_AGE=5` を超えるので書き終えた時点で既に stale = 毎レンダー全走査し直し、
  #     しかも背景 job が重なって積もる (symlink→FIFO で踏んだのと同じ形の破綻)。
  #     上限を超えたら**untracked を数えない** (0 に倒す)。途中まで数えた合計は「間違った数」に
  #     なるので、部分集計はしない。**`+N` 要素そのものは残る** — tracked 側は git が数えた正確な
  #     値なので落とす理由が無く、落とすとかえって情報が減る（`/code-review` の指摘を受けて明文化）。
  #     つまり上限超過時の `+N` は「tracked の増減」であって「全変更」ではない。500 件超は
  #     ignore 設定の漏れなので、その状態を直すほうが先という判断。印を付ける案は却下 —
  #     Line 3 に新しい記号を増やす価値が、この稀なケースに見合わない。
  local _utl
  _utl=$( cd "$dir" 2>/dev/null || exit 0
          _paths=()
          while IFS= read -r -d '' _p; do
            [[ -f "$_p" && ! -L "$_p" ]] || continue
            _paths+=("$_p")
            ((${#_paths[@]} > UNTRACKED_FILE_CAP)) && break
          done < <(git ls-files --others --exclude-standard -z -- ':/' 2>/dev/null)
          # 0 件 (printf が空引数を渡してしまう) と cap 超過はどちらも数えない。
          # bash 3.2 の `set -u` は空配列の展開で即死するので `[@]+` を付ける
          ((${#_paths[@]} == 0 || ${#_paths[@]} > UNTRACKED_FILE_CAP)) && { printf '0\n'; exit 0; }
          printf '%s\0' "${_paths[@]+"${_paths[@]}"}" \
          | xargs -0 grep -Ihc -- '' 2>/dev/null \
          | { _s=0
              while IFS= read -r _l; do
                [[ "$_l" =~ ^[0-9]+$ ]] && ((_s += _l))
              done
              printf '%s\n' "$_s"; } )
  [[ "$_utl" =~ ^[0-9]+$ ]] && ((ins += _utl))
  conflicts=$(git -C "$dir" diff --name-only --diff-filter=U 2>/dev/null | grep -c .)

  if git -C "$dir" rev-parse --abbrev-ref '@{upstream}' &>/dev/null; then
    ahead=$(git -C "$dir" rev-list --count '@{upstream}..HEAD' 2>/dev/null)
    behind=$(git -C "$dir" rev-list --count 'HEAD..@{upstream}' 2>/dev/null)
  fi

  # Last commit age + message (single git log call)
  local last_epoch log_output
  log_output=$(git -C "$dir" log -1 --pretty=$'%ct\n%s' 2>/dev/null)
  last_epoch="${log_output%%$'\n'*}"
  msg="${log_output#*$'\n'}"
  if [[ "$last_epoch" =~ ^[0-9]+$ ]]; then
    # 単位は常に 1 つ (Line 4 の経過と同じ作法)。**どの古さでも必ず埋める** —
    # 7 日超で age を空にしていた頃は render_git の gate が `-n "$age" && -n "$msg"` /
    # `elif -n "$age"` の 2 本しかないため **msg も連鎖して落ち、Line 3 がブランチ名だけ**になった
    # (最終コミットが 1 週間以上前のリポで再現。コミット無しと古いだけの区別も付かない)。
    # gate を足すのではなく空の age が生まれる条件を消す方針 (v1.62.0)。
    # **絶対時刻で出す**（v1.78.0、ユーザー選択。従来は `41m` / `2d` の相対表記）—
    # 「19 分前」ではなく「何時のコミットか」を知りたい、という要望。リセット時刻を絶対に
    # 揃えたのと同じ方向で、**画面上の時刻表記が 1 種類に寄る**（残る相対表記はセッション経過だけ）。
    # `date` の fork はここ（背景の `build_git`）なので hot path に乗らない。
    # **180 日以内は年を省く** — `08-17T13:13` で足り、年まで出すと Line 3 が伸びる。
    # それより古ければ時刻を捨てて `2025-08-17` にする（古いコミットに分単位の意味は無い）。
    local diff=$((_NOW - last_epoch))
    # 書式は **ISO 8601 風**（`08-17T13:13`）— 区切りは `-`、日付と時刻の間は `T`。
    # 年は省く（180 日超だけ `2025-08-17` で年を出し、時刻を捨てる）
    if ((diff < 15552000)); then age=$(date -j -r "$last_epoch" +"%m-%dT%H:%M" 2>/dev/null)
    else                         age=$(date -j -r "$last_epoch" +"%Y-%m-%d" 2>/dev/null); fi
    [[ -z "$age" ]] && age="?"   # 変換できなくても空にしない（空だと msg が連鎖して落ちる）
  else
    msg=""
  fi
  [[ ${#msg} -gt 20 ]] && msg="${msg:0:20}.."
  # 事実の中に区切り文字や改行が混ざると桁がずれる (branch 名は改行を持てないが msg は持てる)
  msg="${msg//$'\n'/ }"; msg="${msg//$'\037'/ }"

  local US=$'\037'
  # **先頭に形式タグ (`GIT_FMT`)** — 読み側はこれが一致しないレコードを捨てて取り直す。
  # フィールドを足す / 並べ替える / 意味や単位を変えるときは `GIT_FMT` の一覧も直すこと
  # (一覧がそのままタグなので、直せば旧キャッシュは自動的に無効になる)。
  printf '%s\n' "${GIT_FMT}${US}${branch}${US}${detached}${US}${repo_id}${US}${remote}${US}${ins}${US}${del}${US}${conflicts}${US}${ahead}${US}${behind}${US}${age}${US}${msg}${US}${op}"
}

# render_git FACTS — facts (build_git の出力 / cold-start の合成) + stdin 由来値から line_git を組む。
# 表示判断はここだけにある。stdin 由来値 ($ws_repo_id / $pr_review_state) は cache に入れず毎回ここで足す。
# 第 2 引数 = **Line 2 が実際に描いたパス** (worktree では repo root で切った側)。`gh:` の畳み込みが
# 参照する。グローバル参照にすると「Line 2 区画の後で呼ぶ」という暗黙の順序依存になり、
# 並べ替えたときに **fallback が黙って別の値を使って畳みが効かなくなる** (テストも stderr も赤くならない)。
render_git() {
  # 宣言と分解は `GIT_FIELDS` の 1 本から作る（`local $var` の word splitting は bash 3.2 で動く）
  local $GIT_FIELDS
  local screen_dir="${2:-$current_dir}"
  # **here-string を使わない** — bash 3.2 の `<<<` は一時ファイルを作るので、`read <<<` は
  # 実測 1.679ms（パラメータ展開の分割なら 0.083ms）。hot path なので毎描画に乗る。
  # **末尾に US を 1 個足す**と「区切りが残っているか」の分岐が要らなくなる — 尽きた後は
  # 空文字が続き、フィールド数より短いレコード（cold-start の 2 個）でも残りが空になる。
  local _rest="$1"$'\037' _f
  for _f in $GIT_FIELDS; do
    printf -v "$_f" '%s' "${_rest%%$'\037'*}"
    _rest="${_rest#*$'\037'}"
  done
  [[ -z "$branch" ]] && return

  # .invalid: Git が空リポ (git init 直後 / clone 失敗残骸) の HEAD に使う placeholder
  if [[ "$branch" == ".invalid" ]]; then
    line_git+=("${DIM}(empty)${RST}")
    return
  fi

  # 進行中の操作は**先頭**に置く — この行で最も行動に直結する事実で、後ろの `HEAD@<sha>` や
  # ブランチ名に「なぜこの状態なのか」を与える。**色は既存の赤**（detached / conflicts と同じ
  # 「特別な git 状態」の類なので、行に色系統を増やさない）。
  [[ -n "$op" ]] && line_git+=("${RED}${op}${RST}")

  if [[ "$detached" == 1 ]]; then
    # detached では repo 識別も PR も出さない (どの branch の話でもないため)
    line_git+=("${RED}HEAD@${branch}${RST}")
  else
    # repo 識別は stdin の workspace.repo (Claude Code 2.1.145+、fork ゼロ) を優先し、無ければ facts の origin。
    # gh: プレフィックスのみ dim、owner/repo は通常輝度 — ローカル dir 名と origin repo 名の食い違いは
    # ここでしか判別できない一次情報なので。
    # **パス末尾が `/owner/repo` に一致したら省く** (v1.74.0) — ghq 系のレイアウト
    # (`~/ghq/github.com/<owner>/<repo>`) では Line 2 のパスがそのまま owner/repo で終わるので、
    # `gh:` が同じ文字列の二度出しになる。上の一次情報という理由は覆さず、**その理由が効くとき
    # だけ出す**形に純化する (「違う時だけ出るなら差分そのものがシグナル」の適用)。
    # 大文字小文字が違えば一致しないので「出続ける」側に倒れる = 誤って消える事故は起きない。
    # **worktree でも畳む** — Line 2 は `<repo>/.claude/worktrees/<name>` を repo root で切って
    # 描くので、比較するのは**画面に出ているパス**（第 2 引数の `screen_dir`）。`current_dir`
    # （末尾 = worktree 名）と比べていた頃は、画面に 2 回出ている repo 名を畳めなかった。
    # **一致した成分だけ削る 3 段**: `/owner/repo` 一致 → 出さない / `/repo` だけ一致 →
    # `gh:owner/`（owner はローカルに現れないので残す）/ 不一致 → 全部出す。特例を足すのではなく
    # 上の省略規則の一般化で、`~/dev/<repo>` という**最も普通の clone レイアウト**にも効く。
    # **末尾の `/` は意図的** — 裸の `gh:owner` は「owner という名の repo」に誤読される。`/` が
    # 「続き（repo 部）は真上の行の末尾」の標識になる。
    # 比較は必ず `/` で anchor する — 付けないと `my-<repo>` のような上位文字列に誤爆する。
    local id="${ws_repo_id:-$repo_id}"
    if [[ -n "$id" && "$screen_dir" != *"/$id" ]]; then
      # repo 名だけ一致 → owner だけ残す (末尾の `/` が「続きは真上の行」の標識)
      [[ "$id" == */* && "$screen_dir" == *"/${id##*/}" ]] && id="${id%/*}/"
      line_git+=("${DIM}gh:${RST}${id}")
    fi

    # GitHub tree URL — PR への遷移は Claude Code 組み込みフッターの PR badge に任せる
    local branch_show="$branch"
    [[ -n "$remote" ]] && osc8 "${remote}/tree/${branch}" "$branch" branch_show
    line_git+=("${GIT}${branch_show}${RST}")

    # PR review state (Claude Code 2.1.145+) — フッターが出さない state のみを補う
    if has_val "$pr_review_state"; then
      local pr_color
      pr_state_color "$pr_review_state" pr_color
      line_git+=("${pr_color}${pr_review_state}${RST}")
    fi
  fi

  # Dirty state = **行数の増減** (`+470 -105`)。Claude Desktop の code 画面と同じ単位・同じ色。
  # `+` 緑 / `-` 赤 は既存の `↑`(ahead) 緑 / `↓`(behind) 赤 と同じ 2 色なので、行に新しい色は増えない。
  # **0 の側は出さない** — 追加だけ / 削除だけの作業で `+42 -0` の `-0` はノイズ。
  # conflicts は Desktop の状態表に無いので記号を自前で決めた (マージ中は最優先の情報なので
  # 独立して残す)。**`+`/`-` と同じ ASCII の 1 桁**にするのが選定条件 —
  # `×` (U+00D7) は East Asian Ambiguous 幅で、ambiguous-width=2 の端末では 2 桁になり
  # `+`/`-` との桁揃えが崩れる。`U` は git の `--diff-filter=U` 由来の内部語彙なので使わない。
  # `?` は旧 untracked 表示を廃止したので空いており、`!` と衝突しない。
  [[ "$conflicts" =~ ^[0-9]+$ ]] && ((conflicts > 0)) && line_git+=("${RED}!${conflicts}${RST}")
  [[ "$ins" =~ ^[0-9]+$ ]] && ((ins > 0)) && line_git+=("${DIFF_ADD}+${ins}${RST}")
  [[ "$del" =~ ^[0-9]+$ ]] && ((del > 0)) && line_git+=("${DIFF_DEL}-${del}${RST}")
  [[ "$ahead"  =~ ^[0-9]+$ ]] && ((ahead > 0))  && line_git+=("${DIFF_ADD}↑${ahead}${RST}")
  [[ "$behind" =~ ^[0-9]+$ ]] && ((behind > 0)) && line_git+=("${DIFF_DEL}↓${behind}${RST}")

  # Last commit: age + 20 字に切った message
  if [[ -n "$age" && -n "$msg" ]]; then
    line_git+=("${DIM}${age} ${msg}${RST}")
  elif [[ -n "$age" ]]; then
    line_git+=("${DIM}${age}${RST}")
  fi
}


# ============================================================================
# Line 1: Vim mode + Provider + Model + effort/think/fast + Agent + 宛名 + [branch/fork] + Version
# ============================================================================
line1=()

if ((_jq_ok == 0)); then
  line1+=("${RED}jq error${RST}")
  # 空行は literal で出す — bash 3.2 の set -u は空配列の [*] 展開で即死し、
  # "jq error" を出すはずが statusline 全体が空白になる (macOS の /bin/bash は 3.2 固定)
  printf '%s\n\n\n' "${line1[*]}"
  exit 0
fi

# --- キャッシュの mtime をまとめて取る（実測と仕組みは `prefetch_mtimes` の頭に 1 箇所だけ）---
# ここで守るのは**順序**だけ: ① `git_cache_file` でパスを確定してから渡す ② **jq 失敗の bail より
# 後**（前に置くと捨てる結果のために `md5` と `stat` を fork し、キャッシュ dir まで作る）
# ③ 3 つの stale 判定より前。**取った値は描画開始時点のスナップショット**なので、この描画中に
# 自分が書き換えるファイル（`resolve_resets` の `$RESET_CACHE` 等）を渡してはいけない。
git_cache_file "$current_dir"
prefetch_mtimes "$SUB_CACHE" "$USAGE_CACHE" "$_gc"

# Vim mode badge (Claude Code 2.1.x vim.mode) — leftmost so it catches the eye while typing.
# Claude Code's footer shows a dim "-- INSERT --" hint; this badge is intentionally louder.
# NORMAL is hidden (it's the default — showing it adds noise).
case "$vim_mode" in
  INSERT)        line1+=("${VIM_INSERT} INSERT ${RST}") ;;
  VISUAL)        line1+=("${VIM_VISUAL} VISUAL ${RST}") ;;
  "VISUAL LINE") line1+=("${VIM_VISUAL} V-LINE ${RST}") ;;
esac

# Model (colored by tier): prefer display_name, fall back to id
model_show="${model:-$model_id}"
# display_name の "(1M context)" は名前から剥がす — コンテキスト量は Line 4 の % の分母として
# `48%/1M` で出すほうが (a) % を修飾する情報が % の隣に来る (b) display_name が空の Bedrock でも
# 同じ表示になる (c) Line 1 が 14 文字短くなり subagent 行の表記と揃う。
# "context" を含む末尾の括弧だけを対象にし、他の括弧付き display_name は触らない。
case "$model_show" in
  *" ("*"context)") model_show="${model_show% (*}" ;;
esac

# Cloud provider detection (check model_id for Bedrock prefix, not display_name)
provider=""
shopt -s nocasematch
if [[ "$model_id" =~ ^(global|jp|us-gov|us|eu|au|apac)\. ]] || [[ "${CLAUDE_CODE_USE_BEDROCK:-}" == "1" ]] || [[ "${CLAUDE_CODE_USE_MANTLE:-}" == "1" ]]; then
  provider="bedrock"
elif [[ "${CLAUDE_CODE_USE_VERTEX:-}" == "1" ]]; then
  provider="vertex"
elif [[ "${CLAUDE_CODE_USE_FOUNDRY:-}" == "1" ]]; then
  provider="foundry"
fi
shopt -u nocasematch

# Provider indicator (first in line)
case "$provider" in
  bedrock) line1+=("${BDCK}Bedrock${RST}") ;;
  vertex)  line1+=("${VTEX}Vertex${RST}") ;;
  foundry) line1+=("${FNDY}Foundry${RST}") ;;
  *)
    fetch_subscription
    if has_val "$_sub_type"; then
      # 公式表記 + レート枠 (`Max 5x` / `Enterprise 5x` / `Pro`)。組み立ては lib.sh の plan_label。
      plan_label _plan "$_sub_type" "$_rate_tier"
      line1+=("${ANTH}Anthropic(${_plan})${RST}")
    else
      line1+=("${ANTH}Anthropic${RST}")
    fi
    ;;
esac

# Model (colored by tier) — 共有 model_color が nocasematch スコープを内部管理する
model_color _model_col "$model_show" "$model_id"
line1+=("$_model_col")

# 色は effort_color（lib.sh）に集約 — subagent 行と同じランプを使う
if has_val "$effort_level"; then
  effort_color _eff_col "$effort_level"
  line1+=("$_eff_col")
fi
[[ "$thinking_enabled" == "true" ]] && line1+=("${THINK}think${RST}")
# fast mode (Claude Code 2.1.216 docs で確認、fast_mode boolean) — /fast 有効時のみ。false/欠落は非表示
[[ "$fast_mode" == "true" ]] && line1+=("${FAST}fast${RST}")

# output style (`output_style.name`) — **常に出す**（v1.76.0、ユーザー選択。`default` 以外だけ
# 出していたが「default のときも default と出してほしい」）。output style は応答の挙動を根本から
# 変えるのに Claude Code に常設表示が無く、`/output-style` を開かないと今どれなのか分からない。
# **`default` だけ dim** — 既定値は「特に設定していない」を示すプレースホルダ側なので、
# `no git` / `(empty)` / `-%` と同じ扱いにする。非既定は白で立つので「違う」は一目で分かる。
# 旧 Claude Code / フィールド欠落では空になり何も出ない（`// ""` の既定値）。
if has_val "$output_style"; then
  if [[ "$output_style" == "default" ]]; then
    line1+=("${DIM}${output_style}${RST}")
  else
    line1+=("${OSTYLE}${output_style}${RST}")
  fi
fi

# Agent name
if has_val "$agent_name"; then
  line1+=("${AGENT}${agent_name}${RST}")
fi

# Session lineage marker — session_name 末尾のマーカーから「このセッションの出自」を読む。
# 2.1.220 実測: `/branch` は ` (Branch)`、`/fork` は ` ⑂` (U+2442) を付ける。**`(Fork)` は付かない**。
# 旧 `(Fork)` は 2.1.77 より前の `/branch` のエイリアスなので **branch 扱い** — fork と出すと意味が逆になる。
# 色は branch/fork で同じ黄。色はカテゴリ (別セッション由来) を表し、語がどちらかを表す。
# ピンク (AGENT) は使わない — fork は agent view の行になるので `agent.name` と同色が 2 語並びうる。
# ⑂ を先に見る: `/branch` した会話を `/fork` すると `foo (Branch) ⑂` と両方付くが、
# 「親が並走している」ほうが行動に直結する新しい事実なので fork を優先する。
# session_name 自体は表示しない (2.1.76+ が右上にネイティブ表示する) ので、サニタイズはしない。
# 連番 ` (Branch 2)` も付く (2.1.220 実測) ので数字付きの arm を持つ。`*"(Branch"*` の前方一致に
# しないのは、名前に "(Branch protection)" 等を含むだけのセッションが degraded path (transcript が
# 読めない環境) で誤爆するため — マーカーの実測形 `(Branch)` / `(Branch N)` だけを受ける。
session_kind=""
case "$session_name" in
  *"$FORK_GLYPH"*)                                  session_kind="fork" ;;
  *"(Branch)"*|*"(Branch "[0-9]*")"*|*"(Fork)"*)    session_kind="branch" ;;
esac
# 名前のマーカーだけでは足りない — `/branch` は **元セッションの名前にも** ` (Branch)` を書き込む
# (2.1.221 実測。元・子・元を resume した実体の 3 つが同名 `… (Branch)` になり、元に戻っても消えなかった)。
# transcript 冒頭の `forkedFrom` 記録だけが「本当に派生した側」の証拠なので、これで裏取りする。
# 先頭 1 行ではなく **20 行** 見る — 冒頭に custom-title/mode/file-history-snapshot のヘッダ記録が
# 積まれて forkedFrom が 7 行目に来る transcript が実在する (実測: 23 件中 22 件が 1 行目、1 件が 7 行目)。
# needle は `"forkedFrom":{` — JSON 文字列値の中では `"` が必ず `\"` にエスケープされるので、
# この生の並びは**構造上のキーとしてしか現れない**（本文に貼られた jsonl 断片では一致しない）。
# 読めない時 (旧 Claude Code に `transcript_path` が無い等) は従来どおり名前だけで出す = graceful degradation。
# 旧 `(Fork)` (2.1.77 以前の子) も gate を通るが、実在する 4 件全てが forkedFrom を 1 行目に持つ (実測済み)。
# `⑂` にはゲートを掛けない — customTitle には書かれず実行時の名前にだけ付くので元へ伝播しない。
# かつ **fork の子は forkedFrom を持たない** (2.1.222 実測: `/fork` 子 transcript の全 47 行に 0 件、
# customTitle も空) ので、掛ければ「出るべき fork が出ない」が確実に起きる。非対称は実測どおり。
parent_sid=""
if [[ "$session_kind" == "branch" && -r "$transcript_path" ]]; then
  _fork_seen="" _scan=0 _tline="" _fk=""
  # `|| [[ -n ... ]]` — 最終行に改行が無い transcript で read が rc=1 でも内容は入っている
  while IFS= read -r _tline || [[ -n "$_tline" ]]; do
    if [[ "$_tline" == *'"forkedFrom":{'* ]]; then
      _fork_seen=1
      # 裏取りに使う同じ記録が親 id も持つ (`{"sessionId":"…","messageUuid":"…"}`) ので、
      # ついでに抜いて「元へ戻る」用に出す — 追加の I/O も fork も無い。
      # `}` までで切ってスコープを閉じる — forkedFrom の値はネストを持たないので、
      # 後続の別キーの `"sessionId"` を誤って拾わない。
      _fk="${_tline#*'"forkedFrom":{'}" _fk="${_fk%%\}*}"
      if [[ "$_fk" == *'"sessionId":"'* ]]; then
        _fk="${_fk#*'"sessionId":"'}" _fk="${_fk%%'"'*}"
        # **切り詰めず full uuid で出す** — `--resume` は 8 桁 prefix を受けない (2.1.222 実測:
        # `"3052272d" is not a UUID and does not match any session title` で弾かれる。full uuid だと
        # `No conversation found with session ID:` = UUID として受理された上での不一致になり、
        # エラーの種類が違う)。prefix 解決は存在しないので、短くするとコピーしても戻れない。
        # 許可リストで uuid の形だけ受ける (拒否リストは持たない方針) — 1 番目の arm で hex と
        # ハイフン以外を弾き、2 番目で 8-4-4-4-12 の配置を見る。壊れた記録や別形式の id では
        # 語だけの従来表示に落ちる。
        case "$_fk" in
          *[!0-9a-f-]*) ;;
          ????????-????-????-????-????????????) parent_sid="$_fk" ;;
        esac
      fi
      break
    fi
    (( ++_scan >= 20 )) && break
  done < "$transcript_path"
  [[ -n "$_fork_seen" ]] || session_kind="" parent_sid=""
fi
# --- Peer name: cross-session messaging の宛名 ---
# `SendMessage`/`ListAgents` のアドレスは `~/.claude/sessions/<pid>.json` の `name` (cwd 由来 derived)。
# **undocumented な内部ファイル** (docs にも CHANGELOG にも無い) なので読めなければ何も出さない。
# 出す理由・却下した表記・付与率の実測は docs/internals.md の「宛名」節にある (ここには
# 編集時に壊しうる不変条件だけ置く)。**キャッシュを持たせないこと** — 理由はコストではなく
# **宛名が走行中に書き換わる**こと (`/rename` `/branch` が `name` を書き換え、背景セッションは
# 8 桁 id → AI タイトルへ変わる)。キャッシュすると死んだ宛先を出し続ける = SendMessage の誤配。
# (v1.81.0 まではコストも理由だったが、`prefetch_mtimes` の引数に足せば stat は増えないので
# その論拠は消えた。fork ゼロ自体は維持する。)
peer_name=""
# gate は**性能のため**で、挙動の防御は下の id 照合が単独で担う (空 id はどのファイルにも一致しない)。
# 未取得時に glob 展開ごと省ける (bash は非選択の分岐で glob を展開しない)。
if has_val "$session_id"; then
  # **`CLAUDE_CONFIG_DIR` を尊重する** — ハードコードすると別 config dir のセッションで宛名が
  # 丸ごと消える (経緯は docs/internals.md の「宛名」節。メタテストが直書きを禁じている)。
  for _sf in "${CONFIG_DIR}"/sessions/*.json; do
    # **`-r` で gate する。`2>/dev/null` では黙らせられない** — リダイレクトは左から適用されるので
    # `< "$_sf"` の失敗が先に起き、ディレクトリが無い環境 (2.1.224 より前) では未展開の glob が渡って
    # **毎レンダー stderr にエラーが出る**。credentials の `$(<file)` と同じ Gotcha。
    [[ -r "$_sf" ]] || continue
    _sl=""
    # `read` の rc は見ない — このファイル群は末尾改行が無く rc=1 でも内容は入る (forkedFrom と同じ罠)
    IFS= read -r _sl < "$_sf"
    [[ "$_sl" == *"\"sessionId\":\"${session_id}\""* ]] || continue
    # **`nameSource` で絞らない** — `name` は生成規則にかかわらず常にアドレスなので、絞ると
    # 「送れる宛先が画面に無い」状態が生まれる (v1.69.0 の回帰。経緯は docs/internals.md の「宛名」節)。
    # `"name":"` は `"nameSource":"` に一致しない (`"name` の次が `S`)。JSON 文字列値の中では
    # `"` が必ずエスケープされるので、この生の並びは構造上のキーとしてしか現れない (forkedFrom と同じ理屈)。
    [[ "$_sl" == *'"name":"'* ]] || continue
    peer_name="${_sl#*'"name":"'}"
    # **終端の `"` は退避の後に探す** — 素朴に切ると値の中の `\"` で切れて誤った宛名を出す = 誤配。
    # **`\\` を `\"` より先に退避する**のが順序の不変条件 (`\\"` の誤読を防ぐ。`osc8` の `%` 先行と同じ)。
    # **制御文字の escape (`\n` `\uXXXX`) は decode しない** — `\n` を実文字に戻すと単一 printf の
    # 4 行契約が壊れ、ESC の escape は AI 生成タイトルからの ANSI 注入になる。第 3 の escape が実測で
    # 出たら `//` を足さず parser へ移す (経緯と根拠は docs/internals.md の「宛名」節)。
    peer_name="${peer_name//\\\\/$'\002'}"
    peer_name="${peer_name//\\\"/$'\001'}"
    peer_name="${peer_name%%'"'*}"
    peer_name="${peer_name//$'\001'/\"}"
    peer_name="${peer_name//$'\002'/\\}"
    break
  done
fi

# 宛名 — **ラベルも囲みも色も付けず値だけ置く**。要素間のスペースが単語境界になり、名前に含まれる
# `-` は境界文字でないのでダブルクリックで丸ごと選択できる = そのまま `SendMessage` に貼れる。
# 記号を足すと選択に混ざるので**付けないことが要件**。却下した表記は docs/internals.md の「宛名」節。
has_val "$peer_name" && line1+=("$peer_name")
# Session indicator — branch 先では元セッションの id を添える (`branch:<uuid>`)。
# `/branch` の元は別端末で resume されるので、戻るには id が要る (コピーして `--resume`)。
# fork には添えない — 元は同じ端末に残り detach で戻れるうえ、fork の子は forkedFrom を持たない。
# ラベル側 (黄) に `:` まで含め値は通常輝度 — `gh:` と同じ「値が一次情報」の作法。
if [[ -n "$session_kind" ]]; then
  if [[ -n "$parent_sid" ]]; then
    line1+=("${YLW}${session_kind}:${RST}${parent_sid}")
  else
    line1+=("${YLW}${session_kind}${RST}")
  fi
fi

# Version — **Line 1 の最後**。版は行動に効かない参照情報なので、溢れた時に最初に削られてよい。
# **最新版から遅れている間だけアラーム色（赤）で立てる**（v1.79.0 時点の設計）。最新版は
# Claude Code 自身が置く changelog キャッシュの冒頭から読み、`ver_older` で数値比較する。
# 却下済み: ①「前回見た版と違う間だけ立てる」（変化の検知では*遅れているか*が読めない）
# ② 明度だけ上げる白 231（アラームとして弱かった）。どちらも復活させないこと。
if has_val "$cc_version"; then
  resolve_version_color "$cc_version"
  line1+=("${_ver_col}v${cc_version}${RST}")
fi

# ============================================================================
# Line 2: Dir + Worktree
# ============================================================================
line2=()

# Directory path (full display — no truncation)
# Always use current_dir: the worktree.path override (above) and Claude Code 2.1.176+ keep it
# pointing at the live dir. Do NOT fall back to project_dir — it pins to the launch dir (see CHANGELOG 1.32.0).
_display_dir="$current_dir"
_short_dir="${_display_dir/#$HOME/~}"

# Worktree path split: `<repo>/.claude/worktrees/<name>` はパス末尾がランダムな worktree 名になり
# リポ dir が中程に埋まって「どこの repo か」が読めないため、リポ root と 🌲<name> に分割表示する
# （リンクは root / worktree 各ディレクトリへ）。worktree 内サブディレクトリや既定外配置では
# marker 不一致で分割せずフルパス表示に fallback する。
_wt_marker="$WT_MARKER"   # lib.sh の共有定数（両 statusline で drift 防止）
_is_wt=""
if has_val "$wt_name" || has_val "$ws_git_worktree"; then _is_wt=1; fi
_wt_leaf=""
# `?*` = marker より前に 1 文字以上 — リポが / 直下の極端ケースで root が空になり空リンク要素が出るのを防ぐ
if [[ -n "$_is_wt" && "$_short_dir" == ?*"$_wt_marker"* ]]; then
  _wt_leaf="${_short_dir##*"$_wt_marker"}"
  [[ -z "$_wt_leaf" || "$_wt_leaf" == */* ]] && _wt_leaf=""
fi

# Line 2 が描くパス（worktree では root 側で切る）を 1 組で決める。**Line 3 の `gh:` 畳み込みも
# ここを見る** ので、切り方を変えたときに 3 箇所へ散らないようにまとめてある
_line2_dir="$_display_dir" _line2_short="$_short_dir"
if [[ -n "$_wt_leaf" ]]; then
  _line2_dir="${_display_dir%"$_wt_marker"*}" _line2_short="${_short_dir%"$_wt_marker"*}"
fi
_screen_dir="${_line2_dir%/}"       # 比較用（末尾の / を落とす）
editor_url "$_line2_dir" _editor_url
osc8 "$_editor_url" "$_line2_short" _osc_tmp
line2+=("$_osc_tmp")

# Worktree indicator: Claude Code worktree (wt_name) or git linked worktree (ws_git_worktree, Claude Code 2.1.97+)
# Placed adjacent to the path since it qualifies what the path *is*.
if [[ -n "$_is_wt" ]]; then
  if [[ -n "$_wt_leaf" ]]; then
    editor_url "$_display_dir" _editor_url
    osc8 "$_editor_url" "$_wt_leaf" _osc_tmp
    line2+=("🌲${DIM}${_osc_tmp}${RST}")
  else
    line2+=("🌲")
  fi
  # from:HEAD (detached HEAD から作成) も「detached から切った」事実を示すので表示する
  # (v1.74.0 で Line 3 base: を撤去したので、切り元を出すのはここだけ)
  if has_val "$wt_orig_branch"; then
    line2+=("${DIM}from:${wt_orig_branch}${RST}")
  fi
fi

# Aggregate, not per-basename: per-basename can be truncated at terminal edge,
# hiding which dirs are added. Claude Code 2.1.141 fixed row-drop on overflow but still truncates.
if ((added_dirs_count > 0)); then
  line2+=("${DIM}(+${added_dirs_count} dirs)${RST}")
fi

# ============================================================================
# Line 3: Git info (separated from Line 2 to avoid overflow)
# ============================================================================
line_git=()

# Git info (background refresh)
# **タグを検証してから使う** — 一致しなければ「無い」扱いにして cold-start に落ち、同時に背景 build を
# 起こす (TTL を待たない)。読みは `read` で fork ゼロ (`$(<file)` は bash 3.2 でコマンド置換 = fork)
_git_facts="" _gc_raw=""
if [[ -r "$_gc" ]]; then
  IFS= read -r _gc_raw < "$_gc"
  [[ "$_gc_raw" == "${GIT_FMT}"$'\037'* ]] && _git_facts="${_gc_raw#*$'\037'}"
fi
# **タグ不一致で即取り直すのは「中身があるのにタグが違う」ときだけ** — 非 git ディレクトリでは
# `build_git` が何も出さず **0 バイトのファイル**が残るので、`-s` を付けないとタグ不一致と同じ扱いに
# なって `cache_stale` の 5s 抑止を通らず**毎レンダー背景 build を spawn する**（storm。表示は
# 正常なので沈黙する。`/code-review` が実測で捕まえた）
if [[ -s "$_gc" && -z "$_git_facts" ]] || cache_stale "$_gc" "$GIT_CACHE_MAX_AGE"; then
  # 末尾の `>/dev/null 2>&1` は**内側の `> tmp` と別物で、外せない** — subshell が親の stdout を
  # 保持し続けると捕捉側の EOF が遅れる (docs/internals.md「バックグラウンド更新」/ fetch_subscription の注記)
  ( [[ -d "$GIT_CACHE_DIR" ]] || mkdir -p -m 700 "$CACHE_BASE" "$GIT_CACHE_DIR"
    build_git "$current_dir" > "${_gc}.tmp-$$" && mv "${_gc}.tmp-$$" "$_gc" ) >/dev/null 2>&1 & disown
fi
if [[ -z "$_git_facts" ]]; then
  # キャッシュ未populate — non-git かどうかは pure bash で判定 (fork ゼロ)
  if [[ ! -d "${_display_dir}/.git" && ! -f "${_display_dir}/.git" ]]; then
    line_git+=("${DIM}no git${RST}")
  else
    # Cold start: .git/HEAD から branch だけを読み、build_git と同じ facts レイアウトに合成する
    # (残りのフィールドは空)。表示は同じ render_git を通るので、3 経路で gate を揃える問題が起きない。
    _head_file="${_display_dir}/.git"
    if [[ -f "$_head_file" ]]; then
      # Worktree: .git はファイル → gitdir ポインタを追う
      _gitdir="$(<"$_head_file")"; _gitdir="${_gitdir#gitdir: }"
      [[ "$_gitdir" != /* ]] && _head_file="${_display_dir}/${_gitdir}/HEAD" || _head_file="${_gitdir}/HEAD"
    else
      _head_file="${_head_file}/HEAD"
    fi
    if [[ -f "$_head_file" ]]; then
      _head=$(<"$_head_file")
      if [[ "$_head" == ref:* ]]; then
        _git_facts="${_head#ref: refs/heads/}"$'\037'"0"
      else
        _git_facts="${_head:0:7}"$'\037'"1"     # detached (raw sha)
      fi
    fi
  fi
fi
# facts があれば (キャッシュでも cold-start 合成でも) 同じ presenter を通す
[[ -n "$_git_facts" ]] && render_git "$_git_facts" "$_screen_dir"


# ============================================================================
# Line 4: コンテキスト + 経過 + コスト (このセッションのスコープ) = line_sess
# Line 5: レート制限 + 追加課金 (アカウントのスコープ、Anthropic のみ) = line_lim
# ============================================================================
# **スコープで行を分ける** (v1.74.0)。1 行に混ぜていた頃は 7 要素・弱め表示 7 割で、
# 「どこまでが制限の話でどこからがこのセッションの話か」が読めなかった (ユーザー指摘 2 回)。
# 区切り記号を足したり並べ替えで凌ぐのではなく、意味の境界で行を割る。
# **セッション行を上（4 行目）** に置く — 毎ターン変わるのはこちらで、制限は数時間〜1 週間単位。
# 変数名は表示行番号を持たせない (`line3`/`line4` は「配列の通番」と「表示行」がずれて読み違える)。
line_lim=() line_sess=()

# リセット時刻は 2 つまとめて解決する — epoch が変わらない限り `date` を叩かない (resolve_resets)。
# Anthropic 以外では rate_limits が来ないので呼ばない (キャッシュも作らない)。
_five_txt="" _seven_txt=""
[[ -z "$provider" ]] && resolve_resets "$five_reset_epoch" "$seven_reset_epoch"

# 5-hour rate limit (Anthropic only, Claude Code 2.1.80+) — leftmost for quick glance
# リセットは**絶対時刻** (`19:31`)。曜日を付けないのが週間制限との区別になる。
if [[ -z "$provider" ]] && has_val "$five_pct"; then
  braille_bar "$five_pct" _bbar
  line_lim+=("${ANTH}${_bbar} ${five_pct}%${RST}")
  [[ -n "$_five_txt" ]] && line_lim+=("${ANTH}${_five_txt}${RST}")
fi

# Weekly rate limit (Anthropic only) — 5h の直後。Pro/Max では stdin の `seven_day` が来る
# (Enterprise 契約では null になることがあり、その場合は出ない = graceful degradation)。
# リセットは曜日付きの絶対時刻 (`土 16:00`)。
if [[ -z "$provider" ]] && has_val "$seven_pct" && ((seven_pct > 0)); then
  line_lim+=("${DIM}week:${seven_pct}%${RST}")
  [[ -n "$_seven_txt" ]] && line_lim+=("${DIM}${_seven_txt}${RST}")
fi

# モデル別の週間制限 (`Fable:39%`、Anthropic のみ)。stdin には来ないので `/usage` の `limits[]` から。
# **`fetch_usage_spend` はここで 1 回だけ呼ぶ** — extra:$ も同じキャッシュを使うので、
# 後段では `_usage_cents` を読むだけにする (2 回呼ぶと背景 fetch が二重に走る)。
# 全体の週間制限 (stdin の `seven_day`) と**併存させる** — 別の制限なので置き換えない。
if [[ -z "$provider" ]]; then
  fetch_usage_spend
  render_scoped_limits
fi

# Context bar
if has_val "$used_pct"; then
  pct_int=${used_pct%.*}
  color_by_threshold "$pct_int" 90 80 ctx_color
  braille_bar "$pct_int" _bbar
  # 分母は**値が来ていれば常に**添える (`48%/1M`・`48%/200k`)。% だけでは絶対量が読めず、
  # 「既定の 200k だけ無印」にすると読み手が既定値を記憶している前提になる (v1.57.0 で常時表示へ)。
  # **分母は % と同じ色**にして一体で読ませる — dim で弱めると「% を修飾する値」ではなく
  # 「別の補助情報」に見えるため (2026-07-27 のヒアリング)。
  # 表記は fmt_ctx_size に委ねる (1M 決め打ちの整数除算だと 500k が出ず 1.5M が /1M と誤表示になる)。
  _ctx_den=""
  if ((ctx_window_size > 0)); then
    fmt_ctx_size "$ctx_window_size" _ctx_size
    _ctx_den="/${_ctx_size}"
  fi
  ctx_text="${ctx_color}${_bbar} ${pct_int}%${_ctx_den}${RST}"
  [[ "$exceeds_200k" == "true" && "$ctx_window_size" -le 200000 ]] && ctx_text+=" ${RED}⚠ 200K超${RST}"
  line_sess+=("$ctx_text")
else
  line_sess+=("${DIM}      -%${RST}")
fi

# Session elapsed (cost.total_duration_ms) — 長時間 agentic セッション / 並走運用で「何時間回してる?」
# を即答するため。Claude Code に常駐表示が無く、stdin に既にあるので fork ゼロ。
# 60 秒未満は出さない (開始直後の "0m" はノイズ)。フィールド欠落 (旧 Claude Code) も 0 で非表示に倒れる。
if ((dur_sec >= 60)); then
  fmt_elapsed "$dur_sec" _dur
  line_sess+=("${DIM}${_dur}${RST}")
fi

# Extra-usage spend (usage-credits, Anthropic only) — 実課金額。stdin に無いので /usage を背景取得。
# **アカウント側の行 (line_lim) に置く** — 枠を超えた分の課金なので制限と同じスコープ。
# セッションコストは「このセッションの API 換算額」で別のスコープなのでセッション行に残す。
if [[ -z "$provider" ]]; then
  # fetch は制限グループ側で済んでいる (`_usage_cents` を読むだけ)
  if [[ "$_usage_cents" =~ ^[0-9]+$ ]] && ((_usage_cents > 0)); then
    printf -v _xtra 'extra:$%d.%02d' $((_usage_cents / 100)) $((_usage_cents % 100))
    # **bold で立てる** — この行で唯一「実際に請求される額」なので、同色相のセッションコスト
    # (COST, ブロンズ) との明度差に加えて太さでも差を付ける。bold は色ではないので
    # Line 4/5 の色系統を増やさない (vim mode バッジ以外で bold を使うのはここだけ)。
    line_lim+=("${BOLD}${SPEND}${_xtra}${RST}")
  fi
fi

# Session cost (全プロバイダー共通。Claude Code 計算済みの API 換算 USD; subscription では実請求なしの参考値)
# cost_cents > 0 が「フィールド欠落 (旧 Claude Code)」と「$0.00」の両方を非表示に倒す
if ((cost_cents > 0)); then
  printf -v _cost '$%d.%02d' $((cost_cents / 100)) $((cost_cents % 100))
  # **金額らしく金色で出す** (v1.74.0)。extra-usage の実課金 (SPEND, 明るい gold) と同色相で
  # 明度だけ下げた COST (ブロンズ) を使い、「どちらも金額 / 明るい方が実際に請求される額」の
  # 序列を色で表す。無色だった頃は「弱め要素の中で唯一の通常輝度」でしか立っていなかった。
  line_sess+=("${COST}${_cost}${RST}")
fi

# ============================================================================
# Output — single write() for atomic pipe delivery
# ============================================================================
# `:-` が必須 — bash 3.2 の set -u は空配列の [*] 展開で即死する。line_git は「.git はあるが HEAD が
# 読めない」(親リポが消えた stale worktree 等) で空になり、line_lim/line_sess も全要素が条件付きなので空になりうる。
# 付け忘れると exit 1 で statusline が丸ごと空白になる (bash 4+ では再現しないので手元では気付けない)。
#
# **空の行は出さない** — 制限行 (line_lim) は Bedrock/Vertex/Foundry では全要素が Anthropic 限定なので
# 空になる。無条件に改行を出すと**空行が 1 本挟まって**見た目が崩れるので、非空の行だけを連結する。
# 通常 (Anthropic + git リポ) はちょうど 5 行、Bedrock では 4 行になる。
_l1="${line1[*]:-}" _l2="${line2[*]:-}" _lg="${line_git[*]:-}"
_lim="${line_lim[*]:-}" _sess="${line_sess[*]:-}"
_out="${_l1}"$'\n'"${_l2}"
[[ -n "$_lg" ]]   && _out+=$'\n'"${_lg}"
[[ -n "$_sess" ]] && _out+=$'\n'"${_sess}"   # Line 4: このセッション
[[ -n "$_lim" ]]  && _out+=$'\n'"${_lim}"    # Line 5: アカウントの制限 + 追加課金
printf '%s\n' "$_out"

exit 0
