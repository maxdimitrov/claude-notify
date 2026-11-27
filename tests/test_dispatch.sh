#!/bin/sh
# Tests for scripts/dispatch.sh using the stub backend.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/fixlib.sh"
DISPATCH="$here/../scripts/dispatch.sh"
export TMPDIR="$FIXROOT/tmp"; mkdir -p "$TMPDIR"
MARK="$TMPDIR/claude-notify"
export STUB_LOG="$FIXROOT/stub.log"
export CLAUDE_NOTIFY_PLATFORM_DIR="$here/stub"

fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; shift; for l in "$@"; do echo "  $l"; done; fails=$((fails+1)); }
reset() {
  : > "$STUB_LOG"; rm -rf "$MARK"
  unset CLAUDE_PROJECT_DIR CLAUDE_CODE_SESSION_ATTENDED
  CLAUDE_CODE_ENTRYPOINT=claude-vscode; export CLAUDE_CODE_ENTRYPOINT
}
run() { fx "$2" | sh "$DISPATCH" "$1"; echo $? ; }   # prints exit code
log() { cat "$STUB_LOG"; }
assert_log_has() { if log | grep -q -- "$2"; then ok "$1"; else bad "$1" "want [$2] in log:" "$(log)"; fi; }
assert_log_empty() { if [ -z "$(log)" ]; then ok "$1"; else bad "$1" "log not empty:" "$(log)"; fi; }
assert_rc0() { if [ "$2" = 0 ]; then ok "$1"; else bad "$1" "exit code $2"; fi; }

reset; rc=$(run notify perm.json)
assert_rc0 notify_rc "$rc"
assert_log_has notify_event 'event=permission'
assert_log_has notify_called '^notify$'
[ -f "$MARK/sess-perm-1.pending" ] && ok notify_marker || bad notify_marker "no marker in $MARK: $(ls "$MARK" 2>&1)"

reset; rc=$(run notify question.json)
assert_log_has question_event 'event=question'

reset; rc=$(run notify other.json)
assert_rc0 unknown_type_rc "$rc"; assert_log_empty unknown_type_skipped

reset; run notify perm.json >/dev/null; : > "$STUB_LOG"
rc=$(fx stop.json | sed 's/sess-stop-1/sess-perm-1/' | sh "$DISPATCH" stop; echo $?)
assert_rc0 stop_rc "$rc"
assert_log_has stop_event 'event=done'
[ ! -f "$MARK/sess-perm-1.pending" ] && ok stop_marker_removed || bad stop_marker_removed "marker still there"

reset; rc=$(run stop stop_active.json)
assert_rc0 stop_active_rc "$rc"; assert_log_empty stop_active_skipped

