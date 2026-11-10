#!/bin/bash
# test.sh — statusline-command.sh の回帰テスト。`/bin/bash test.sh` で全部走る（数秒）。
#
# **入れる基準は「画面を見て気付けないか」。** 表示文字列の assert は入れない — 3 行の中身は
# 開発中に何度も変わるので、書いた瞬間から書き換え作業になる。ここが守るのは、静かに壊れて
# 気付けないもの: キャッシュの互換と移行、並走時の巻き戻し、型変更での抽出全滅、時刻の
# ゾーン/書式、トークンの非露出、bash 3.2 互換。
#
# **被験体は必ず `/bin/bash`（3.2）で起動する。** `bash script.sh` と書くと最重要制約を一切
# 検証しないテストになる（v1 で 3.2 即死バグ 3 件が全緑で出荷された）。
#
# **新しい回帰テストは対象を壊して NG を確認する。** 壊すのは python のヒアドキュメント
# （`sed -i` は zsh のクォート解釈で黙って空振りし、壊れていないまま緑になる）。

cd "$(dirname "$0")" || exit 1
S="$PWD/statusline-command.sh"
US=$(printf '\037')
NOW=$(date +%s)
ok=0; ng=0
TMPS=""

cleanup() { for d in $TMPS; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

# **出力の契約は「空行を含まず最大 3 行」。** 「常に 3 行」ではない — 1 行目と 3 行目に出す値が
# 何も無い payload（`{}` 等）では正しく 1 行になる（空の行は連結しない、の帰結）。
# ここを「3 行」で固定すると、**空行を挟む実装に戻す変更をテストを消さずに入れられる**。
contract() {  # contract OUTPUT → 空行が無く 1〜3 行なら 1
  local t e
  t=$(printf '%s' "$1" | grep -c '')            # 非空行
  e=$(printf '%s' "$1" | grep -c '^$')          # 空行
  [ "$t" -ge 1 ] && [ "$t" -le 3 ] && [ "$e" = 0 ] && printf 1
}
check() {  # check NAME NONEMPTY_IF_OK DETAIL
  if [ -n "$2" ]; then ok=$((ok + 1)); printf '  ok   %s\n' "$1"
  else ng=$((ng + 1)); printf '  NG   %s\n       %s\n' "$1" "$3"; fi
}
has() { case "$2" in *"$1"*) printf 1 ;; esac; }        # has NEEDLE HAYSTACK
no()  { case "$2" in *"$1"*) ;; *) printf 1 ;; esac; }   # no NEEDLE HAYSTACK（含まないなら 1）
# **複数条件は `all` で束ねる。** `"$(a)$(b)"` と連結すると**片方が満たされただけで非空**に
# なり、AND ではなく **OR** になる（2026-09-08 の mutation で実証: 型ガードを外しても
# `contract` が 1 を返すので緑のままだった）。
all() { local a; for a in "$@"; do [ -n "$a" ] || return 0; done; printf 1; }
empty() { [ ! -s "$1" ] && printf 1; }                  # empty FILE
strip() { sed -e $'s/\033\\[[0-9;]*m//g' -e $'s/\033\\]8;;[^\007]*\007//g'; }
mkd() { local d; d=$(mktemp -d); TMPS="$TMPS $d"; printf '%s' "$d"; }
# **背景の取得は `CLAUDE_STATUSLINE_SYNC_FETCH=1` で前景で走らせて見る**（`SYNC` に入れて env に渡す）。
# 被験体は本番ではプランと枠を背景 subshell で取るので、以前は「背景が書き終わった印」を 0.1 秒刻みで
# 待っていた（固定の sleep は負荷で落ちた: 6 並列で 12 回中 6 回 NG）。同じ関数を前景で呼ぶ seam にしたので
# 待ち合わせが要らない。**背景で走ること自体**は下の「描画は背景の取得を待たない」で別に pin する。
SYNC="CLAUDE_STATUSLINE_SYNC_FETCH=1"
# 一時ファイル `account….tmp-PID` は数えない（前景でも mv の失敗で残りうる。拾うと PID が毎回違うので
# 「キャッシュ名が分かれる」テストが鍵の計算に関係なく緑になる。/code-review 指摘）
cachename() { ls "$1" 2>/dev/null | grep -v '\.tmp-' | head -1; }  # cachename DIR
# **背景の取得を実物に行かせない。** 偽の `security` と `curl` を PATH の先頭に置く — 置かないと
# 背景が**開発者の実 Keychain を読み、本物の /usage を叩く**（並列で回すと 429 と同じ形の負荷）。
NOBG=$(mkd)
printf '#!/bin/bash\nprintf %%s %s\n' \
  "'{\"claudeAiOauth\":{\"subscriptionType\":\"max\",\"rateLimitTier\":\"x\",\"accessToken\":\"T\"}}'" > "$NOBG/security"
printf '#!/bin/bash\ncat >/dev/null; printf %%s "{\\"limits\\":[]}"\n' > "$NOBG/curl"
chmod +x "$NOBG/security" "$NOBG/curl"
cfile() { printf '%s/account%s' "$1" "${2//\//_}"; }    # cfile CACHEDIR CFGDIR

setup() {  # setup [SETTINGS_JSON]
  CFG=$(mkd); CD=$(mkd); ERR="$CD/err"
  printf '%s' "${1-{\}}" > "$CFG/settings.json"
}
rawr() {  # rawr PAYLOAD [LINE] — **色を落とさない**（色の assert 用）
  local out
  out=$(printf '%s' "$1" | env CLAUDE_CONFIG_DIR="$CFG" CLAUDE_STATUSLINE_V2_CACHE_DIR="$CD" \
        CLAUDE_STATUSLINE_NO_NET=1 /bin/bash "$S" 2>"$ERR")
  if [ -n "${2-}" ]; then printf '%s' "$out" | sed -n "${2}p"; else printf '%s' "$out"; fi
}
render() {  # render PAYLOAD [LINE]
  local out
  out=$(printf '%s' "$1" | env CLAUDE_CONFIG_DIR="$CFG" CLAUDE_STATUSLINE_V2_CACHE_DIR="$CD" \
        CLAUDE_STATUSLINE_NO_NET=1 /bin/bash "$S" 2>"$ERR" | strip)
  if [ -n "${2-}" ]; then printf '%s' "$out" | sed -n "${2}p"; else printf '%s' "$out"; fi
}
seed() {  # seed TZVAL [PCT] [RESET]
  { printf 'schema%s1\n' "$US"; printf 'tz%s%s\n' "$US" "$1"
    printf 'plan%senterprise\n' "$US"; printf 'tier%sdefault_claude_max_5x\n' "$US"
    printf 'at.plan%s%s\n' "$US" "$NOW"; printf 'at.limits%s%s\n' "$US" "$NOW"
    printf 'limit%sFable%s%s%s%s\n' "$US" "$US" "${2:-51}" "$US" "${3:-6 16:00}"; } > "$(cfile "$CD" "$CFG")"
}
seed2() {  # seed2 FABLE_PCT OPUS_PCT — モデル別枠を 2 件持たせる
  { printf 'schema%s1\n' "$US"; printf 'tz%s\n' "$US"
    printf 'plan%senterprise\n' "$US"; printf 'tier%sdefault_claude_max_5x\n' "$US"
    printf 'at.plan%s%s\n' "$US" "$NOW"; printf 'at.limits%s%s\n' "$US" "$NOW"
    printf 'limit%sFable%s%s%s6 16:00\n' "$US" "$US" "$1" "$US"
    printf 'limit%sOpus%s%s%s6 16:00\n' "$US" "$US" "$2" "$US"; } > "$(cfile "$CD" "$CFG")"
}

D="$PWD"
pay() {  # pay [EXTRA_JSON]
  printf '{"version":"2.1.260","model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":31,"context_window_size":1000000}%s}' "$D" "${1-}"
}
# **時刻の期待値は「未来の固定した分」から起こす。** 過去の epoch を置くとスクリプトが
# 正しく `now` を出すので**その時刻を過ぎた瞬間に落ちる時限爆弾**になる（実際に踏んだ:
# 固定日時を過ぎた翌日に 4 本落ちた）。**未来にずらしつつ「時刻の中身」は固定する** —
# 明日の 10:30 UTC を使えば、ゾーンと書式の変換は日付に依らず同じ結果になる。
E5=$(TZ=UTC jq -rn 'now | (. + 86400) | strftime("%Y-%m-%d") + "T10:30:00Z" | fromdate')
FIVE=",\"rate_limits\":{\"five_hour\":{\"used_percentage\":24,\"resets_at\":$E5}}"

echo "── 契約: 3 行と stderr ──"
setup
O=$(render "$(pay "$FIVE")")
check "通常の payload で 3 行" "$([ "$(printf '%s' "$O" | grep -c '')" = 3 ] && echo 1)" "$O"
check "stderr が空" "$([ ! -s "$ERR" ] && echo 1)" "$(cat "$ERR")"
setup; O=$(render '{}')
check "空の payload でも契約を守る（1 行になる）" "$(contract "$O")" "$O"
setup
O=$(printf '' | env CLAUDE_CONFIG_DIR="$CFG" CLAUDE_STATUSLINE_V2_CACHE_DIR="$CD" \
     CLAUDE_STATUSLINE_NO_NET=1 /bin/bash "$S" 2>/dev/null | strip)
check "空の stdin でも契約を守る" "$(contract "$O")" "$O"
setup; O=$(render '[]')
check "配列の stdin では jq error を出す（黙って消えない）" \
  "$(all "$(has 'jq error' "$O")" "$(contract "$O")")" "$O"

