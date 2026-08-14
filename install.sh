#!/bin/bash
# install.sh — このリポジトリの statusline を settings.json に登録する。
# 既定は「差分を見せて y/N 確認」。既存設定は保ったままマージし、書き換え前にタイムスタンプ付き
# バックアップを取る (上書きしない)。詳細は README の Installation 参照。
set -euo pipefail

main_only=0 assume_yes=0 dry_run=0 uninstall=0
for a in "$@"; do
  case "$a" in
    --main-only) main_only=1 ;;
    --uninstall) uninstall=1 ;;
    -y|--yes)    assume_yes=1 ;;
    -n|--dry-run) dry_run=1 ;;
    -h|--help)
      cat <<'USAGE'
usage: ./install.sh [--dry-run] [--yes] [--main-only] [--uninstall]

  settings.json に statusLine (と subagentStatusLine) を登録します
  (既定: ${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json)。
  既定では変更内容を差分で表示して確認を求めます。スクリプトは clone したこの場所を
  絶対パスで参照するので、更新は git pull だけで反映されます。

  -n, --dry-run  変更内容を表示するだけで書き込まない
  -y, --yes      確認プロンプトを省略する (非対話環境ではこれが必須)
      --main-only  メインの statusLine だけ登録し、サブエージェント行は Claude Code 既定のままにする
      --uninstall  statusLine / subagentStatusLine の登録を外す (他のキーは触らない)

  CLAUDE_SETTINGS=<path>  書き込み先の settings.json を差し替える
USAGE
      exit 0 ;;
    *) printf 'unknown option: %s (--help を参照)\n' "$a" >&2; exit 2 ;;
  esac
done

[[ "$(uname -s)" == Darwin ]] || {
  printf 'この statusline は macOS 専用です (stat -f / md5 -q -s に依存)。検出: %s\n' "$(uname -s)" >&2
  exit 1; }
command -v jq >/dev/null || { echo "jq が必要です: brew install jq" >&2; exit 1; }

# PATH に置かれた形 (スラッシュ無し) でも解決できるよう "." に fallback (姉妹スクリプトと同じ作法)
_selfdir="${BASH_SOURCE%/*}"; [[ "$_selfdir" == "$BASH_SOURCE" ]] && _selfdir="."
# $BASH_SOURCE は相対のことがある (./install.sh) ので、cwd に依存しない値を書けるよう絶対化する
repo=$(cd "$_selfdir" && pwd)

if [[ $uninstall -eq 0 ]]; then
scripts=(statusline-command.sh lib.sh)
[[ $main_only -eq 1 ]] || scripts+=(subagent-statusline-command.sh)
for f in "${scripts[@]}"; do
  [[ -f "$repo/$f" ]] || { printf '%s が %s に見つかりません\n' "$f" "$repo" >&2; exit 1; }
done
fi

