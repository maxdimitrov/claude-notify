#!/bin/sh
# Tests for scripts/mac/* using PATH stubs (terminal-notifier, osascript, afplay, code, open).
here=$(cd "$(dirname "$0")" && pwd)
MAC="$here/../scripts/mac"
T="${TMPDIR:-${TEMP:-/tmp}}"
if command -v cygpath >/dev/null 2>&1; then T=$(cygpath -u "$T"); fi
W="$T/cn-mac-$$"; mkdir -p "$W/bin"
export TMPDIR="$W/tmp"; mkdir -p "$TMPDIR"
export LOG="$W/calls.log"
export CLAUDE_NOTIFY_FOCUS_DELAY=0
EM=$(printf '\342\200\224')

# Stubs: log argv, one "ARG <value>" line per argument.
mkstub() {
  cat > "$W/bin/$1" <<STUB
#!/bin/sh
printf 'CALL $1\n' >> "\$LOG"
for a in "\$@"; do printf 'ARG %s\n' "\$a" >> "\$LOG"; done
$2
STUB
  chmod +x "$W/bin/$1"
}
mkstub terminal-notifier ':'
mkstub afplay ':'
mkstub code ':'
mkstub open ':'
# osascript: System Events reads follow OSA_MODE/OSA_OUT; display notification always succeeds.
mkstub osascript 'case "$*" in *"System Events"*) [ "${OSA_MODE:-fail}" = ok ] && { printf "%s\n" "$OSA_OUT"; exit 0; }; exit 1 ;; esac; exit 0'
# PATH without the stubs' real counterparts is not needed: stubs shadow; "no terminal-notifier"
# is simulated by a second bin dir without it.
mkdir -p "$W/bin2"; for s in afplay code open osascript; do cp "$W/bin/$s" "$W/bin2/$s"; done
BASEPATH=$PATH

fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; shift; for l in "$@"; do echo "  $l"; done; fails=$((fails+1)); }
reset() { : > "$LOG"; rm -rf "$TMPDIR/claude-notify"; unset OSA_MODE OSA_OUT; }
has() { if grep -qxF -- "$2" "$LOG"; then ok "$1"; else bad "$1" "want [$2] in:" "$(cat "$LOG")"; fi; }
hasnt() { if grep -qxF -- "$2" "$LOG"; then bad "$1" "unexpected [$2] in:" "$(cat "$LOG")"; else ok "$1"; fi; }

SID=11111111-2222-3333-4444-555555555555
PD="$W/my proj/it's repo"; mkdir -p "$PD"
RN="it's repo"
rec() { # event line1 line2 [tabtitle]; env EP (default claude-vscode), RAW (default root)
  printf 'event=%s\nsession=%s\nentrypoint=%s\nroot=%s\nrawroot=%s\nprojectdir=%s\ntitle=Claude needs permission\ntabtitle=%s\nline1=%s\nline2=%s\nmarker=\n' \
    "$1" "$SID" "${EP-claude-vscode}" "$RN" "${RAW-$RN}" "$PD" "$4" "$2" "$3"
}
run_notify() { PATH="$W/bin:$BASEPATH" sh "$MAC/notify" 2>"$W/stderr"; echo $?; }
run_notify2() { PATH="$W/bin2:$BASEPATH" sh "$MAC/notify" 2>"$W/stderr"; echo $?; }

# 1. terminal-notifier args and quoting
reset
L2='$(touch /tmp/pwned) "q" `x`'
rm -f /tmp/pwned
rc=$(rec permission "it's repo - tab" "$L2" "tab" | run_notify)
[ "$rc" = 0 ] && ok tn_rc || bad tn_rc "rc=$rc"
has tn_called 'CALL terminal-notifier'
has tn_title 'ARG Claude needs permission'
has tn_subtitle "ARG it's repo - tab"
has tn_message "ARG $L2"
has tn_sound_ping 'ARG Ping'
has tn_group "ARG $SID"
exec_str=$(grep -A1 -x 'ARG -execute' "$LOG" | tail -1 | sed 's/^ARG //')
case "$exec_str" in *touch*|*'"q"'*|*'needs permission'*) bad execute_only_dir_session "text leaked: $exec_str" ;; *) ok execute_only_dir_session ;; esac
: > "$LOG"
PATH="$W/bin:$BASEPATH" sh -c "$exec_str"
has exec_focus_ran_code 'CALL code'
has exec_projectdir "ARG $PD"
has exec_session "ARG vscode://anthropic.claude-code/open?session=$SID"
[ -e /tmp/pwned ] && { bad exec_no_injection "/tmp/pwned created"; rm -f /tmp/pwned; } || ok exec_no_injection