echo "── 抽出: 型が変わっても全滅しない ──"
# **`// ""` は欠損を防ぐが型変更を防がない。** `.effort.level` は effort が文字列になった瞬間に
# jq 全体を abort させ、1 行だけの出力になる（2026-09-04 に実測）。
for bad in \
  '{"version":1,"model":"s","effort":"s","workspace":"s","context_window":"s","rate_limits":"s","cost":"s","prompt_cache":"s","worktree":7}' \
  '{"rate_limits":{"five_hour":"s","seven_day":3},"prompt_cache":{"last_miss_cause":"s"},"cost":{"total_cost_usd":"s"},"context_window":{"used_percentage":"s"}}' \
  '{"effort":"high"}' '{"model":5}' '{"cost":{"total_cost_usd":null}}' '{"fast_mode":{}}' '{"fast_mode":"true"}'
do
  setup
  O=$(render "$bad")
  # **契約だけでは足りない。** 型ガードを外すと抽出が丸ごと abort して 1 行になり、
  # 「空行なし最大 3 行」は満たしてしまう（mutation で実証）。**`jq error` が出ないこと**
  # = 抽出が生き残ったこと、で pin する。
  check "型崩し $(printf '%s' "$bad" | head -c 34)… で抽出が生き残る" \
    "$(all "$(no 'jq error' "$O")" "$(contract "$O")" "$(empty "$ERR")")" \
    "$O / $(cat "$ERR")"
done

echo "── キャッシュ: 版上げと項目追加に耐える ──"
setup; seed ""
L=$(render "$(pay)" 3)
check "新形式のレコードを読む" "$(has 'Fable:' "$L")" "$L"
check "モデル別枠の曜日が英語 3 文字" "$(has 'Sat 16:00' "$L")" "$L"

# **未知のキーは読み飛ばす**（新しい版が書いたファイルを古い版が読んでも死なない）
setup
{ printf 'schema%s1\n' "$US"; printf 'tz%s\n' "$US"; printf 'plan%smax\n' "$US"
  printf 'tier%sdefault_claude_max_20x\n' "$US"
  printf 'credits%s12.34\n' "$US"; printf 'spend.limit%s500\n' "$US"
  printf 'at.plan%s%s\n' "$US" "$NOW"; printf 'at.limits%s%s\n' "$US" "$NOW"
  printf 'limit%sFable%s7%s6 16:00\n' "$US" "$US" "$US"; } > "$(cfile "$CD" "$CFG")"
O=$(render "$(pay)")
check "未知キーがあっても既知の値を読む" \
  "$(all "$(has 'Fable:' "$O")" "$(has 'Ultra' "$O")")" "$O"
check "未知キーで stderr が出ない" "$([ ! -s "$ERR" ] && echo 1)" "$(cat "$ERR")"

# **プラン名は 2026-11 の公式表記**（Max 5x → Max、Max 20x → Ultra）。Keychain の値は旧名のままなので
# 表示の側で畳む。**出さない倍率は 1 つずつ見る** — 「`Max` を含む」だけだと `Max 5x` のままでも緑になる。
t_plan() {  # t_plan NAME SUB_TYPE RATE_TIER WANT [MUST_NOT]
  setup
  { printf 'schema%s1\n' "$US"; printf 'tz%s\n' "$US"; printf 'plan%s%s\n' "$US" "$2"
    printf 'tier%s%s\n' "$US" "$3"; printf 'at.plan%s%s\n' "$US" "$NOW"; } > "$(cfile "$CD" "$CFG")"
  local O; O=$(render "$(pay)" 1)
  if [ -n "${5-}" ]; then
    check "$1" "$(all "$(has "($4)" "$O")" "$(no "$5" "$O")")" "$O"
  else
    check "$1" "$(has "($4)" "$O")" "$O"
  fi
}
t_plan "Max 5x は Max と出す"             max        default_claude_max_5x  'Max'        '5x'
t_plan "Max 20x は Ultra と出す"          max        default_claude_max_20x 'Ultra'      '20x'
t_plan "ultra が来ても Ultra（倍率なし）"   ultra      default_claude_max_20x 'Ultra'      '20x'
t_plan "知らない倍率の Max は倍率ごと出す"  max        default_claude_max_50x 'Max 50x'
t_plan "Enterprise の 5x は残す"          enterprise default_claude_max_5x  'Enterprise 5x'

# **無いキーは既定値**（古い版が書いたファイルを新しい版が読んでも死なない）
setup
{ printf 'schema%s1\n' "$US"; printf 'tz%s\n' "$US"; printf 'plan%spro\n' "$US"
  printf 'at.plan%s%s\n' "$US" "$NOW"; } > "$(cfile "$CD" "$CFG")"
O=$(render "$(pay)")
check "キーが足りなくてもプランは生き残る" "$(has 'Pro' "$O")" "$O"

# **旧い位置固定のレコードからの移行**（schema 不一致 → 捨てる。誤表示しない）
setup
printf 'ts,plan,tier,tz%s%s%senterprise%sdefault_claude_max_5x%s\nFable%s51%s6 16:00' \
  "$US" "$NOW" "$US" "$US" "$US" "$US" "$US" > "$(cfile "$CD" "$CFG")"
O=$(render "$(pay)")
check "旧形式は捨てる（値を誤表示しない）" \
  "$(all "$(no 'Fable' "$O")" "$(no 'Enterprise' "$O")")" "$O"
check "旧形式でも契約を守り stderr が空" \
  "$(all "$(contract "$O")" "$(empty "$ERR")")" "$O / $(cat "$ERR")"

# **末尾に改行が無い行を落とさない**（`read` が rc=1 を返すので `|| [ -n "$_k" ]` が要る）
setup
{ printf 'schema%s1\n' "$US"; printf 'tz%s\n' "$US"; printf 'at.limits%s%s\n' "$US" "$NOW"
  printf 'limit%sFable%s33%s6 16:00' "$US" "$US" "$US"; } > "$(cfile "$CD" "$CFG")"
L=$(render "$(pay)" 3)
check "改行なしの最終行も読む" "$(has 'Fable:' "$L")" "$L"

