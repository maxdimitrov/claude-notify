#!/bin/sh
# claude-notify click handler (macOS). Usage: focus.sh <projectdir> <session>
# Focus the project's VS Code window, then reveal the Claude session tab.
here=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || exit 0
. "$here/lib.sh" 2>/dev/null || exit 0

projectdir=$1; session=$2
root=$(basename "$projectdir" 2>/dev/null)
[ -n "$root" ] || { cn_log "focus: no projectdir"; exit 0; }

codebin=
if command -v code >/dev/null 2>&1; then codebin=code
elif [ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]; then
  codebin="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
fi
if [ -n "$codebin" ]; then "$codebin" "$projectdir" >/dev/null 2>&1; else cn_log "focus: no code CLI"; fi
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

if name=$(osascript -e 'tell application "System Events" to get name of front window of (first process whose frontmost is true)' 2>/dev/null); then
  if cn_has_any_seg "$name" "$root"; then
    reveal guarded
  else
    cn_log "focus: skipped (front window '$name' is not '$root')"
  fi
else
  cn_log "focus: unguarded (osascript error, no Accessibility?) root=$root"
  reveal unguarded
fi
exit 0
