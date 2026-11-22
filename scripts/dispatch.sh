#!/bin/sh
# claude-notify dispatcher. Usage: dispatch.sh notify|stop|clear (hook JSON on stdin) | ping "<message>" (env only).
# Guards, builds the record, keeps a pending marker per session, calls the platform
# backend. Always exits 0: a broken notifier must never affect a session.

here=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || exit 0
[ -r "$here/lib/content.sh" ] || exit 0
. "$here/lib/content.sh" 2>/dev/null || exit 0

mode=$1
payload=; [ "$mode" = ping ] || payload=$(cat)

# Headless / helper sessions stay silent.
case "${CLAUDE_CODE_ENTRYPOINT:-}" in sdk*) exit 0 ;; esac
[ "${CLAUDE_CODE_SESSION_ATTENDED:-}" = 0 ] && exit 0

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) platform=windows ;;
  Darwin) platform=mac ;;
  *) platform=linux ;;
esac
dir=${CLAUDE_NOTIFY_PLATFORM_DIR:-$here/$platform}

mdir="${TMPDIR:-${TEMP:-/tmp}}/claude-notify"
if [ "$mode" = ping ]; then session=${CLAUDE_CODE_SESSION_ID:-}; else session=$(cn_field "$payload" session_id); fi
[ -n "$session" ] || session=unknown
safe=$(printf '%s' "$session" | tr -c 'A-Za-z0-9_-' '_')
marker="$mdir/$safe.pending"

case "$mode" in
  notify)
    case "$(cn_field "$payload" notification_type)" in
      permission_prompt) event=permission ;;
      elicitation_dialog) event=question ;;
      *) exit 0 ;;
    esac
    ;;
  stop)
    [ "$(cn_field "$payload" stop_hook_active)" = true ] && exit 0
    case "$(cn_turn_origin "$(cn_field "$payload" transcript_path)")" in ""|human) ;; *) exit 0 ;; esac
    event=done
    ;;
  ping) event=ping ;;
  clear)
    [ -f "$marker" ] || exit 0
    if [ "$(cat "$marker" 2>/dev/null)" = ping ] && [ "$(cn_field "$payload" hook_event_name)" != UserPromptSubmit ]; then exit 0; fi
    rm -f "$marker" 2>/dev/null
    [ -f "$dir/clear" ] || exit 0
    name=$(cn_repo_name "$(cn_repo_root "$(cn_project_dir "$payload")")")
    sh "$dir/clear" "$session" "$name" >/dev/null 2>&1
    exit 0
    ;;
  *) exit 0 ;;
esac

if [ "$event" = ping ]; then record=$(cn_build_ping "$2"); else record=$(cn_build_record "$event" "$payload"); fi

if [ "$event" = done ]; then
  rm -f "$marker" 2>/dev/null
else
  _cn_mk=toast; [ "$event" = ping ] && _cn_mk=ping
  mkdir -p "$mdir" 2>/dev/null && echo "$_cn_mk" > "$marker" 2>/dev/null
fi

[ -f "$dir/notify" ] || exit 0
printf '%s\n' "$record" | sh "$dir/notify" >/dev/null 2>&1
exit 0