# **schema が違うレコードは値ごと捨てる。** 旧い位置固定のレコードは**キーがどの case にも
# 当たらない**ので、上のテストは schema 検査を pin していない（mutation で実証）。
# 正しいキーに見える値を置いて、schema だけずらす。
setup
{ printf 'schema%s99
' "$US"; printf 'tz%s
' "$US"; printf 'plan%senterprise
' "$US"
  printf 'tier%sdefault_claude_max_5x
' "$US"; printf 'at.plan%s%s
' "$US" "$NOW"
  printf 'at.limits%s%s
' "$US" "$NOW"
  printf 'limit%sZZTOP%s77%s6 16:00
' "$US" "$US" "$US"; } > "$(cfile "$CD" "$CFG")"
O=$(render "$(pay)")
check "schema が違えば値を使わない" \
  "$(all "$(no 'ZZTOP' "$O")" "$(no 'Enterprise' "$O")")" "$O"

# 壊れたレコードでも退化するだけ
for bad in 'garbage' "schema${US}99" "limit${US}${US}${US}" "at.plan${US}NaN"; do
  setup; printf '%s' "$bad" > "$(cfile "$CD" "$CFG")"
  O=$(render "$(pay)")
  check "壊れたレコード $(printf '%s' "$bad" | tr "$US" '|' | head -c 20)" \
    "$(all "$(contract "$O")" "$(empty "$ERR")")" "$O / $(cat "$ERR")"
done

# **⑦ 確認できなくなって久しい値は出さない。** `at.*` は claim で毎回進むので「取れているか」を
# 表さない。ログアウトやアカウント切替の後に古いプラン名を出し続けるのは「無表示 < 誤読」の裏返し。
setup
{ printf 'schema%s1\n' "$US"; printf 'tz%s\n' "$US"; printf 'plan%senterprise\n' "$US"
  printf 'tier%sdefault_claude_max_5x\n' "$US"
  printf 'at.plan%s%s\n' "$US" "$NOW"                    # claim は今（毎回進む）
  printf 'at.limits%s%s\n' "$US" "$NOW"
  printf 'ok.plan%s%s\n' "$US" "$((NOW - 200000))"       # 最後に取れたのは 2 日以上前
  printf 'ok.limits%s%s\n' "$US" "$((NOW - 200000))"
  printf 'limit%sFable%s51%s6 16:00\n' "$US" "$US" "$US"; } > "$(cfile "$CD" "$CFG")"
O=$(render "$(pay)")
check "確認できなくなって久しいプランは出さない" "$(no 'Enterprise' "$O")" "$O"
check "確認できなくなって久しい枠は出さない" "$(no 'Fable' "$O")" "$O"

# **`ok.*` を知らない版が書いたレコードは `at.*` で救済する。** これが無いとアップグレード直後に
# プランと枠が消え、claim のせいで次の取得まで最大 300 秒戻らない。
setup
{ printf 'schema%s1\n' "$US"; printf 'tz%s\n' "$US"; printf 'plan%senterprise\n' "$US"
  printf 'tier%sdefault_claude_max_5x\n' "$US"; printf 'at.plan%s%s\n' "$US" "$NOW"
  printf 'at.limits%s%s\n' "$US" "$NOW"
  printf 'limit%sFable%s51%s6 16:00\n' "$US" "$US" "$US"; } > "$(cfile "$CD" "$CFG")"
O=$(render "$(pay)")
check "ok.* が無い旧レコードは at.* で救済する（upgrade 直後に消えない）" \
  "$(all "$(has 'Enterprise' "$O")" "$(has 'Fable' "$O")")" "$O"

echo "── キャッシュ: 出所ごとの鮮度と tz ──"
# **tz が食い違ったら枠だけ捨てる**（プランは tz と無関係なので巻き込まない）
setup '{"timeZone":"UTC"}'; seed "Asia/Tokyo"
O=$(render "$(pay)")
check "tz 不一致でもプランは残る" "$(has 'Enterprise 5x' "$O")" "$O"
check "tz 不一致なら枠は捨てる" "$(no 'Fable' "$O")" "$O"

# 片方だけ古い → stale-while-revalidate で今ある値を即返す
setup
{ printf 'schema%s1\n' "$US"; printf 'tz%s\n' "$US"; printf 'plan%senterprise\n' "$US"
  printf 'tier%sdefault_claude_max_5x\n' "$US"; printf 'at.plan%s%s\n' "$US" "$NOW"
  printf 'at.limits%s%s\n' "$US" "$((NOW - 9999))"
  printf 'limit%sFable%s51%s6 16:00\n' "$US" "$US" "$US"; } > "$(cfile "$CD" "$CFG")"
O=$(render "$(pay)")
check "古い側も即返す（stale-while-revalidate）" \
  "$(all "$(has 'Enterprise 5x' "$O")" "$(has 'Fable' "$O")")" "$O"

# **③ キャッシュの鍵は config dir と securestorage dir の両方から作る。** キャッシュに入るのは
# `CLAUDE_SECURESTORAGE_CONFIG_DIR` で引いた Keychain の値なので、config dir だけで鍵にすると
# **同じ config dir で securestorage を分けた 2 つが互いのプラン名と枠を表示する**。
_cn() {  # _cn CONFIGDIR SECUREDIR → 生成されたキャッシュのファイル名
  local d; d=$(mkd)
  printf '%s' "$(pay)" | env CLAUDE_CONFIG_DIR="$1" CLAUDE_SECURESTORAGE_CONFIG_DIR="$2" \
    CLAUDE_STATUSLINE_V2_CACHE_DIR="$d" PATH="$NOBG:$PATH" "$SYNC" /bin/bash "$S" >/dev/null 2>&1
  cachename "$d"
}
_a=$(_cn /tmp/cfgX /tmp/ssA); _b=$(_cn /tmp/cfgX /tmp/ssB)
check "securestorage を分けたらキャッシュも分かれる" \
  "$([ -n "$_a" ] && [ "$_a" != "$_b" ] && echo 1)" "A=$_a B=$_b"
# **既定ではファイル名を変えない**（変えると全ユーザーが一斉に取り直す = 429 事故と同じ負荷）
_d1=$(mkd)
printf '%s' "$(pay)" | env -u CLAUDE_CONFIG_DIR -u CLAUDE_SECURESTORAGE_CONFIG_DIR \
  CLAUDE_STATUSLINE_V2_CACHE_DIR="$_d1" PATH="$NOBG:$PATH" "$SYNC" /bin/bash "$S" >/dev/null 2>&1
_n1=$(cachename "$_d1")
# **ファイルが無いときに緑にしない**（`no '__' ""` は 1 を返す。背景が書かなくなっても通ってしまう）
check "securestorage 未設定ならキャッシュ名に接尾辞を付けない" \
  "$(all "$_n1" "$(no '__' "$_n1")")" "[$_n1]"

echo "── 時刻: timeZone と timeFormat ──"
t_time() {  # t_time NAME SETTINGS EXPECT
  setup "$2"
  local L; L=$(render "$(pay "$FIVE")" 3)
  check "$1" "$(has "$3" "$L")" "$L"
  check "$1 — stderr 空" "$([ ! -s "$ERR" ] && echo 1)" "$(cat "$ERR")"
}
t_time "timeZone: UTC"              '{"timeZone":"UTC"}'                    '10:30'
# **夏時間の無いゾーンで見る** — `America/New_York` の `06:30` は夏時間の間だけ正しく、
# 11 月に入った日から `05:30` になって落ちた（2026-11-04。時限爆弾の季節版）。
# Kolkata は +05:30 固定で、開発機の JST とも UTC とも違うので設定が効いたことも見分けられる。
t_time "timeZone: Asia/Kolkata"     '{"timeZone":"Asia/Kolkata"}'            '16:00'
# **`12-hour` はゾーンも一緒に固定する** — 期待値をシステムの TZ に依存させると
# **開発機のゾーン以外で落ちる**（JST 前提の `7:30 PM` が UTC で `10:30 AM` になった）。
t_time "timeFormat: 12-hour"        '{"timeFormat":"12-hour","timeZone":"UTC"}'  '10:30 AM'
t_time "timeFormat: 24-hour-utc"    '{"timeFormat":"24-hour-utc","timeZone":"America/New_York"}' '10:30Z'
# **不正なゾーン名は必ず落とす** — libc は黙って UTC にするが上流はシステムのゾーンに戻す。
# 落とさないと「UTC の時刻をローカルだと思って読む」誤読になる。判定は TZif マジック 4 バイト。
setup; SYS=$(render "$(pay "$FIVE")" 3)
for z in JST Asia zone.tab ../../etc/passwd /etc/localtime ':Asia/Tokyo'; do
  setup "$(printf '{"timeZone":"%s"}' "$z")"
  L=$(render "$(pay "$FIVE")" 3)
  check "不正なゾーン '$z' はシステムのゾーンに戻る" \
    "$([ "$L" = "$SYS" ] && [ ! -s "$ERR" ] && echo 1)" "$L / $(cat "$ERR")"
done
# 壊れた settings でも既定に倒れる（`--slurpfile` だと抽出ごと死ぬ）
for s in 'not json{' '[]' '5' '"x"'; do
  setup "$s"
  L=$(render "$(pay "$FIVE")" 3)
  check "壊れた settings '$s' で既定表記" "$([ "$L" = "$SYS" ] && [ ! -s "$ERR" ] && echo 1)" "$L / $(cat "$ERR")"
done

echo "── ゲージ ──"
# **ゲージは数値の代わりではなく、数値の隣に置く比較の道具**（単独では 5% と 40% が読めない）
for pct in 0 1 4 43 88 100; do
  setup
  L=$(render "$(printf '{"version":"2.1.260","model":{"display_name":"Opus 5"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":%s}}' "$D" "$pct")" 3)
  check "context ${pct}% にゲージと数値が並ぶ" "$(has "${pct}%" "$L")" "$L"
done
setup
L=$(render "$(printf '{"version":"2.1.260","model":{"display_name":"Opus 5"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":100}}' "$D")" 3)
check "100% はバーが 5 セル埋まる" "$(has '⣿⣿⣿⣿⣿' "$L")" "$L"

echo "── 枠が尽きかけているとき（90%+ は要素まるごと赤）──"
# **バーだけ赤にすると「要素が 2 つに割れて見える」**（2026-09-07 に実機で却下した形）ので、
# 90%+ では識別色（`5h`=ANTH / `week`=dim ANTH / モデル別枠=モデル色）を**置き換える**。
# **3 枠すべて 90/89 の厳密境界で対に持つ**（90 で赤・89 で赤くない）。片方だけだと「常に赤」に
# する変更も「絶対に赤くしない」変更も、どちらかがテストを消さずに入る。**境界を 91/88 のように
# 緩めると `>=` を `>` にする mutant が緑のまま通る**（91 は `>` でも赤くなるので区別できない）。
RED_ESC=$(printf '\033[31m'); DIM_ESC=$(printf '\033[2m')
# **赤の needle は要素にアンカーする**（`${RED_ESC}5h:` の形）— 「3 行目のどこかに赤がある」だけだと
# **狙いを外した赤でも通る**。アンカーすればその要素が赤いことを直接見る。
# **パレットの値（180 / 95 …）は焼き込まない** — 識別色は「可読性のため自由に調整して良い」ものなので、
# 焼き込むとパレットを触った日に**枠のテストが赤くなって原因を誤らせる**。スイープの有無は
# **`38;5;` の異なる色数**で見る（グラデは 3 ストップ以上 = 必ず複数、赤 1 色は 31 の 1 つだけ）。
ncol() { printf '%s' "$1" | grep -o $'\033\[38;5;[0-9]*m' | sort -u | grep -c .; }
lim() {  # lim FIVE SEVEN → payload
  printf '{"version":"2.1.260","model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":31,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":%s},"seven_day":{"used_percentage":%s}}}' "$D" "$1" "$2"
}
# **枠ごとに 1 件ずつ見る。** 「5h と week のどちらかが赤」で束ねると、**片方の赤を外す変更で
# 緑のまま**になる（2026-09-16 の mutation で実証: 5h の赤を外しても week が赤いので通った）。
# 見たい枠だけを 90%+ にして、もう一方は閾値未満に置く。
setup; O=$(rawr "$(lim 90 10)" 3)
check "5h だけが 90%+ なら 5h が赤くなる" \
  "$(all "$(has "${RED_ESC}5h:" "$O")" "$(no 'jq error' "$O")")" "$(printf '%s' "$O" | cat -v)"
setup; O=$(rawr "$(lim 10 90)" 3)
check "week だけが 90%+ なら week が赤くなる" \
  "$(all "$(has "${RED_ESC}week:" "$O")" "$(no 'jq error' "$O")")" "$(printf '%s' "$O" | cat -v)"
check "90%+ の week は dim を外す（アラームを二次情報にしない）" \
  "$(no "${DIM_ESC}${ANTH_ESC}week:" "$O")" "$(printf '%s' "$O" | cat -v)"
