#!/bin/sh
# Tests for scripts/linux/* using PATH stubs (notify-send, paplay, canberra-gtk-play).
here=$(cd "$(dirname "$0")" && pwd)
LIN="$here/../scripts/linux"
T="${TMPDIR:-${TEMP:-/tmp}}"
if command -v cygpath >/dev/null 2>&1; then T=$(cygpath -u "$T"); fi
W="$T/cn-linux-$$"; mkdir -p "$W/bin" "$W/bin0" "$W/snd"
export LOG="$W/calls.log"
: > "$W/snd/dialog-warning.oga"; : > "$W/snd/complete.oga"

mkstub() {
  cat > "$W/bin/$1" <<STUB
#!/bin/sh
printf 'CALL $1\n' >> "\$LOG"
for a in "\$@"; do printf 'ARG %s\n' "\$a" >> "\$LOG"; done
STUB
  chmod +x "$W/bin/$1"
}
mkstub notify-send; mkstub paplay; mkstub canberra-gtk-play
# PATH with essentials only (no stubs): symlink-free approach, use base PATH minus stubs.
BASEPATH=$PATH
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; shift; for l in "$@"; do echo "  $l"; done; fails=$((fails+1)); }
reset() { : > "$LOG"; }
has() { if grep -qxF -- "$2" "$LOG"; then ok "$1"; else bad "$1" "want [$2] in:" "$(cat "$LOG")"; fi; }
hasnt() { if grep -qxF -- "$2" "$LOG"; then bad "$1" "unexpected [$2] in:" "$(cat "$LOG")"; else ok "$1"; fi; }
rec() { printf 'event=%s\nsession=s1\nroot=r\nprojectdir=/p\ntitle=Claude needs permission\ntabtitle=t\nline1=r - t\nline2=%s\n' "$1" "$2"; }
run() { PATH="$W/bin:$BASEPATH" CLAUDE_NOTIFY_SOUND_DIR="${SD:-$W/snd}" sh "$LIN/notify"; echo $?; }
BODY=$(printf 'r - t\nhello $(x) "q"')

reset; rc=$(rec permission 'hello $(x) "q"' | run)
[ "$rc" = 0 ] && ok perm_rc || bad perm_rc "rc=$rc"
has perm_app 'ARG Claude Code'; has perm_urgency 'ARG critical'; has perm_title 'ARG Claude needs permission'
# body is one multi-line arg: check both lines present as consecutive log lines
grep -qxF 'ARG r - t' "$LOG" && grep -qxF 'hello $(x) "q"' "$LOG" && ok perm_body || bad perm_body "$(cat "$LOG")"
has perm_paplay 'CALL paplay'; has perm_sound "ARG $W/snd/dialog-warning.oga"
reset; rec question x | run >/dev/null; has question_crit 'ARG critical'
reset; rec ping x | run >/dev/null; has ping_crit 'ARG critical'; has ping_sound "ARG $W/snd/dialog-warning.oga"
reset; rec done x | run >/dev/null; has done_normal 'ARG normal'; hasnt done_not_crit 'ARG critical'; has done_sound "ARG $W/snd/complete.oga"
# no sound files -> canberra
reset; SD="$W/nosnd" rec done x | SD="$W/nosnd" run >/dev/null
has canberra 'CALL canberra-gtk-play'; has canberra_id 'ARG complete'; hasnt no_paplay 'CALL paplay'
reset; rec permission x | SD="$W/nosnd" run >/dev/null; has canberra_warn 'ARG dialog-warning'
# no notify-send -> exit 0, nothing logged
reset; rc=$(rec permission x | PATH="$W/bin0:$BASEPATH" sh "$LIN/notify"; echo $?)
[ "$rc" = 0 ] && ok nosend_rc || bad nosend_rc "rc=$rc"
[ -s "$LOG" ] && bad nosend_silent "$(cat "$LOG")" || ok nosend_silent
# clear no-op
sh "$LIN/clear" s1 r; [ $? = 0 ] && ok clear_rc || bad clear_rc "nonzero"

rm -rf "$W"
if [ "$fails" = 0 ]; then echo "linux: PASS"; exit 0; else echo "linux: $fails FAILED"; exit 1; fi