# **`CLAUDE_SETTINGS` が外側の既定であること**が壊しうる不変条件 (入れ替えると明示指定を無視する)。
# `CLAUDE_CONFIG_DIR` を尊重する理由は docs/internals.md の「宛名」節。
settings="${CLAUDE_SETTINGS:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json}"
_dir="${settings%/*}"; [[ "$_dir" == "$settings" ]] && _dir="."   # スラッシュ無しなら cwd
# `mkdir -p "$_dir"` はここでは**やらない** — --dry-run が書き込まない保証を壊す。
# 書き込む直前 (dry-run の bail より後) で作る。
# symlink 越しなら実体に書く (dotfiles 管理で settings.json が symlink のことがある。
# リンクに mv すると実体との繋がりが切れて「設定したのに反映されない」になる)
_hops=0
while [[ -L "$settings" ]]; do
  _link=$(readlink "$settings")
  case "$_link" in
    /*) settings="$_link" ;;
    *)  _dir="${settings%/*}"; [[ "$_dir" == "$settings" ]] && _dir="."
        settings="$_dir/$_link" ;;
  esac
  _hops=$((_hops + 1)); (( _hops < 10 )) || { echo "symlink が深すぎます: $settings" >&2; exit 1; }
done
# 空ファイル (中断した編集の残骸等) も未初期化として扱う — 「不正な JSON」で突き返さない。
# 以降は中身を `$_cur_json` に持って回す — 未初期化のときの `{}` を
# **--dry-run では変数に持つだけでファイルを作らない**ため。以前はここで実ファイルを作っており、
# 「差分を見せるまで一切書かない」という install.sh の約束を --dry-run 自身が破っていた。
# 実書き込みの経路は後段の `cp -p` / `stat` が実ファイルを要求するので、そちらでは作る。
if [[ -s "$settings" ]]; then
  _cur_json=$(<"$settings")
elif [[ $dry_run -eq 1 ]]; then
  _cur_json='{}'
else
  _dir="${settings%/*}"; [[ "$_dir" == "$settings" ]] && _dir="."
  mkdir -p "$_dir"
  echo '{}' > "$settings"
  _cur_json='{}'
fi
jq -e . <<<"$_cur_json" >/dev/null 2>&1 || { echo "$settings が不正な JSON です。先に直してください" >&2; exit 1; }

# 登録するスクリプトを先に試走する (壊れたものを global 設定に書かない)。
# 2 つの seam で副作用を止める (test.bats と同じもの):
#   CLAUDE_STATUSLINE_NO_NET=1        — OAuth 通信と Keychain 読みを止める
#   CLAUDE_STATUSLINE_CACHE_DIR=<tmp> — git キャッシュの書き込み先を捨てる先へ逃がす。
#     NO_NET は git キャッシュには効かないので、これが無いと試走がユーザーの
#     $TMPDIR/claude-statusline-<uid>/git/ に本物のエントリを作ってしまう。
# exit 0 だけでなく出力があることも見る。
_probe() {
  local out
  out=$(printf '%s' "$2" | CLAUDE_STATUSLINE_NO_NET=1 CLAUDE_STATUSLINE_CACHE_DIR="$_probe_cache" \
        /bin/bash "$repo/$1" 2>/dev/null) || return 1
  [[ -n "$out" ]]
}
# mktemp と trap は試走する時だけ — `--uninstall` は probe を 1 度も呼ばないので、
# ここに置かないと「clone を消した後の掃除」経路が無駄に fork する
if [[ $uninstall -eq 0 ]]; then
_probe_cache=$(mktemp -d)
trap 'rm -rf "$_probe_cache"' EXIT
_probe statusline-command.sh \
  '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"version":"0","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":1}}' \
  || { printf 'statusline-command.sh が正常に動きませんでした (%s)\n' "$repo" >&2; exit 1; }
[[ $main_only -eq 1 ]] || _probe subagent-statusline-command.sh \
  '{"columns":80,"tasks":[{"id":"p","label":"probe","model":"claude-opus-5"}]}' \
  || { printf 'subagent-statusline-command.sh が正常に動きませんでした (%s)\n' "$repo" >&2; exit 1; }
fi

# 既存の statusLine の他キー (padding 等) と、ユーザーが決めた refreshInterval /
# hideVimModeIndicator は保つ (//= なので未設定時だけ既定値を入れる)。
if [[ $uninstall -eq 1 ]]; then
  # 2 キーだけ落とす。他のキーには触らないので個人設定は残る
  filter='del(.statusLine) | del(.subagentStatusLine)'
else
  filter='
    .statusLine = ((.statusLine // {}) + {type: "command", command: $main})
    | .statusLine.refreshInterval //= 30
    | .statusLine.hideVimModeIndicator //= true
  '
  [[ $main_only -eq 1 ]] || filter+='
    | .subagentStatusLine = ((.subagentStatusLine // {}) + {type: "command", command: $sub})
  '
fi

# settings.json の `command` はシェル経由で実行される (docs: "The `command` field runs in a shell")
# ので、埋めるパスは**シェル用に引用してから**入れる。`printf %q` は空白・`(`・`'`・glob 文字
# (`{} * ? []`) すべてを安全にするので、拒否リストは持たない。
# 以前は空白だけを弾いていたが、(a) `~/Documents/Projects (old)/` のような**正当なパスを拒否**し、
# (b) `{a,b}` の brace 展開や `*` の glob は素通りして「試走は通るのに登録すると真っ白」になっていた
# — 拒否リストを足し続けるのではなく、引用して発生条件そのものを消す方針。
# `printf -v` で fork を作らない (このリポの作法)。
printf -v _qmain '%q' "$repo/statusline-command.sh"
printf -v _qsub  '%q' "$repo/subagent-statusline-command.sh"
_new=$(jq --arg main "/bin/bash $_qmain" \
          --arg sub  "/bin/bash $_qsub" \
          "$filter" <<<"$_cur_json")

_keys='{statusLine, subagentStatusLine} | with_entries(select(.value != null))'
_before=$(jq -S "$_keys" <<<"$_cur_json")
_after=$(printf '%s' "$_new" | jq -S "$_keys")

if [[ "$_before" == "$_after" ]]; then
  if [[ $uninstall -eq 1 ]]; then
    printf '登録されていません (変更なし): %s\n' "$settings"
  else
    printf '既に登録済みです (変更なし): %s\n' "$settings"
  fi
  exit 0
fi

printf '書き込み先: %s\n\n変更内容:\n' "$settings"
diff -u --label 'current' --label 'after' \
  <(printf '%s\n' "$_before") <(printf '%s\n' "$_after") || true

# 他ツールの statusLine を奪う場合は明示的に警告する (無警告で奪わない)。
# 判定は**スクリプト名**で行う — パスで突き合わせると自分の登録を「別のツール」と誤警告する:
# ① README の主経路は `~/.claude/statusline/...` を手で貼る形なので `$repo` と文字列一致しない
# ② `printf %q` の引用が入ると `my\ repo` のように `$repo` と字面が変わる
# ③ clone を移動・改名しても以前の登録は自分のもの
# 同名スクリプトを持つ別ツールは警告できなくなるが、差分は必ず表示するので無断では奪わない。
_cur_cmd=$(printf '%s' "$_before" | jq -r '.statusLine.command // ""')
if [[ -n "$_cur_cmd" && "${_cur_cmd##*/}" != "statusline-command.sh" ]]; then
  printf '\n注意: 既存の statusLine が別のコマンドを指しています:\n  %s\nこれを上書きします。残したい場合は中止して手動で設定してください。\n' "$_cur_cmd"