setup; O=$(rawr "$(lim 89 89)" 3)
check "89% では赤くならない（識別色のまま）" \
  "$(all "$(no "$RED_ESC" "$O")" "$([ "$(ncol "$O")" -ge 2 ] && printf 1)")" "$(printf '%s' "$O" | cat -v)"
# モデル別枠は**モデル色のスイープを捨てて**赤 1 色にする（1 要素に色系統を 2 つ入れない）
setup; seed "" 90 "3 16:00"; O=$(rawr "$(lim 10 10)" 3); N_HI=$(ncol "$O")
check "モデル別枠が 90%+ なら赤になり、モデル色のスイープが消える" \
  "$(all "$(has "${RED_ESC}Fable:" "$O")" "$([ "$N_HI" -le 2 ] && printf 1)")" "$(printf '%s' "$O" | cat -v)"
setup; seed "" 89 "3 16:00"; O=$(rawr "$(lim 10 10)" 3); N_LO=$(ncol "$O")
check "89% のモデル別枠はモデル色のスイープを保つ" \
  "$(all "$(no "$RED_ESC" "$O")" "$([ "$N_LO" -gt "$N_HI" ] && printf 1)")" "色数 89%%=$N_LO / 90%%=$N_HI  $(printf '%s' "$O" | cat -v)"

echo "── モデル別週間枠の 0% は隠す ──"
# **`week:` と同じ扱い**（2026-09-16）。モデル別枠も**週間の**枠なので、規則「0% を隠すのは
# 週間の枠だけ」がそのまま当たる（`5h` だけは 0% でも出す = 左端の一目確認用）。
# **「0 を出さない」と「非 0 が同時に生き残る」を対で持つ** — 前者だけだと**全部隠す**変更が、
# 後者だけだと**全部出す**変更が、どちらもテストを消さずに入る。レコードは複数ありうるので、
# **1 件でも 0% があったら行ごと落ちる**ような実装になっていないことも同時に見る。
setup; seed "" 0 "6 16:00"
O=$(render "$(pay "$FIVE")" 3)
check "モデル別枠が 0% なら出さない" \
  "$(all "$(no 'Fable' "$O")" "$(no 'jq error' "$O")" "$(has '5h:' "$O")")" "$O"
setup; seed "" 38 "6 16:00"
O=$(render "$(pay "$FIVE")" 3)
check "モデル別枠が非 0% なら出す" \
  "$(all "$(has 'Fable' "$O")" "$(has '38%' "$O")")" "$O"
setup; seed2 0 41
O=$(render "$(pay "$FIVE")" 3)
check "0% と非 0% が混在したら非 0% だけ残る" \
  "$(all "$(no 'Fable' "$O")" "$(has 'Opus:' "$O")" "$(has '41%' "$O")")" "$O"

echo "── 回帰: 2026-09-08 のレビューで見つかった 9 件 ──"
# **① `current_dir` に `/` が無いと無限ループしていた。** `${_d%/*}` は `/` の無い文字列を
# 変えずに返す。既定は `.` で、**jq が無い・落ちた場合も `.`** なので「jq 未インストールで
# git 管理外を開く」だけで 100% CPU に張り付く。**`grep -c` では捕まらない**（返ってこない）。
setup
_wd=$(mkd)
( cd "$_wd" && printf '%s' '{"version":"2.1.260","model":{"display_name":"Opus 5"}}' \
  | env CLAUDE_CONFIG_DIR="$CFG" CLAUDE_STATUSLINE_V2_CACHE_DIR="$CD" \
    CLAUDE_STATUSLINE_NO_NET=1 /bin/bash "$S" >"$CD/loop.out" 2>&1 ) &
_lp=$!; _n=0
while kill -0 $_lp 2>/dev/null && [ $_n -lt 5 ]; do sleep 1; _n=$((_n + 1)); done
if kill -0 $_lp 2>/dev/null; then kill -9 $_lp 2>/dev/null; _looped=1; else _looped=""; fi
check "current_dir に / が無く git 管理外でも終了する（無限ループ回帰）" \
  "$([ -z "$_looped" ] && echo 1)" "5 秒経っても終わらない"

# **④ `$HOME` はパス成分で一致させる**（前方一致だと `/Users/user2` が `~2` になる）
setup
L=$(HOME=/nonexistent-home render "$(printf '{"version":"2.1.260","model":{"display_name":"Opus 5"},"workspace":{"current_dir":"/nonexistent-home2/dev"},"context_window":{"used_percentage":31}}')" 2)
check "\$HOME を前方一致で畳まない（~2/dev にしない）" "$(no '~2' "$L")" "$L"
setup
L=$(HOME=/nonexistent-home render "$(printf '{"version":"2.1.260","model":{"display_name":"Opus 5"},"workspace":{"current_dir":"/nonexistent-home/dev"},"context_window":{"used_percentage":31}}')" 2)
check "\$HOME 配下は畳む" "$(has '~/dev' "$L")" "$L"

# **⑤ `context_window_size` が整数でないと `(( ))` が毎描画 stderr に漏れる**
setup
O=$(render "$(printf '{"version":"2.1.260","model":{"display_name":"Opus 5"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":31,"context_window_size":1000000.5}}' "$D")")
check "ctx_size が小数でも stderr が空" "$(empty "$ERR")" "$(cat "$ERR")"
check "ctx_size が小数でも分母を出す" "$(has '/1M' "$O")" "$O"

# **⑥ 表示に載る文字列の制御文字**（改行が 3 行契約を割り、ESC が ANSI 注入になる）
for fld in current_dir model version; do
  setup
  case "$fld" in
    current_dir) J='{"version":"2.1.260","model":{"display_name":"Opus 5"},"workspace":{"current_dir":"/tmp/a\nb"},"context_window":{"used_percentage":31}}' ;;
    model)       J='{"version":"2.1.260","model":{"display_name":"Op\nus"},"workspace":{"current_dir":"'"$D"'"},"context_window":{"used_percentage":31}}' ;;
    version)     J='{"version":"2.1\n260","model":{"display_name":"Opus 5"},"workspace":{"current_dir":"'"$D"'"},"context_window":{"used_percentage":31}}' ;;
  esac
  O=$(render "$J")
  check "$fld に改行が入っても契約を守る" "$(contract "$O")" "$O"
done

# **⑨ detached HEAD は赤 + 短縮 sha**（普通のブランチと同じ橙だと平常に見える）
setup
_dt=$(mkd)
( cd "$_dt" && git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m x \
  && git checkout -q --detach ) >/dev/null 2>&1
RAW=$(printf '%s' "$(printf '{"version":"2.1.260","model":{"display_name":"Opus 5"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":31}}' "$_dt")" \
  | env CLAUDE_CONFIG_DIR="$CFG" CLAUDE_STATUSLINE_V2_CACHE_DIR="$CD" CLAUDE_STATUSLINE_NO_NET=1 \
    /bin/bash "$S" 2>/dev/null | sed -n 2p)
check "detached HEAD は短縮 sha を出す" "$(has 'HEAD@' "$RAW")" "$(printf '%s' "$RAW" | tr -d '\033')"
check "detached HEAD は赤（状態の色）" "$(has "$(printf '\033[31m')" "$RAW")" "色コード無し"

echo "── prompt_cache: caching_observed の gate（2.1.270）──"
# **キャッシュトークンを報告しないプロバイダ / ゲートウェイでは `warm` が常に `false`** なので、
# gate が無いと**永久に `cold` が出続ける**（誤読）。2.1.270 の `/statusline` プロンプトが
# `caching_observed == true and warm == false` を公式の作法にした。こちらは **`== false` で
# 落とす**向きで実装してある — absent は「このフィールドを持たない旧 CC」だけの経路なので、
# `== true` にすると旧 CC で cold が黙って消える。**3 通りを対で持つ**（片方だけだと、
# gate を消す変更も gate を全部落とす変更も、どちらかがテストを消さずに入る）。
setup
O=$(render "$(pay ',"prompt_cache":{"warm":false,"caching_observed":false}')")
check "caching_observed:false なら cold を出さない" \
  "$(all "$(no 'cold' "$O")" "$(no 'jq error' "$O")" "$(contract "$O")")" "$O"
setup
O=$(render "$(pay ',"prompt_cache":{"warm":false,"caching_observed":true,"last_miss_cause":{"causes":["ttl_expired_5m"]}}')")
check "caching_observed:true なら cold を出す" \
  "$(all "$(has 'cold' "$O")" "$(no 'jq error' "$O")")" "$O"
setup
O=$(render "$(pay ',"prompt_cache":{"warm":false}')")
check "caching_observed が無い旧 CC では cold を出す" \
  "$(all "$(has 'cold' "$O")" "$(no 'jq error' "$O")")" "$O"
# **型が変わっても抽出ごと落とさない。** 未文書の payload なので boolean 以外が来る前提で守る
# （`contract` だけ見る assert は弱い — 抽出が abort すると 1 行になって契約は満たす）。
setup
O=$(render "$(pay ',"prompt_cache":{"warm":false,"caching_observed":"yes"}')")
check "caching_observed が文字列でも抽出が生き残る" \
  "$(all "$(no 'jq error' "$O")" "$(has '31%' "$O")")" "$O"

