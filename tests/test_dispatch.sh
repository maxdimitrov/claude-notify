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

reset; run notify perm.json >/dev/null; : > "$STUB_LOG"
rc=$(run clear perm.json)
assert_rc0 clear_with_marker_rc "$rc"
assert_log_has clear_args '^clear sess-perm-1 fixture-repo$'
[ ! -f "$MARK/sess-perm-1.pending" ] && ok clear_marker_removed || bad clear_marker_removed "marker still there"

# clear uses env project dir for the root name
reset; run notify perm.json >/dev/null; : > "$STUB_LOG"
CLAUDE_PROJECT_DIR='c:/Users/maxa2/claude'; export CLAUDE_PROJECT_DIR
run clear perm.json >/dev/null
assert_log_has clear_env_root '^clear sess-perm-1 claude$'

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
reset; rc=$(stopfx transcript_origin_task); assert_log_empty stop_task_skipped
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

# --- R6a: unreadable content.sh exits 0 (copy dispatch.sh alone)
mkdir -p "$FIXROOT/lone/scripts"; cp "$DISPATCH" "$FIXROOT/lone/scripts/dispatch.sh"
reset; rc=$(echo '{}' | sh "$FIXROOT/lone/scripts/dispatch.sh" notify; echo $?)
assert_rc0 missing_content_rc "$rc"

rm -rf "$FIXROOT"
if [ "$fails" = 0 ]; then echo "dispatch: PASS"; exit 0; else echo "dispatch: $fails FAILED"; exit 1; fi