# 1b. entrypoint and rawroot travel in the -execute command; a terminal session gets no reveal
reset; EP=cli RAW=wt1 rec permission "l1" "l2" "" | run_notify >/dev/null
exec_str=$(grep -A1 -x 'ARG -execute' "$LOG" | tail -1 | sed 's/^ARG //')
case "$exec_str" in *"'cli' 'wt1'") ok exec_carries_ep_raw ;; *) bad exec_carries_ep_raw "execute: $exec_str" ;; esac
: > "$LOG"
PATH="$W/bin:$BASEPATH" sh -c "$exec_str"
has exec_cli_focuses 'CALL code'
hasnt exec_cli_no_reveal "ARG vscode://anthropic.claude-code/open?session=$SID"
grep -q 'no reveal: entrypoint=cli' "$TMPDIR/claude-notify/mac.log" && ok exec_cli_logged || bad exec_cli_logged "$(cat "$TMPDIR/claude-notify/mac.log")"

# 1c. empty line2 never reaches -message (terminal-notifier would print usage)
reset; rec permission "repo - tab" "" "" | run_notify >/dev/null
msg=$(grep -A1 -x 'ARG -message' "$LOG" | tail -1)
[ "$msg" = 'ARG repo - tab' ] && ok empty_line2_uses_line1 || bad empty_line2_uses_line1 "got [$msg]"
reset; rec permission "" "" "" | run_notify >/dev/null
msg=$(grep -A1 -x 'ARG -message' "$LOG" | tail -1)
[ "$msg" = 'ARG Claude needs permission' ] && ok empty_lines_use_title || bad empty_lines_use_title "got [$msg]"

# 2a. ping uses Ping
reset; rec ping "r" "m" "" | run_notify >/dev/null
has ping_sound 'ARG Ping'

# 2. done uses Glass
reset; rec done "r" "m" "" | run_notify >/dev/null
has done_glass 'ARG Glass'

# 3. fallback without terminal-notifier: osascript + afplay, hint once
reset
rc=$(rec permission "l1" "l2" "" | run_notify2)
has fb_osascript 'CALL osascript'
has fb_display 'ARG end run'
has fb_afplay 'CALL afplay'
has fb_afplay_path 'ARG /System/Library/Sounds/Ping.aiff'
hasnt fb_no_tn 'CALL terminal-notifier'
[ -f "$TMPDIR/claude-notify/hint-shown" ] && ok hint_marker || bad hint_marker "no marker"
grep -q terminal-notifier "$W/stderr" && ok hint_printed || bad hint_printed "stderr: $(cat "$W/stderr")"
grep -q 'hint: claude-notify: terminal-notifier not found' "$TMPDIR/claude-notify/mac.log" && ok hint_logged || bad hint_logged "$(cat "$TMPDIR/claude-notify/mac.log")"
rec permission "l1" "l2" "" | run_notify2 >/dev/null
[ -s "$W/stderr" ] && bad hint_once "hint printed twice" || ok hint_once

# 4. silent while watching
reset; export OSA_MODE=ok OSA_OUT="Code|tab ti... - it's repo - Visual Studio Code"
rec permission "it's repo - tab title" "m" "tab title" | run_notify >/dev/null
hasnt watching_silent 'CALL terminal-notifier'
reset; export OSA_MODE=ok OSA_OUT="Code|tab ti${EM} - it's repo - Visual Studio Code"
OSA_OUT="Code|other ${EM} it's repo ${EM} Visual Studio Code"
rec permission "it's repo - tab title" "m" "tab title" | run_notify >/dev/null
has other_tab_notifies 'CALL terminal-notifier'
reset; export OSA_MODE=ok OSA_OUT="Safari|tab title - it's repo"
rec permission "it's repo - tab title" "m" "tab title" | run_notify >/dev/null
has other_app_notifies 'CALL terminal-notifier'
reset; export OSA_MODE=ok OSA_OUT="Code|tab title ${EM} it's repo ${EM} Visual Studio Code"
rec permission "it's repo - tab title" "m" "tab title" | run_notify >/dev/null
hasnt watching_emdash_silent 'CALL terminal-notifier'
reset; export OSA_MODE=ok OSA_OUT="Code|tab title - OTHER - Visual Studio Code"
rec permission "it's repo - tab title" "m" "tab title" | run_notify >/dev/null
has other_root_notifies 'CALL terminal-notifier'
reset  # osascript error: notify normally
rec permission "it's repo - tab title" "m" "tab title" | run_notify >/dev/null
has osa_error_notifies 'CALL terminal-notifier'
reset; export OSA_MODE=ok OSA_OUT="Code|tab title - wt1 - Visual Studio Code"  # worktree window
RAW=wt1 rec permission "it's repo - tab title" "m" "tab title" | run_notify >/dev/null
hasnt watching_rawroot_silent 'CALL terminal-notifier'
reset; export OSA_MODE=ok OSA_OUT="Code|tab title - wt1 - Visual Studio Code"
rec permission "it's repo - tab title" "m" "tab title" | run_notify >/dev/null
has watching_other_rawroot_notifies 'CALL terminal-notifier'