echo "── prompt_cache: warm の TTL と期限 / miss の原因（warm）/ cold ──"
# **期限は分に切り捨てる**（10:30:50 切れを 10:31 と出すと、間に合うと読んで間に合わない）。
# 時刻は「未来の固定した分」+ ゾーン固定で起こす（`E5` の作法）。**経路は 2 本ある** — 既定は
# 最初の jq がプロセスの TZ で整形し、`timeZone` があると `_rt` が整形し直す。片方だけ見ると
# もう片方の切り捨て・過去チェックを外しても緑になる。**プロセスの TZ も固定する** — `timeZone`
# のケースをプロセス TZ=UTC の環境で回すと、`_rt` が無くても最初の jq の結果が一致して緑になる。
renderz() {  # renderz PROC_TZ PAYLOAD LINE — render をプロセスの TZ を固定して回す
  printf '%s' "$2" | env TZ="$1" CLAUDE_CONFIG_DIR="$CFG" CLAUDE_STATUSLINE_V2_CACHE_DIR="$CD" \
    CLAUDE_STATUSLINE_NO_NET=1 /bin/bash "$S" 2>"$ERR" | strip | sed -n "${3}p"
}
# PCW は misses:4 を持つが last_miss_at が無い = TTL 内の miss が無いので、`×` は出ない
PCW=',"prompt_cache":{"warm":true,"caching_observed":true,"ttl":"5m","misses":4,"expires_at":'
setup
O=$(renderz UTC "$(pay "${PCW}$((E5 + 50))}")" 3)
check "warm は TTL と期限（分に切り捨て）を出す — 既定の経路" \
  "$(all "$(has 'cache 5m 10:30' "$O")" "$(no 'cold' "$O")" "$(no '×' "$O")" "$(no 'jq error' "$O")")" "$O"
setup '{"timeZone":"UTC"}'
O=$(renderz Asia/Tokyo "$(pay "${PCW}$((E5 + 50))}")" 3)
check "warm は TTL と期限（分に切り捨て）を出す — timeZone の経路" "$(has 'cache 5m 10:30' "$O")" "$O"
setup '{"timeFormat":"12-hour","timeZone":"UTC"}'
O=$(renderz Asia/Tokyo "$(pay "${PCW}${E5}}")" 3)
check "warm の期限は timeFormat に追従する" "$(has 'cache 5m 10:30 AM' "$O")" "$O"
# 過去の期限は出さない（未来の時刻に読める誤読）。TTL だけは残る。2 経路とも見る
for _pz in '' '{"timeZone":"UTC"}'; do
  setup "${_pz:-{\}}"
  O=$(renderz Asia/Tokyo "$(pay "${PCW}1000}")" 3)
  check "warm でも過去の期限は出さない（settings: ${_pz:-なし}）" \
    "$(all "$(has 'cache 5m' "$O")" "$(no ':16' "$O")")" "$O"
done
setup
O=$(render "$(pay ',"prompt_cache":{"warm":true,"caching_observed":false,"ttl":"5m","expires_at":'"$E5"'}')" 3)
check "caching_observed:false なら warm も出さない" "$(no 'cache' "$O")" "$O"
setup
O=$(render "$(pay ',"prompt_cache":{"warm":true,"caching_observed":true}')" 3)
check "TTL も期限も無い warm は何も出さない（裸の cache にしない）" "$(no 'cache' "$O")" "$O"
# TTL は形を見て通す（未文書なので任意文字列を画面に出さない）。前後どちらの崩れも見る
for _t in '5m x' 'x5m'; do
  setup
  O=$(renderz UTC "$(pay ',"prompt_cache":{"warm":true,"caching_observed":true,"ttl":"'"$_t"'","expires_at":'"$E5"'}')" 3)
  check "形の崩れた TTL '$_t' は出さない" "$(all "$(no "$_t" "$O")" "$(has 'cache 10:30' "$O")")" "$O"
done
# **warm は橙 209、cold は青 111**（2.19.0。色の温度を状態に合わせる）。行末に置いて、閉じ忘れも一緒に見る
# **`case` は関数に出す** — bash 3.2 は `$( )` の中の `case` のパターンの `)` で置換を閉じてしまい、
# 何を渡しても非空になる（RST を外した mutant が緑で通った）。
ends() { case "$2" in *"$1") printf 1 ;; esac; }   # ends SUFFIX HAYSTACK
setup
_raw=$(rawr "$(pay "${PCW}${E5}}")" 3)
check "warm は橙 209 で、行末で閉じる" \
  "$(all "$(has $'\033[38;5;209mcache 5m' "$_raw")" "$(ends "$(printf '\033[0m')" "$_raw")")" "$(printf '%s' "$_raw" | cat -v)"
setup
_raw=$(rawr "$(pay ',"prompt_cache":{"warm":false,"caching_observed":true,"ttl":"5m"}')" 3)
check "cold は COLD の色で、行末で閉じる" \
  "$(all "$(has $'\033[38;5;111mcold' "$_raw")" "$(ends "$(printf '\033[0m')" "$_raw")")" "$(printf '%s' "$_raw" | cat -v)"
# **2.19.0: miss は warm の側に「miss <時刻> <原因>」で、miss の直後 5 分だけ出す。`×N` は出さない。**
# miss でもキャッシュを書き直すので warm のまま。cold は放置で切れたときだけで、原因を付けない。
# **対で持つ**: 窓の内（10 秒前）／外（400 秒前）／TTL が 1h でも 5 分で切る（1800 秒前）／未来の時刻。
CW_SGR=$'\033[38;5;209m'  # warm の色（生リテラルで pin）
setup
_raw=$(rawr "$(pay "$FIVE"',"cost":{"total_cost_usd":12.3}')" 3)
check "5h は淡いアクア 116、\$ は金 179（2.19.0）" \
  "$(all "$(has $'\033[38;5;116m5h:' "$_raw")" "$(has $'\033[38;5;179m$12.30' "$_raw")")" "$(printf '%s' "$_raw" | cat -v)"
LM=$((NOW - 10)); MT=$(TZ=UTC date -r "$LM" +%H:%M)
PCM=',"prompt_cache":{"warm":true,"caching_observed":true,"ttl":"5m","expires_at":'"$E5"',"last_miss_at":'"$LM"
setup
O=$(renderz UTC "$(pay "${PCM}"',"misses":4,"last_miss_cause":{"causes":["tools_changed"],"tools_added":2,"tools_removed":1}}')" 3)
check "warm で miss の直後なら miss の時刻・原因・ツール増減を出す（×N は出さない）" \
  "$(all "$(has "cache 5m 10:30 miss $MT tools_changed +2 -1" "$O")" "$(no '×' "$O")")" "$O"
setup '{"timeZone":"Asia/Kolkata"}'
O=$(renderz UTC "$(pay "${PCM}"',"last_miss_cause":{"causes":["effort_changed"]}}')" 3)
check "miss の時刻も timeZone に追従する" "$(has "miss $(TZ=Asia/Kolkata date -r "$LM" +%H:%M) effort_changed" "$O")" "$O"
setup '{"timeFormat":"12-hour","timeZone":"UTC"}'
O=$(renderz Asia/Tokyo "$(pay "${PCM}"',"last_miss_cause":{"causes":["effort_changed"]}}')" 3)
check "miss の時刻も timeFormat に追従する" "$(has "miss $(LC_ALL=C TZ=UTC date -r "$LM" '+%-I:%M %p') effort_changed" "$O")" "$O"
setup
O=$(renderz UTC "$(pay ',"prompt_cache":{"warm":true,"caching_observed":true,"ttl":"5m","expires_at":'"$E5"',"last_miss_at":'"$((NOW - 400))"',"last_miss_cause":{"causes":["tools_changed"],"tools_added":2}}')" 3)
check "5 分を過ぎた miss は出さない" \
  "$(all "$(has 'cache 5m 10:30' "$O")" "$(no 'miss' "$O")" "$(no 'tools_changed' "$O")")" "$O"
setup '{"timeZone":"Asia/Kolkata"}'
O=$(renderz UTC "$(pay ',"prompt_cache":{"warm":true,"caching_observed":true,"ttl":"5m","expires_at":'"$E5"',"last_miss_at":'"$((NOW - 400))"',"last_miss_cause":{"causes":["tools_changed"]}}')" 3)
check "timeZone の経路でも 5 分を過ぎた miss は出さない" "$(all "$(has 'cache 5m' "$O")" "$(no 'miss' "$O")")" "$O"
setup
O=$(renderz UTC "$(pay ',"prompt_cache":{"warm":true,"caching_observed":true,"ttl":"1h","expires_at":'"$E5"',"last_miss_at":'"$((NOW - 1800))"',"last_miss_cause":{"causes":["model_changed"]}}')" 3)
check "TTL が 1h でも窓は 5 分（30 分前の miss は出さない）" \
  "$(all "$(has 'cache 1h 10:30' "$O")" "$(no 'model_changed' "$O")")" "$O"
setup
O=$(renderz UTC "$(pay ',"prompt_cache":{"warm":true,"caching_observed":true,"ttl":"1h","expires_at":'"$E5"',"last_miss_at":'"$((NOW - 240))"',"last_miss_cause":{"causes":["model_changed"]}}')" 3)
check "4 分前の miss は出す（窓の内側）" "$(has 'cache 1h 10:30 miss' "$O")" "$O"
setup
O=$(renderz UTC "$(pay ',"prompt_cache":{"warm":true,"caching_observed":true,"ttl":"5m","expires_at":'"$E5"',"last_miss_at":'"$((NOW + 600))"',"last_miss_cause":{"causes":["unknown"]}}')" 3)
check "未来の last_miss_at は出さない（時計のずれ）" "$(all "$(has 'cache 5m 10:30' "$O")" "$(no 'miss' "$O")")" "$O"
setup
O=$(render "$(pay ',"prompt_cache":{"warm":false,"caching_observed":true,"ttl":"5m","misses":4,"last_miss_at":'"$LM"',"last_miss_cause":{"causes":["tools_changed"],"tools_added":2,"tools_removed":1}}')" 3)
check "cold は TTL だけ（原因・miss・回数を出さない）" \
  "$(all "$(has 'cold 5m' "$O")" "$(no 'tools_changed' "$O")" "$(no 'miss' "$O")" "$(no '×' "$O")")" "$O"