fi

if [[ $dry_run -eq 1 ]]; then
  printf '\n--dry-run なので書き込みませんでした。\n'
  exit 0
fi

if [[ $assume_yes -eq 0 ]]; then
  [[ -t 0 ]] || { printf '\n非対話環境です。内容を確認して --yes を付けて実行してください。\n' >&2; exit 1; }
  printf '\n続行しますか? [y/N] '
  read -r _ans || _ans=n     # Ctrl-D は set -e で即死させず中止扱いにする
  case "$_ans" in [yY]|[yY][eE][sS]) ;; *) echo "中止しました。"; exit 1 ;; esac
fi

# バックアップは毎回別名 (既存の .bak を潰すと「2 回叩いたら元の設定が消える」事故になる)
_bak="$settings.bak.$(date +%Y%m%d%H%M%S)"
[[ -e "$_bak" ]] && _bak="$_bak.$$"
cp -p "$settings" "$_bak"
# 元のパーミッションを引き継ぐ (settings.json は env の API キー等を持ちうる。
# 新規 tmp を mv すると 600 で固めていたファイルが umask の 644 に緩む)
_tmp="$settings.tmp.$$"
: > "$_tmp"
chmod "$(stat -f '%Lp' "$settings")" "$_tmp"
printf '%s\n' "$_new" > "$_tmp" && mv "$_tmp" "$settings"

if [[ $uninstall -eq 1 ]]; then
  printf '登録を外しました: %s\nバックアップ: %s\n次回 Claude Code 起動時から標準のステータスラインに戻ります。\n' "$settings" "$_bak"
else
  printf '登録しました: %s\nバックアップ: %s\n次回 Claude Code 起動時 (または /doctor) から反映されます。\n' "$settings" "$_bak"
fi
