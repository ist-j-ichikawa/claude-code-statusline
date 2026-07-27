#!/bin/bash
# install.sh — このリポジトリの statusline を ~/.claude/settings.json に登録する。
# 既定は「差分を見せて y/N 確認」。既存設定は保ったままマージし、書き換え前にタイムスタンプ付き
# バックアップを取る (上書きしない)。詳細は README の Installation 参照。
set -euo pipefail

main_only=0 assume_yes=0 dry_run=0
for a in "$@"; do
  case "$a" in
    --main-only) main_only=1 ;;
    -y|--yes)    assume_yes=1 ;;
    -n|--dry-run) dry_run=1 ;;
    -h|--help)
      cat <<'USAGE'
usage: ./install.sh [--dry-run] [--yes] [--main-only]

  ~/.claude/settings.json に statusLine (と subagentStatusLine) を登録します。
  既定では変更内容を差分で表示して確認を求めます。スクリプトは clone したこの場所を
  絶対パスで参照するので、更新は git pull だけで反映されます。

  -n, --dry-run  変更内容を表示するだけで書き込まない
  -y, --yes      確認プロンプトを省略する (非対話環境ではこれが必須)
      --main-only  メインの statusLine だけ登録し、サブエージェント行は Claude Code 既定のままにする

  CLAUDE_SETTINGS=<path>  書き込み先の settings.json を差し替える (既定: ~/.claude/settings.json)
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
repo=$(cd "$_selfdir" && pwd)   # ~ 展開されない環境でも効くよう絶対パスに解決

# settings.json の command 文字列にパスを埋めるので、空白入りパスは引用できず壊れる。
# 試走は通ってしまい「入れたのに真っ白」になるため、書く前に断る。
case "$repo" in
  *[[:space:]]*)
    printf 'clone 先のパスに空白が含まれています:\n  %s\n' "$repo" >&2
    printf '設定値の分割で壊れるため登録できません。空白を含まないパスに clone し直してください。\n' >&2
    exit 1 ;;
esac

scripts=(statusline-command.sh lib.sh)
[[ $main_only -eq 1 ]] || scripts+=(subagent-statusline-command.sh)
for f in "${scripts[@]}"; do
  [[ -f "$repo/$f" ]] || { printf '%s が %s に見つかりません\n' "$f" "$repo" >&2; exit 1; }
done

settings="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
_dir="${settings%/*}"; [[ "$_dir" == "$settings" ]] && _dir="."   # スラッシュ無しなら cwd
mkdir -p "$_dir"
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
# 空ファイル (中断した編集の残骸等) も未初期化として扱う — 「不正な JSON」で突き返さない
[[ -s "$settings" ]] || echo '{}' > "$settings"
jq -e . "$settings" >/dev/null 2>&1 || { echo "$settings が不正な JSON です。先に直してください" >&2; exit 1; }

# 登録するスクリプトを先に試走する (壊れたものを global 設定に書かない)。
# CLAUDE_STATUSLINE_NO_NET=1 — インストールが OAuth 通信 / Keychain 読み / 共有キャッシュ書き込みを
# 副作用として起こさないため (test.bats と同じ seam)。exit 0 だけでなく出力があることも見る。
_probe() {
  local out
  out=$(printf '%s' "$2" | CLAUDE_STATUSLINE_NO_NET=1 /bin/bash "$repo/$1" 2>/dev/null) || return 1
  [[ -n "$out" ]]
}
_probe statusline-command.sh \
  '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"version":"0","workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":1}}' \
  || { printf 'statusline-command.sh が正常に動きませんでした (%s)\n' "$repo" >&2; exit 1; }
[[ $main_only -eq 1 ]] || _probe subagent-statusline-command.sh \
  '{"columns":80,"tasks":[{"id":"p","label":"probe","model":"claude-opus-5"}]}' \
  || { printf 'subagent-statusline-command.sh が正常に動きませんでした (%s)\n' "$repo" >&2; exit 1; }

# 既存の statusLine の他キー (padding 等) と、ユーザーが決めた refreshInterval /
# hideVimModeIndicator は保つ (//= なので未設定時だけ既定値を入れる)。
filter='
  .statusLine = ((.statusLine // {}) + {type: "command", command: $main})
  | .statusLine.refreshInterval //= 30
  | .statusLine.hideVimModeIndicator //= true
'
[[ $main_only -eq 1 ]] || filter+='
  | .subagentStatusLine = ((.subagentStatusLine // {}) + {type: "command", command: $sub})
'

_new=$(jq --arg main "/bin/bash $repo/statusline-command.sh" \
          --arg sub  "/bin/bash $repo/subagent-statusline-command.sh" \
          "$filter" "$settings")

_keys='{statusLine, subagentStatusLine} | with_entries(select(.value != null))'
_before=$(jq -S "$_keys" "$settings")
_after=$(printf '%s' "$_new" | jq -S "$_keys")

if [[ "$_before" == "$_after" ]]; then
  printf '既に登録済みです (変更なし): %s\n' "$settings"
  exit 0
fi

printf '書き込み先: %s\n\n変更内容:\n' "$settings"
diff -u --label 'current' --label 'after' \
  <(printf '%s\n' "$_before") <(printf '%s\n' "$_after") || true

# 他ツールの statusLine を奪う場合は明示的に警告する (無警告で奪わない)
_cur_cmd=$(printf '%s' "$_before" | jq -r '.statusLine.command // ""')
if [[ -n "$_cur_cmd" && "$_cur_cmd" != *"$repo"* ]]; then
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

printf '登録しました: %s\nバックアップ: %s\n次回 Claude Code 起動時 (または /doctor) から反映されます。\n' "$settings" "$_bak"