setup
O=$(render "$(pay "${PCM}"',"last_miss_cause":{"causes":["tools_changed"],"tools_added":0,"tools_removed":1}}')" 3)
check "ツール増減は 0 の側を添えない" "$(all "$(has 'tools_changed -1' "$O")" "$(no '+0' "$O")")" "$O"
setup
O=$(render "$(pay "${PCM}"',"last_miss_cause":{"causes":["system_prompt_changed"],"system_char_delta":-340}}')" 3)
check "システムプロンプトの文字数の増減は添えない" \
  "$(all "$(has 'system_prompt_changed' "$O")" "$(no '340' "$O")")" "$O"
# 原因と数の対応を取り違えない（ツール数は tools_changed のときだけ）
setup
O=$(render "$(pay "${PCM}"',"last_miss_cause":{"causes":["ttl_expired_5m"],"tools_added":2}}')" 3)
check "原因に対応しない数は添えない" "$(all "$(has 'ttl_expired_5m' "$O")" "$(no '+2' "$O")")" "$O"
setup
O=$(renderz UTC "$(pay "${PCM}"'}')" 3)
check "原因が無い miss でも miss の時刻は出す" "$(has "miss $MT" "$O")" "$O"
# **warm に付けた miss も 1 要素 1 色**（strip した文字列では色を外しても dim を足しても緑になるので、
# 生の出力で「先頭の SGR から行末の RST まで別の SGR が無い」を見る）
one_sgr() {  # one_sgr PREFIX HAYSTACK — PREFIX の後ろが RST 1 つで終わり、途中に ESC が無いなら 1
  local r="${2#*"$1"}" e=$'\033[0m'
  [ "$r" != "$2" ] || return 0
  local b="${r%"$e"}"
  [ "$b" != "$r" ] || return 0
  case "$b" in *$'\033'*) ;; *) printf 1 ;; esac
}
setup
_raw=$(rawr "$(pay "${PCM}"',"last_miss_cause":{"causes":["tools_changed"],"tools_added":2}}')" 3)
check "warm に付けた miss も同じ 1 色で、行末で閉じる" \
  "$(all "$(has 'tools_changed +2' "$_raw")" "$(one_sgr "${CW_SGR}cache 5m" "$_raw")")" "$(printf '%s' "$_raw" | cat -v)"
# 型が変わっても抽出ごと落とさない
setup
O=$(render "$(pay ',"prompt_cache":{"warm":false,"ttl":5,"expires_at":"x","misses":"3","last_miss_at":"x","last_miss_cause":{"causes":["tools_changed"],"tools_added":"2"}}')")
check "prompt_cache の各フィールドの型が変わっても抽出が生き残る" \
  "$(all "$(no 'jq error' "$O")" "$(has 'cold' "$O")" "$(has '31%' "$O")")" "$O"
setup
O=$(render "$(pay "${PCM}"',"misses":"3","last_miss_cause":{"causes":["tools_changed"],"tools_added":"2"}}')")
check "warm の miss の各フィールドの型が変わっても原因は生き残る" \
  "$(all "$(no 'jq error' "$O")" "$(has 'tools_changed' "$O")" "$(no '+2' "$O")")" "$O"
setup
O=$(render "$(pay ',"prompt_cache":{"warm":true,"caching_observed":true,"ttl":"5m","expires_at":'"$E5"',"last_miss_at":"x","last_miss_cause":{"causes":["tools_changed"]}}')")
check "last_miss_at が数でなければ miss を出さない（抽出は生き残る）" \
  "$(all "$(no 'jq error' "$O")" "$(no 'tools_changed' "$O")" "$(has 'cache 5m' "$O")")" "$O"
setup
O=$(render "$(pay ',"prompt_cache":{"warm":false,"last_miss_cause":"s"}')")
check "last_miss_cause が文字列でも抽出が生き残る" \
  "$(all "$(no 'jq error' "$O")" "$(has 'cold' "$O")")" "$O"

echo "── 1 行目: 宛名と session id ──"
setup; L=$(render "$(pay ',"fast_mode":true')" 1)
check "fast_mode が true なら fast を出す" "$(has 'fast' "$L")" "$L"
setup; L=$(render "$(pay ',"fast_mode":"true"')" 1)
check "fast_mode が文字列の true なら出さない" "$(no 'fast' "$L")" "$L"
# **宛名は `session_name` と同じなら出さない／違えば出す**を対で持つ（片方だけだと「常に出さない」
# 変更が緑で通る）。**session id は行末に全桁**（`--resume` は 8 桁を受けない）。
SID="8505e86d-3f0c-4c97-afc4-6237463f3650"
peer_fixture() {  # peer_fixture NAME — sessions/<pid>.json を実物の並び（formerNames が後ろ）で置く
  mkdir -p "$CFG/sessions"
  printf '{"pid":1,"sessionId":"%s","name":"%s","nameSource":"auto","formerNames":[{"name":"OLDNAME"}]}' \
    "$SID" "$1" > "$CFG/sessions/1.json"
}
setup; peer_fixture "same title"
L=$(render "$(pay ",\"session_id\":\"$SID\",\"session_name\":\"same title\"")" 1)
check "宛名が session_name と同じなら出さない" "$(no 'same title' "$L")" "$L"
setup; peer_fixture "renamed-peer"
L=$(render "$(pay ",\"session_id\":\"$SID\",\"session_name\":\"same title\"")" 1)
check "宛名が session_name と違えば出す" "$(has 'renamed-peer' "$L")" "$L"
setup; peer_fixture "renamed-peer"
L=$(render "$(pay ",\"session_id\":\"$SID\"")" 1)
check "session_name が無い（旧 CC）なら宛名を出す" "$(has 'renamed-peer' "$L")" "$L"
# 比較は**完全一致**（部分一致にすると `… 配布` と `… 配布 ⑂ codex` の実例で宛名が消える）
setup; peer_fixture "same title"
L=$(render "$(pay ",\"session_id\":\"$SID\",\"session_name\":\"same title ⑂ codex\"")" 1)
check "宛名が session_name の前方部分なだけなら出す" "$(has 'same title' "$L")" "$L"
# **JSON のエスケープを含む宛名は出さない**（最初の `"` で切るので `a \"b\" c` が `a \` になる）
setup; mkdir -p "$CFG/sessions"
printf '{"pid":1,"sessionId":"%s","name":"a \\"b\\" c","nameSource":"user"}' "$SID" > "$CFG/sessions/1.json"
L=$(render "$(pay ",\"session_id\":\"$SID\",\"session_name\":\"other\"")" 1)
check "エスケープを含む宛名は出さない" "$(all "$(no 'a \' "$L")" "$(no 'other' "$L")")" "$L"
setup; peer_fixture "plain-peer"
L=$(render "$(pay ",\"session_id\":\"$SID\",\"session_name\":\"other\"")" 1)
check "エスケープを含まない宛名は出す（上の対）" "$(has 'plain-peer' "$L")" "$L"
ends_sid() { case "$1" in *" $SID") printf 1 ;; esac; }
setup
L=$(render "$(pay ",\"session_id\":\"$SID\"")" 1)
check "session id は 1 行目の末尾に全桁で出す" "$(ends_sid "$L")" "$L"
setup
_raw=$(rawr "$(pay ",\"session_id\":\"$SID\"")" 1)
check "session id は dim で出す" "$(has $'\033[2m'"$SID"$'\033[0m' "$_raw")" "$(printf '%s' "$_raw" | cat -v)"
setup
O=$(render "$(pay ",\"session_id\":\"a*b c\"")")
check "英数字と - 以外を含む session id は出さない" \
  "$(all "$(no 'a*b' "$O")" "$(no 'jq error' "$O")" "$(empty "$ERR")")" "$O / $(cat "$ERR")"

echo "── セキュリティ ──"
# **OAuth トークンを argv に出さない**（`ps aux` 漏れ）。偽 curl の argv を記録して確かめる。
setup
SPY=$(mkd)
cat > "$SPY/curl" <<'EOS'
#!/bin/bash
printf '%s\n' "$@" > "$SPYLOG"
cat > "$SPYSTDIN"
printf '%s' '{"limits":[]}'
EOS
chmod +x "$SPY/curl"
printf '#!/bin/bash\nprintf %%s %s\n' \
  "'{\"claudeAiOauth\":{\"subscriptionType\":\"max\",\"rateLimitTier\":\"default_claude_max_20x\",\"accessToken\":\"SECRET-TOKEN\"}}'" > "$SPY/security"
chmod +x "$SPY/security"
printf '%s' "$(pay)" | env CLAUDE_CONFIG_DIR="$CFG" CLAUDE_STATUSLINE_V2_CACHE_DIR="$CD" \
  PATH="$SPY:$PATH" SPYLOG="$SPY/argv" SPYSTDIN="$SPY/stdin" "$SYNC" /bin/bash "$S" >/dev/null 2>&1
check "トークンが curl の argv に出ない" \
  "$(if [ ! -f "$SPY/argv" ] || ! grep -q 'SECRET-TOKEN' "$SPY/argv"; then echo 1; fi)" \
  "$(cat "$SPY/argv" 2>/dev/null)"
