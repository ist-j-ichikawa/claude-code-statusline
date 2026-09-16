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
  '{"effort":"high"}' '{"model":5}' '{"cost":{"total_cost_usd":null}}'
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
  "$(all "$(has 'Fable:' "$O")" "$(has 'Max 20x' "$O")")" "$O"
check "未知キーで stderr が出ない" "$([ ! -s "$ERR" ] && echo 1)" "$(cat "$ERR")"

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
    CLAUDE_STATUSLINE_V2_CACHE_DIR="$d" /bin/bash "$S" >/dev/null 2>&1
  sleep 1; ls "$d" 2>/dev/null | head -1
}
_a=$(_cn /tmp/cfgX /tmp/ssA); _b=$(_cn /tmp/cfgX /tmp/ssB)
check "securestorage を分けたらキャッシュも分かれる" \
  "$([ -n "$_a" ] && [ "$_a" != "$_b" ] && echo 1)" "A=$_a B=$_b"
# **既定ではファイル名を変えない**（変えると全ユーザーが一斉に取り直す = 429 事故と同じ負荷）
_d1=$(mkd)
printf '%s' "$(pay)" | env CLAUDE_STATUSLINE_V2_CACHE_DIR="$_d1" /bin/bash "$S" >/dev/null 2>&1
sleep 1
check "securestorage 未設定ならキャッシュ名に接尾辞を付けない" \
  "$(no '__' "$(ls "$_d1" 2>/dev/null | head -1)")" "$(ls "$_d1" 2>/dev/null | head -1)"

echo "── 時刻: timeZone と timeFormat ──"
t_time() {  # t_time NAME SETTINGS EXPECT
  setup "$2"
  local L; L=$(render "$(pay "$FIVE")" 3)
  check "$1" "$(has "$3" "$L")" "$L"
  check "$1 — stderr 空" "$([ ! -s "$ERR" ] && echo 1)" "$(cat "$ERR")"
}
t_time "timeZone: UTC"              '{"timeZone":"UTC"}'                    '10:30'
t_time "timeZone: America/New_York" '{"timeZone":"America/New_York"}'        '06:30'
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
check "caching_observed:true なら cold と原因を出す" \
  "$(all "$(has 'cold ttl_expired_5m' "$O")" "$(no 'jq error' "$O")")" "$O"
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
  PATH="$SPY:$PATH" SPYLOG="$SPY/argv" SPYSTDIN="$SPY/stdin" /bin/bash "$S" >/dev/null 2>&1
sleep 2
check "トークンが curl の argv に出ない" \
  "$(if [ ! -f "$SPY/argv" ] || ! grep -q 'SECRET-TOKEN' "$SPY/argv"; then echo 1; fi)" \
  "$(cat "$SPY/argv" 2>/dev/null)"
check "トークンは stdin で渡る（-H @-）" \
  "$([ -s "$SPY/stdin" ] && grep -q 'SECRET-TOKEN' "$SPY/stdin" && echo 1)" \
  "stdin: $(head -c 60 "$SPY/stdin" 2>/dev/null)"
check "curl の argv に --config が無い（設定ディレクティブ注入の経路）" \
  "$(if [ ! -f "$SPY/argv" ] || ! grep -q -- '--config' "$SPY/argv"; then echo 1; fi)" \
  "$(cat "$SPY/argv" 2>/dev/null)"
# **`mkdir -p -m 700` が実際に走る経路で見る。** `mktemp -d` は最初から 0700 なので、
# それを stat するだけでは**この行を `mkdir -p` に書き換えても緑のまま**（mutation で実証）。
# **まだ存在しないディレクトリ**を CACHE_BASE に指定して、スクリプトに作らせてから見る。
_cb="$(mkd)/sub"
printf '%s' "$(pay)" | env CLAUDE_CONFIG_DIR="$CFG" CLAUDE_STATUSLINE_V2_CACHE_DIR="$_cb" \
  /bin/bash "$S" >/dev/null 2>&1
sleep 1
check "スクリプトが作るキャッシュディレクトリは 700" \
  "$([ -d "$_cb" ] && [ "$(stat -f '%Sp' "$_cb")" = "drwx------" ] && echo 1)" \
  "$([ -d "$_cb" ] && stat -f '%Sp' "$_cb" || echo '作られなかった')"
# **Keychain のサービス名は config dir ごとに変わる**（決め打ちで引くと別アカウントの blob を読む）
check "Keychain のサービス名に config dir の sha256 先頭 8 桁を付ける" \
  "$(grep -q 'shasum -a 256' "$S" && grep -q 'Claude Code-credentials' "$S" && echo 1)" ""
check "credentials ファイルは securestorage 側から読む" \
  "$(grep -q 'SECURESTORAGE_DIR}/.credentials.json' "$S" && echo 1)" ""

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
