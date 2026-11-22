#!/bin/sh
# claude-notify dispatcher. Usage: dispatch.sh notify|stop|clear (hook JSON on stdin) | ping "<message>" (env only).
# Guards, builds the record, keeps a pending marker per session, calls the platform
# backend. Always exits 0: a broken notifier must never affect a session.
# Backend contract: <platform dir>/notify reads the record (scripts/lib/content.sh) on stdin;
# <platform dir>/clear <session> <root> <rawroot> takes the session's toast down.

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

# Clear fires on every tool call: with no marker at all, stop before parsing the payload.
if [ "$mode" = clear ]; then
  set -- "$mdir"/*.pending
  [ -e "$1" ] || exit 0
fi

if [ "$mode" = ping ]; then session=${CLAUDE_CODE_SESSION_ID:-}; else session=$(cn_field "$payload" session_id); fi
[ -n "$session" ] || session=unknown
safe=$(printf '%s' "$session" | tr -c 'A-Za-z0-9_-' '_')
marker="$mdir/$safe.pending"

case "$mode" in
  notify)
    case "$(cn_field "$payload" notification_type)" in
      permission_prompt)
        event=permission; mk=toast
        _tool=$(cn_token "$(cn_perm_tool "$(cn_field "$payload" message)")")
        [ -n "$_tool" ] && mk="$mk tool=$_tool" ;;
      elicitation_dialog) event=question; mk=question ;;
      *) exit 0 ;;
    esac
    _agent=$(cn_token "$(cn_field "$payload" agent_id)")
    [ -n "$_agent" ] && mk="$mk agent=$_agent"
    ;;
  stop)
    [ "$(cn_field "$payload" stop_hook_active)" = true ] && exit 0
    # A deliberate ping is up: it already told the user; keep it (and its marker).
    case "$(cat "$marker" 2>/dev/null)" in ping|"ping "*) exit 0 ;; esac
    case "$(cn_turn_origin "$(cn_field "$payload" transcript_path)")" in ""|human) ;; *) exit 0 ;; esac
    event=done
    ;;
  ping) event=ping; mk=ping ;;
  clear)
    [ -f "$marker" ] || exit 0
    cn_should_clear "$(cat "$marker" 2>/dev/null)" "$(cn_field "$payload" hook_event_name)" \
      "$(cn_token "$(cn_field "$payload" tool_name)")" "$(cn_token "$(cn_field "$payload" agent_id)")" || exit 0
    rm -f "$marker" 2>/dev/null
    [ -f "$dir/clear" ] || exit 0
    _pd=$(cn_project_dir "$payload")
    sh "$dir/clear" "$session" "$(cn_repo_name "$(cn_repo_root "$_pd")")" "$(cn_repo_name "$_pd")" >/dev/null 2>&1
    exit 0
    ;;
  *) exit 0 ;;
esac

# Marker path for the record, native on Windows (Notify.ps1 checks it after showing the toast).
recmarker=
if [ "$event" != done ]; then
  recmarker=$marker
  if [ "$platform" = windows ] && command -v cygpath >/dev/null 2>&1; then
    recmarker=$(cygpath -w "$marker" 2>/dev/null)
  fi
fi

if [ "$event" = ping ]; then record=$(cn_build_ping "$2" "$recmarker"); else record=$(cn_build_record "$event" "$payload" "$recmarker"); fi

if [ "$event" = done ]; then
  rm -f "$marker" 2>/dev/null
else
  mkdir -p "$mdir" 2>/dev/null && echo "$mk" > "$marker" 2>/dev/null
fi

[ -f "$dir/notify" ] || exit 0
printf '%s\n' "$record" | sh "$dir/notify" >/dev/null 2>&1
exit 0