# **stdin に届いただけでは足りない** — 偽 curl は渡された stdin を全部記録するので、curl が `-H @-` を
# 付けずに stdin を読み捨てても緑になる（2026-10-08 の mutation で実証）。argv の `@-` も対で見る。
# `@-` は **`-H` の直後**でだけ数える（`--data-binary @-` でも stdin は届くが、ヘッダは送られない）。
check "トークンは stdin で渡る（-H @-）" \
  "$(all "$([ -s "$SPY/stdin" ] && grep -q 'SECRET-TOKEN' "$SPY/stdin" && echo 1)" \
         "$(awk 'p && $0 == "@-" {f = 1} {p = ($0 == "-H")} END {exit !f}' "$SPY/argv" 2>/dev/null && echo 1)")" \
  "stdin: $(head -c 60 "$SPY/stdin" 2>/dev/null) / argv: $(cat "$SPY/argv" 2>/dev/null | tr '\n' ' ')"
check "curl の argv に --config / -K が無い（設定ディレクティブ注入の経路）" \
  "$(if [ ! -f "$SPY/argv" ] || ! grep -qE -- '^(--config|-[a-zA-Z]*K)' "$SPY/argv"; then echo 1; fi)" \
  "$(cat "$SPY/argv" 2>/dev/null)"
# **`mkdir -p -m 700` が実際に走る経路で見る。** `mktemp -d` は最初から 0700 なので、
# それを stat するだけでは**この行を `mkdir -p` に書き換えても緑のまま**（mutation で実証）。
# **まだ存在しないディレクトリ**を CACHE_BASE に指定して、スクリプトに作らせてから見る。
_cb="$(mkd)/sub"
# ディレクトリは前景が背景を起こす前に作るので、待たずに見てよい（背景は偽の security / curl に向ける）
printf '%s' "$(pay)" | env CLAUDE_CONFIG_DIR="$CFG" CLAUDE_STATUSLINE_V2_CACHE_DIR="$_cb" \
  PATH="$NOBG:$PATH" /bin/bash "$S" >/dev/null 2>&1
check "スクリプトが作るキャッシュディレクトリは 700" \
  "$([ -d "$_cb" ] && [ "$(stat -f '%Sp' "$_cb")" = "drwx------" ] && echo 1)" \
  "$([ -d "$_cb" ] && stat -f '%Sp' "$_cb" || echo '作られなかった')"
# **描画は背景の取得を待たない**（seam を入れたので、背景で走ること自体を別に pin する）。偽 curl を 3 秒
# 寝かせても被験体は 1 秒以内に返ること。`& disown` を外す・`>/dev/null` を外す（親の stdout を握る）・
# `2>&1` だけを外す、のどれでも $( ) が curl の終わりを待つので赤くなる（stderr も受けているので）。
SLOW=$(mkd)
cp "$NOBG/security" "$SLOW/security"
printf '#!/bin/bash\ncat >/dev/null; sleep 3; printf %%s "{\\"limits\\":[]}"\n' > "$SLOW/curl"
chmod +x "$SLOW/curl"
setup
_t0=$SECONDS
_O=$(printf '%s' "$(pay)" | env CLAUDE_CONFIG_DIR="$CFG" CLAUDE_STATUSLINE_V2_CACHE_DIR="$CD" \
  PATH="$SLOW:$PATH" /bin/bash "$S" 2>&1)   # stderr も同じ pipe で受ける（`2>&1` だけ外す変更も捕まえる）
_dt=$((SECONDS - _t0))
check "描画は背景の取得を待たない（偽 curl が 3 秒かかっても 1 秒以内に返る）" \
  "$(all "$([ "$_dt" -le 1 ] && echo 1)" "$_O")" "${_dt} 秒"
# **Keychain のサービス名は config dir ごとに変わる**（決め打ちで引くと別アカウントの blob を読む）
check "Keychain のサービス名に config dir の sha256 先頭 8 桁を付ける" \
  "$(grep -q 'shasum -a 256' "$S" && grep -q 'Claude Code-credentials' "$S" && echo 1)" ""
check "credentials ファイルは securestorage 側から読む" \
  "$(grep -q 'SECURESTORAGE_DIR}/.credentials.json' "$S" && echo 1)" ""

# **Keychain のアカウント名は上流と同じ作り方**（2.1.281 のバイナリで確認）: `USER` → 無ければ
# 実ユーザー名 → **`^[a-zA-Z0-9._-]+$` に合わなければ `claude-code-user`**。上流は書き込みも同じ名前で
# するので、ずれると item を引けずプランが消える（画面は静かに要素が欠けるだけ = 気付けない）。
# **偽 `security` の argv で pin する**（ソースの grep だと「判定を書いたが使っていない」で通る）。
acct_of() {  # acct_of USER値 → security に渡った -a の値
  local sp; sp=$(mkd); setup
  printf '#!/bin/bash\nprintf "%%s\\n" "$@" > "%s/argv"\nprintf %%s %s\n' "$sp" \
    "'{\"claudeAiOauth\":{\"subscriptionType\":\"max\",\"rateLimitTier\":\"x\",\"accessToken\":\"T\"}}'" > "$sp/security"
  printf '#!/bin/bash\ncat >/dev/null; printf %%s "{\\"limits\\":[]}"\n' > "$sp/curl"
  chmod +x "$sp/security" "$sp/curl"
  # **`LOGNAME` に囮を置く** — 開発機では `LOGNAME` = `id -un` なので、置かないと「`LOGNAME` に倒す」
  # 旧実装でも同じ値になって緑のまま通る（security-auditor の mutation で実証。2026-09-24）。
  printf '%s' "$(pay)" | env USER="$1" LOGNAME=zz-not-me CLAUDE_CONFIG_DIR="$CFG" CLAUDE_STATUSLINE_V2_CACHE_DIR="$CD" \
    PATH="$sp:$PATH" "$SYNC" /bin/bash "$S" >/dev/null 2>&1
  awk 'p{print; exit} $0=="-a"{p=1}' "$sp/argv" 2>/dev/null
}
A=$(acct_of alice)
check "Keychain の -a は USER を使う" "$([ "$A" = alice ] && echo 1)" "-a=$A"
# **不正な位置を先頭・途中・末尾に散らす** — 末尾だけ不正な値（`bad name!`）だと、正規表現の `^` を
# 外す変更が緑のまま通る（security-auditor の mutation で実証）。
for _bad in '!alice' 'bad name' 'alice!'; do
  A=$(acct_of "$_bad")
  check "USER='$_bad' なら -a は claude-code-user（英数字 . _ - 以外を含む。上流と同じ）" \
    "$([ "$A" = claude-code-user ] && echo 1)" "-a=$A"
done
# **`-` で始まる値はそのまま通す**（上流も同じ正規表現で通す。引用しているので `security` は
# オプションではなくアカウント名として読む = 実機の `security` で rc=44 を確認済み）。
A=$(acct_of '-s')
check "USER='-s' はそのまま -a に渡す（上流と同じ。オプションとしては読まれない）" \
  "$([ "$A" = '-s' ] && echo 1)" "-a=$A"
A=$(acct_of '')
check "USER が空なら実ユーザー名を使う（service だけで引かない）" \
  "$([ -n "$A" ] && [ "$A" = "$(id -un)" ] && echo 1)" "-a=$A / id -un=$(id -un)"

echo "── モデル色 ──"
# **色 assert は生のリテラルで書く**（`$OPUS55_PAL` のような定数で書くと、どんな値に変えても通って
# 無断の再調整を検出できない）。**色は tier ごとに 1 本（最新の版）で、旧い版も同じ色**（2.18.0）。
# 版ごとに 1 件ずつ見る — 「どれかが合う」で束ねると、旧い版の arm を戻す変更が緑のまま通る。
# 旧い版の色（Opus 4.x coral 173 / Opus 5 の先頭 130 / Sonnet 4.6 teal 79 / Sonnet 4.5 amber 214 /
# Sonnet 5 の先頭 28 / Haiku 4.x lavender 183 / Fable 5 の先頭 178 / Fable 5.1 の先頭 95）が無いことも見る。
mcol() {  # mcol ID DISPLAY → Line 1 のモデル名に載った 38;5;N を空白区切りで
  setup
  printf '{"version":"2.1.281","model":{"id":"%s","display_name":"%s"},"workspace":{"current_dir":"/tmp"}}' "$1" "$2" \
    | env CLAUDE_CONFIG_DIR="$CFG" CLAUDE_STATUSLINE_V2_CACHE_DIR="$CD" CLAUDE_STATUSLINE_NO_NET=1 /bin/bash "$S" 2>/dev/null \
    | head -1 | grep -o $'\033\\[38;5;[0-9]*m' | sed 's/.*;//; s/m//' | sort -un | tr '\n' ' '
}
# **最新より古い版はグレー 244 の 1 色**（スイープの色が 1 つも載らない）。**スクリプトより新しい版
# （Opus 5.6）は古くない** — 「最新と一致しない」で判定する実装に戻すと、ここが赤くなる。
for _mv in \
  'claude-opus-5-5|Opus 5.5|130 173 215|61 139 244' 'claude-opus-5-6|Opus 5.6|130 173 215|244' \
  'claude-opus-5|Opus 5|244|130 173 215 61 139' 'claude-opus-4-6|Opus 4.6|244|130 173 215 61' \
  'claude-sonnet-5-5|Sonnet 5.5|25 68 110 153|28 79 214 244' \
  'claude-sonnet-5|Sonnet 5|244|25 68 110 153 28' 'claude-sonnet-4-6|Sonnet 4.6|244|25 68 110 153 79' \
  'claude-sonnet-4-5-20250929|Sonnet 4.5|244|25 68 110 153 214' \
  'claude-haiku-5-5|Haiku 5.5|168 175 222|183 244' 'claude-haiku-4-5-20251001|Haiku 4.5|244|168 175 222 183' \
  'claude-fable-5-2|Fable 5.2|98 140 182|178 95 244' 'claude-fable-5-1|Fable 5.1|244|98 140 182 95' \
  'claude-fable-5|Fable 5|244|98 140 182 178'; do
  IFS='|' read -r _id _dn _want _old <<EOF_MV
