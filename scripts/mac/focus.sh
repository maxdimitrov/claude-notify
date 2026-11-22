#!/bin/sh
# claude-notify click handler (macOS). Usage: focus.sh <projectdir> <session> [<entrypoint>] [<rawroot>]
# Focus the project's VS Code window, then (VS Code sessions only) reveal the Claude session tab.
here=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || exit 0
. "$here/lib.sh" 2>/dev/null || exit 0

projectdir=$1; session=$2; entrypoint=$3; rawroot=$4
root=$(basename "$projectdir" 2>/dev/null)
[ -n "$root" ] || { cn_log "focus: no projectdir"; exit 0; }

codebin=
if command -v code >/dev/null 2>&1; then codebin=code
elif [ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]; then
  codebin="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
fi
if [ -n "$codebin" ]; then "$codebin" "$projectdir" >/dev/null 2>&1; else cn_log "focus: no code CLI"; fi

# Terminal / other sessions: the reveal link would open a duplicate of the session in VS Code.
if [ "$entrypoint" != claude-vscode ]; then
  cn_log "focus: no reveal: entrypoint=$entrypoint"
  exit 0
fi
sleep "${CLAUDE_NOTIFY_FOCUS_DELAY:-1}"

reveal() {
  case "$session" in
    ????????-????-????-????-????????????)
      case "$session" in *[!0-9a-fA-F-]*) cn_log "focus: invalid session id; no reveal"; return ;; esac
      open "vscode://anthropic.claude-code/open?session=$session" >/dev/null 2>&1
      cn_log "focus: revealed session $session ($1)" ;;
    *) cn_log "focus: invalid session id; no reveal" ;;
  esac
}

if _out=$(osascript -e 'tell application "System Events" to tell (first process whose frontmost is true) to return (name & "|" & (name of front window))' 2>/dev/null); then
  _app=${_out%%|*}; name=${_out#*|}
  case "$_app" in
    Code*|Electron)
      if cn_has_any_seg "$name" "$root" || { [ -n "$rawroot" ] && cn_has_any_seg "$name" "$rawroot"; }; then
        reveal guarded
      else
        cn_log "focus: skipped (front window '$name' is not '$root')"
      fi ;;
    *) cn_log "focus: skipped (frontmost app '$_app' is not VS Code)" ;;
  esac
else
  reveal unguarded
fi
exit 0