reset; CLAUDE_CODE_ENTRYPOINT=sdk-cli; export CLAUDE_CODE_ENTRYPOINT
run notify perm.json >/dev/null; run stop stop.json >/dev/null
assert_log_empty sdk_skipped
ls "$MARK"/*.pending >/dev/null 2>&1 && bad sdk_no_marker "marker created" || ok sdk_no_marker

reset; CLAUDE_CODE_SESSION_ATTENDED=0; export CLAUDE_CODE_SESSION_ATTENDED
run notify perm.json >/dev/null; run stop stop.json >/dev/null
assert_log_empty unattended_skipped

reset; rc=$(run clear perm.json)
assert_rc0 clear_without_marker_rc "$rc"; assert_log_empty clear_without_marker

# clear events: <event> [session] [tool_name] [agent_id] -> dispatch clear
clearev() {
  _ag=; [ -n "$4" ] && _ag=",\"agent_id\":\"$4\""
  printf '{"session_id":"%s","cwd":"%s/fixture-repo","hook_event_name":"%s","tool_name":"%s"%s}' \
    "${2:-sess-perm-1}" "$FIX" "$1" "$3" "$_ag" | sh "$DISPATCH" clear
}
mk() { cat "$MARK/${1:-sess-perm-1}.pending" 2>/dev/null; }
kept() { [ -f "$MARK/${2:-sess-perm-1}.pending" ] && ok "$1" || bad "$1" "marker gone"; }
gone() { [ ! -f "$MARK/${2:-sess-perm-1}.pending" ] && ok "$1" || bad "$1" "marker still there: $(mk "$2")"; }

reset; run notify perm.json >/dev/null; : > "$STUB_LOG"
rc=$(clearev UserPromptSubmit; echo $?)
assert_rc0 clear_with_marker_rc "$rc"
assert_log_has clear_args '^clear sess-perm-1 fixture-repo fixture-repo$'
gone clear_marker_removed

# clear uses env project dir for the root name; rawroot is the uncut leaf
reset; run notify perm.json >/dev/null; : > "$STUB_LOG"
CLAUDE_PROJECT_DIR='c:/Users/maxa2/claude'; export CLAUDE_PROJECT_DIR
clearev UserPromptSubmit
assert_log_has clear_env_root '^clear sess-perm-1 claude claude$'
reset; run notify perm.json >/dev/null; : > "$STUB_LOG"
CLAUDE_PROJECT_DIR='f:/Claude/Projects/repo/.claude/worktrees/wt1'; export CLAUDE_PROJECT_DIR
clearev UserPromptSubmit
assert_log_has clear_worktree_rawroot '^clear sess-perm-1 repo wt1$'

# --- marker contents and selective PostToolUse clear (finding: unrelated tools cleared the toast)
reset; run notify perm.json >/dev/null
[ "$(mk)" = 'toast tool=Bash' ] && ok marker_perm_tool || bad marker_perm_tool "marker: [$(mk)]"
reset; fx perm.json | sed 's/"notification_type"/"agent_id":"ag1","notification_type"/' | sh "$DISPATCH" notify
[ "$(mk)" = 'toast tool=Bash agent=ag1' ] && ok marker_perm_agent || bad marker_perm_agent "marker: [$(mk)]"
reset; run notify question.json >/dev/null
[ "$(mk sess-q-1)" = 'question' ] && ok marker_question || bad marker_question "marker: [$(mk sess-q-1)]"

reset; run notify perm.json >/dev/null; : > "$STUB_LOG"
clearev PostToolUse sess-perm-1 Read
assert_log_empty post_other_tool_no_clear; kept post_other_tool_marker_kept
clearev PostToolUse sess-perm-1 Bash
assert_log_has post_same_tool_clears '^clear sess-perm-1 '; gone post_same_tool_marker_gone

reset; fx perm.json | sed 's/"notification_type"/"agent_id":"ag1","notification_type"/' | sh "$DISPATCH" notify; : > "$STUB_LOG"
clearev PostToolUse sess-perm-1 Bash ag2
assert_log_empty post_other_agent_no_clear; kept post_other_agent_marker_kept
clearev PostToolUse sess-perm-1 Bash
assert_log_empty post_main_thread_no_clear; kept post_main_thread_marker_kept
clearev PostToolUse sess-perm-1 Bash ag1
assert_log_has post_same_agent_clears '^clear sess-perm-1 '; gone post_same_agent_marker_gone

reset; mkdir -p "$MARK"; echo toast > "$MARK/sess-perm-1.pending"
clearev PostToolUse sess-perm-1 Read
assert_log_has post_bare_marker_clears '^clear sess-perm-1 '

reset; run notify perm.json >/dev/null; : > "$STUB_LOG"
clearev PermissionDenied sess-perm-1 Read
assert_log_has denied_clears_toast '^clear sess-perm-1 '; gone denied_marker_gone

reset; run notify question.json >/dev/null; : > "$STUB_LOG"
clearev PostToolUse sess-q-1 Bash
clearev PermissionDenied sess-q-1 Bash
assert_log_empty question_kept_by_other_events; kept question_marker_kept sess-q-1
clearev PostToolUse sess-q-1 AskUserQuestion
assert_log_has question_ask_clears '^clear sess-q-1 '; gone question_ask_marker_gone sess-q-1
reset; run notify question.json >/dev/null; : > "$STUB_LOG"
clearev UserPromptSubmit sess-q-1
assert_log_has question_prompt_clears '^clear sess-q-1 '

# --- record carries entrypoint, rawroot and the marker path (empty for done)
reset; run notify perm.json >/dev/null
assert_log_has record_entrypoint '^entrypoint=claude-vscode$'
assert_log_has record_rawroot '^rawroot=fixture-repo$'
assert_log_has record_marker '^marker=.*sess-perm-1\.pending$'
reset; run stop stop.json >/dev/null
assert_log_has record_done_marker_empty '^marker=$'

# --- cheap clear: no marker at all -> the payload is never parsed (no jq run)
realjq=$(command -v jq)
if [ -n "$realjq" ]; then
  mkdir -p "$FIXROOT/jqspy"; JQLOG="$FIXROOT/jq.log"; export JQLOG REALJQ="$realjq"
  printf '#!/bin/sh\necho JQ >> "$JQLOG"\nexec "$REALJQ" "$@"\n' > "$FIXROOT/jqspy/jq"; chmod +x "$FIXROOT/jqspy/jq"
  reset; : > "$JQLOG"
  fx perm.json | sed 's/"Notification"/"PostToolUse"/' | PATH="$FIXROOT/jqspy:$PATH" sh "$DISPATCH" clear
  [ -s "$JQLOG" ] && bad clear_no_marker_no_jq "jq ran $(wc -l < "$JQLOG") times" || ok clear_no_marker_no_jq
  mkdir -p "$MARK"; echo toast > "$MARK/other-session.pending"; : > "$JQLOG"
  fx perm.json | sed 's/"Notification"/"PostToolUse"/' | PATH="$FIXROOT/jqspy:$PATH" sh "$DISPATCH" clear
  [ -s "$JQLOG" ] && ok clear_other_marker_parses || bad clear_other_marker_parses "jq never ran (spy broken?)"
  assert_log_empty clear_other_session_untouched
else
  echo "SKIP clear_no_marker_no_jq (no jq)"
fi

# env wins in the record too
reset; CLAUDE_PROJECT_DIR='f:/Claude/Projects/quant-atelier'; export CLAUDE_PROJECT_DIR
run notify perm.json >/dev/null
assert_log_has record_env_root '^root=quant-atelier$'

# missing platform backend: silent exit 0
reset; rc=$(fx perm.json | CLAUDE_NOTIFY_PLATFORM_DIR="$FIXROOT/none" sh "$DISPATCH" notify; echo $?)
assert_rc0 missing_backend_rc "$rc"

# garbage input and unknown mode: exit 0
reset; rc=$(echo 'not json' | sh "$DISPATCH" notify; echo $?); assert_rc0 garbage_rc "$rc"
rc=$(echo '{}' | sh "$DISPATCH" bogus; echo $?); assert_rc0 bogus_rc "$rc"

# Cyrillic title reaches the backend intact
reset; run notify cyr.json >/dev/null
assert_log_has cyr_tab "tabtitle=$(cat "$FIX/expected_cyr.txt")"

# --- background-turn filter (stop only)
stopfx() { fx stop.json | sed "s/transcript_titles/$1/" | sh "$DISPATCH" stop; echo $?; }
reset; rc=$(stopfx transcript_origin_peer); assert_rc0 stop_peer_rc "$rc"; assert_log_empty stop_peer_skipped
reset; rc=$(stopfx transcript_origin_task); assert_log_has stop_task_notifies 'event=done'
reset; rc=$(stopfx transcript_bg_pending); assert_rc0 stop_bg_pending_rc "$rc"; assert_log_empty stop_bg_pending_skipped
reset; rc=$(stopfx transcript_bg_partial); assert_log_empty stop_bg_partial_skipped
reset; rc=$(stopfx transcript_bg_done); assert_log_has stop_bg_done_notifies 'event=done'
reset; rc=$(stopfx transcript_bg_quoted); assert_log_has stop_bg_quoted_notifies 'event=done'
reset; rc=$(stopfx transcript_origin_human); assert_log_has stop_human_notifies 'event=done'
reset; rc=$(stopfx transcript_origin_none); assert_log_has stop_noorigin_notifies 'event=done'
reset; fx perm.json | sed 's/transcript_titles/transcript_origin_peer/' | sh "$DISPATCH" notify >/dev/null
assert_log_has notify_ignores_origin 'event=permission'

# --- ping
PH="$FIXROOT/home"; mkdir -p "$PH/.claude/projects/-x"
cp "$FIX/transcript_titles.jsonl" "$PH/.claude/projects/-x/sess-ping-1.jsonl"
pingrun() { HOME="$PH" CLAUDE_CODE_SESSION_ID=sess-ping-1 CLAUDE_PROJECT_DIR=/p/my-repo sh "$DISPATCH" ping "$1" </dev/null; echo $?; }
reset; rc=$(pingrun 'ready to test'); assert_rc0 ping_rc "$rc"
assert_log_has ping_event '^event=ping$'
assert_log_has ping_title '^title=Claude needs you$'
assert_log_has ping_line2 '^line2=ready to test$'
assert_log_has ping_root '^root=my-repo$'
[ -f "$MARK/sess-ping-1.pending" ] && ok ping_marker || bad ping_marker "no marker"
reset; CLAUDE_CODE_ENTRYPOINT=sdk-cli; export CLAUDE_CODE_ENTRYPOINT
rc=$(pingrun x); assert_log_empty ping_sdk_skipped
reset; CLAUDE_CODE_SESSION_ATTENDED=0; export CLAUDE_CODE_SESSION_ATTENDED
rc=$(pingrun x); assert_log_empty ping_unattended_skipped

# --- ping survives its own PostToolUse clear
clearas() { fx perm.json | sed "s/sess-perm-1/${2:-sess-perm-1}/; s/\"Notification\"/\"$1\"/" | sh "$DISPATCH" clear; }
reset; pingrun x >/dev/null; : > "$STUB_LOG"; clearas PostToolUse sess-ping-1
assert_log_empty ping_post_tool_no_clear
[ -f "$MARK/sess-ping-1.pending" ] && ok ping_post_tool_marker_kept || bad ping_post_tool_marker_kept "marker gone"
reset; pingrun x >/dev/null; : > "$STUB_LOG"
fx perm.json | sed 's/sess-perm-1/sess-ping-1/; s/"Notification"/"UserPromptSubmit"/' | sh "$DISPATCH" clear
assert_log_has ping_prompt_clears '^clear sess-ping-1 '
[ ! -f "$MARK/sess-ping-1.pending" ] && ok ping_prompt_marker_gone || bad ping_prompt_marker_gone "marker still there"
reset; run notify perm.json >/dev/null; : > "$STUB_LOG"; clearev PostToolUse sess-perm-1 Bash
assert_log_has perm_post_tool_clears '^clear sess-perm-1 '

# --- the turn's own done after a ping: no second notification, ping marker kept
reset; pingrun x >/dev/null; : > "$STUB_LOG"
fx stop.json | sed 's/sess-stop-1/sess-ping-1/' | sh "$DISPATCH" stop
assert_log_empty stop_after_ping_silent
[ "$(mk sess-ping-1)" = ping ] && ok stop_after_ping_marker_kept || bad stop_after_ping_marker_kept "marker: [$(mk sess-ping-1)]"
reset; run notify perm.json >/dev/null; : > "$STUB_LOG"
fx stop.json | sed 's/sess-stop-1/sess-perm-1/' | sh "$DISPATCH" stop
assert_log_has stop_after_toast_notifies 'event=done'

# --- ping record: marker path in the record
reset; pingrun x >/dev/null
assert_log_has ping_record_marker '^marker=.*sess-ping-1\.pending$'

# --- R6a: unreadable content.sh exits 0 (copy dispatch.sh alone)
mkdir -p "$FIXROOT/lone/scripts"; cp "$DISPATCH" "$FIXROOT/lone/scripts/dispatch.sh"
reset; rc=$(echo '{}' | sh "$FIXROOT/lone/scripts/dispatch.sh" notify; echo $?)
assert_rc0 missing_content_rc "$rc"

rm -rf "$FIXROOT"
if [ "$fails" = 0 ]; then echo "dispatch: PASS"; exit 0; else echo "dispatch: $fails FAILED"; exit 1; fi