$_mv
EOF_MV
  C=$(mcol "$_id" "$_dn"); _ok=1
  for _n in $_want; do [ -n "$(has " $_n " " $C")" ] || _ok=""; done
  for _n in $_old; do [ -n "$(no " $_n " " $C")" ] || _ok=""; done
  check "$_dn は ${_want// / → }（最新は tier の色・古い版はグレー）" "$_ok" "色: $C"
done
# 3 行目の `Fable:` は版を持たない（`/usage` の `limits[]` は `"Fable"` だけ）= generic の arm。
# 名前の先頭が 98、`:` から先が名前の終わった色 182 になる（Line 1 と揃う）。
setup; seed "" 39 "6 16:00"; O=$(rawr "$(pay "$FIVE")" 3)
check "3 行目の版なし Fable: も 98 で始まり 182 で続く" \
  "$(all "$(has $'\033[38;5;98mF' "$O")" "$(has $'\033[38;5;182m:' "$O")")" "$(printf '%s' "$O" | cat -v)"

echo "── --subagent は削除した（2.18.0）──"
# settings に `subagentStatusLine` が残っている人のために、`--subagent` では**何も出さず exit 0**。
# 出力があると本体が行ごとに「non-JSON line」をログに書く。stderr も空であること。
setup; O=$(printf '%s' '{"columns":120,"tasks":[{"id":"a1","type":"local_agent","label":"x","model":"claude-haiku-4-5"}]}' \
  | env CLAUDE_CONFIG_DIR="$CFG" CLAUDE_STATUSLINE_V2_CACHE_DIR="$CD" CLAUDE_STATUSLINE_NO_NET=1 /bin/bash "$S" --subagent 2>"$ERR"; echo "rc=$?")
check "--subagent では何も出さず exit 0（既定の行に任せる）" "$(all "$([ "$O" = "rc=0" ] && echo 1)" "$(empty "$ERR")")" "[$O] stderr: $(cat "$ERR")"

echo "── 衛生（メタテスト）──"
# **`bash "$S"` と書くと最重要制約（3.2 互換）を一切検証しないテストになる。**
# 回数ではなく「`/bin/bash` 以外で被験体を起こしている行が 0 か」で見る。
check "被験体を /bin/bash 以外で起動していない" \
  "$([ "$(grep -nE '(^|[^/])bash (-[a-z]+ )*"\$S"' "$0" | grep -cvE '^[0-9]+: *#')" = 0 ] && echo 1)" \
  "$(grep -nE '(^|[^/])bash (-[a-z]+ )*"\$S"' "$0" | grep -vE '^[0-9]+: *#' | head -3)"
check "bash 3.2 で構文が通る" "$(/bin/bash -n "$S" 2>/dev/null && echo 1)" "$(/bin/bash -n "$S" 2>&1)"
check "shebang が #!/bin/bash" "$([ "$(head -1 "$S")" = '#!/bin/bash' ] && echo 1)" "$(head -1 "$S")"
check "bash 4+ 構文が無い" \
  "$([ "$(grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^)|printf .%\(|declare -A|mapfile|readarray|<<<' "$S" | grep -cvE '^[0-9]+: *#')" = 0 ] && echo 1)" \
  "$(grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^)|printf .%\(|declare -A|mapfile|readarray|<<<' "$S" | grep -vE '^[0-9]+: *#' | head -3)"
check "GNU 専用の flag が無い（stat -c / date -d / md5sum 等）" \
  "$([ "$(grep -nE '\bstat -c|\bdate -d|\bdate --date|\bmd5sum|readlink -f|grep -P' "$S" | grep -cvE '^[0-9]+: *#')" = 0 ] && echo 1)" \
  "$(grep -nE '\bstat -c|\bdate -d|\bmd5sum|readlink -f|grep -P' "$S" | grep -vE '^[0-9]+: *#' | head -3)"
check "生の制御文字が埋まっていない" "$([ "$(grep -c "$US" "$S")" = 0 ] && echo 1)" "$(grep -n "$US" "$S" | head -2)"
check "source していない（1 ファイルで完結）" \
  "$([ "$(grep -cE '^[[:space:]]*(source|\.) ' "$S")" = 0 ] && echo 1)" "$(grep -nE '^[[:space:]]*(source|\.) ' "$S")"
# **3 行目の閾値は 1 つ**（CHANGELOG 2.2.0 と CLAUDE.md がそう言っている）。context の上限に
# リテラルの数字を戻すと `LIMIT_HI` を動かしたときにここだけ取り残され、**両方のドキュメントが
# 黙って嘘になる**（出力は今日は同じなので描画のテストでは捕まらない = ソースを見るしかない）。
check "context の上限は LIMIT_HI を渡している（リテラルを戻していない）" \
  "$(all "$(grep -c 'color_by_threshold "\$used_pct" "\$LIMIT_HI"' "$S")" \
         "$([ "$(grep -c 'color_by_threshold "\$used_pct" 9' "$S")" = 0 ] && echo 1)")" \
  "$(grep -n 'color_by_threshold "\$used_pct"' "$S")"
# **各行は SGR を閉じて終わる**（2.1.281 から本体の契約になった）。本体は複数行の出力を行ごとに
# 描くとき、**前の行までに出た SGR と OSC 8 を全部つないで次の行の頭に足す**（2.1.278 には無く
# 2.1.281 にある分割関数。正規表現は `\x1b\[[\d;]*m|\x1b\]8;…`）。行末で色を開いたままにすると
# **次の行の頭から色が漏れる** — 以前は行ごとに独立していたので、`${RST}` の閉じ忘れは
# その行の中だけで済んでいた。**画面を見れば気付けるが、原因を自分のスクリプトに求めにくい**
# （本体の持ち越しを知らないと「2 行目の色が変」に見える）ので pin する。
setup; seed ""
_raw=$(rawr "$(pay "$FIVE"',"cost":{"total_cost_usd":12.5},"prompt_cache":{"warm":false,"caching_observed":true}')")
_open=""; _n=0
while IFS= read -r _l || [ -n "$_l" ]; do
  _n=$((_n + 1))
  # 行の最後の SGR を取る（無ければ空 = 何も開いていない）
  _last=$(printf '%s' "$_l" | grep -o $'\033\[[0-9;]*m' | tail -1)
  case "$_last" in ""|$'\033[0m'|$'\033[m') ;; *) _open="${_open} Line${_n}=$(printf '%s' "$_last" | cat -v)" ;; esac
done <<EOF_RAW
$_raw
EOF_RAW
check "各行は SGR を閉じて終わる（本体が次の行へ持ち越すので）" \
  "$(all "$([ -z "$_open" ] && echo 1)" "$([ "$_n" -ge 2 ] && echo 1)")" "開いたまま:$_open（$_n 行）"
check "OSC 8 を開いたまま終わらない" \
  "$([ $(( $(printf '%s' "$_raw" | grep -o $'\033\]8;' | grep -c .) % 2 )) = 0 ] && echo 1)" "$(printf '%s' "$_raw" | cat -v)"
check "exit 0 で終わる" "$([ "$(tail -1 "$S")" = 'exit 0' ] && echo 1)" "$(tail -1 "$S")"
# **hot path の外部プロセスは jq 1 + git 1 が床**（`date` / `stat` / `md5` は 0）
setup
# **`^\+ ` では `$( )` の中を見ていない。** コマンド置換は subshell なので `bash -x` は
# `++ date` と深さぶんの `+` を出す。`^\+ ` だけだと**最も本命の経路（v1 は `$(date +%s)` を
# 使っていた）を見逃す**（`x=$(date +%s)` が 0 と数えられることを実測）。`^\++ ` で全深さを見る。
_trace=$(printf '%s' "$(pay)" | env CLAUDE_CONFIG_DIR="$CFG" CLAUDE_STATUSLINE_V2_CACHE_DIR="$CD" \
    CLAUDE_STATUSLINE_NO_NET=1 /bin/bash -x "$S" 2>&1 >/dev/null)
F=$(printf '%s' "$_trace" | grep -cE '^\++ (date|stat|md5|shasum) ')
check "hot path で date / stat / md5 / shasum を呼ばない" "$([ "${F:-0}" = 0 ] && echo 1)" "$F 個"
# **床は jq 1 + git 1。** README・CHANGELOG・commit message が名指ししている不変条件なので数える。
NJ=$(printf '%s' "$_trace" | grep -cE '^\++ jq ')
NG2=$(printf '%s' "$_trace" | grep -cE '^\++ git ')
check "hot path の jq は 1 個" "$([ "${NJ:-0}" = 1 ] && echo 1)" "$NJ 個"
check "hot path の git は 1 個" "$([ "${NG2:-0}" = 1 ] && echo 1)" "$NG2 個"

echo
printf '合計 %s ok / %s NG\n' "$ok" "$ng"
[ "$ng" = 0 ]