# 5. clear
reset; PATH="$W/bin:$BASEPATH" sh "$MAC/clear" "$SID" repo; has clear_remove 'ARG -remove'; has clear_session "ARG $SID"

# 6. focus.sh
export OSA_MODE=ok OSA_OUT="Code|x"
VS=claude-vscode
reset; export OSA_MODE=ok OSA_OUT="Code|file.txt $EM it's repo $EM Visual Studio Code"
PATH="$W/bin:$BASEPATH" sh "$MAC/focus.sh" "$PD" "$SID" "$VS"
has focus_code "ARG $PD"
has focus_open "ARG vscode://anthropic.claude-code/open?session=$SID"
reset; export OSA_MODE=ok OSA_OUT="Code|file.txt - other - Visual Studio Code"
PATH="$W/bin:$BASEPATH" sh "$MAC/focus.sh" "$PD" "$SID" "$VS"
hasnt focus_skip_other 'CALL open'
grep -q skipped "$TMPDIR/claude-notify/mac.log" && ok focus_skip_logged || bad focus_skip_logged "no log"
reset; export OSA_MODE=ok OSA_OUT="Terminal|it's repo $EM -zsh"
PATH="$W/bin:$BASEPATH" sh "$MAC/focus.sh" "$PD" "$SID" "$VS"
hasnt focus_terminal_no_open "ARG vscode://anthropic.claude-code/open?session=$SID"
grep -q skipped "$TMPDIR/claude-notify/mac.log" && ok focus_terminal_skip_logged || bad focus_terminal_skip_logged "no log"
reset  # osascript error -> unguarded
PATH="$W/bin:$BASEPATH" sh "$MAC/focus.sh" "$PD" "$SID" "$VS"
has focus_unguarded_open "ARG vscode://anthropic.claude-code/open?session=$SID"
grep -q unguarded "$TMPDIR/claude-notify/mac.log" && ok focus_unguarded_logged || bad focus_unguarded_logged "no log"
reset  # bad session: no link
PATH="$W/bin:$BASEPATH" sh "$MAC/focus.sh" "$PD" 'x;rm -rf' "$VS"
hasnt focus_bad_session 'CALL open'
# entrypoint: only claude-vscode reveals (terminal session, or an old link without one)
reset; export OSA_MODE=ok OSA_OUT="Code|file.txt - it's repo - Visual Studio Code"
PATH="$W/bin:$BASEPATH" sh "$MAC/focus.sh" "$PD" "$SID" cli
has focus_cli_code "ARG $PD"
hasnt focus_cli_no_open 'CALL open'
grep -q 'no reveal: entrypoint=cli' "$TMPDIR/claude-notify/mac.log" && ok focus_cli_logged || bad focus_cli_logged "no log"
reset; export OSA_MODE=ok OSA_OUT="Code|file.txt - it's repo - Visual Studio Code"
PATH="$W/bin:$BASEPATH" sh "$MAC/focus.sh" "$PD" "$SID"
hasnt focus_no_ep_no_open 'CALL open'
# guard accepts the worktree folder name (rawroot) as well as the repo root
reset; export OSA_MODE=ok OSA_OUT="Code|file.txt - wt1 - Visual Studio Code"
PATH="$W/bin:$BASEPATH" sh "$MAC/focus.sh" "$PD" "$SID" "$VS" wt1
has focus_rawroot_open "ARG vscode://anthropic.claude-code/open?session=$SID"
reset; export OSA_MODE=ok OSA_OUT="Code|file.txt - wt1 - Visual Studio Code"
PATH="$W/bin:$BASEPATH" sh "$MAC/focus.sh" "$PD" "$SID" "$VS" other
hasnt focus_other_rawroot_skip 'CALL open'

rm -rf "$W"
if [ "$fails" = 0 ]; then echo "mac: PASS"; exit 0; else echo "mac: $fails FAILED"; exit 1; fi
