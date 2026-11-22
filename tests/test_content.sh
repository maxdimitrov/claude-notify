#!/bin/sh
# Tests for scripts/lib/content.sh
here=$(cd "$(dirname "$0")" && pwd)
. "$here/fixlib.sh"
unset CLAUDE_PROJECT_DIR CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ATTENDED
. "$here/../scripts/lib/content.sh"

fails=0
assert_eq() {
  if [ "$2" = "$3" ]; then echo "ok   $1"; else
    echo "FAIL $1"; echo "  expected: [$2]"; echo "  actual:   [$3]"; fails=$((fails+1)); fi
}
assert_has() {
  case "$3" in *"$2"*) echo "ok   $1" ;; *) echo "FAIL $1"; echo "  want substring: [$2]"; echo "  in: [$3]"; fails=$((fails+1)) ;; esac
}
assert_lacks() {
  case "$3" in *"$2"*) echo "FAIL $1"; echo "  unwanted substring: [$2]"; echo "  in: [$3]"; fails=$((fails+1)) ;; *) echo "ok   $1" ;; esac
}
field() { printf '%s\n' "$2" | sed -n "s/^$1=//p"; }

# --- repo root / name
assert_eq root_win 'F:\Claude\Projects\mailroom' "$(cn_repo_root 'F:\Claude\Projects\mailroom\.claude\worktrees\foo')"
assert_eq root_fwd 'F:/Claude/Projects/mailroom' "$(cn_repo_root 'F:/Claude/Projects/mailroom/.claude/worktrees/foo')"
assert_eq root_plain '/home/u/proj' "$(cn_repo_root '/home/u/proj')"
assert_eq name_win mailroom "$(cn_repo_name 'F:\Claude\Projects\mailroom')"
assert_eq name_fwd mailroom "$(cn_repo_name 'f:/Claude/Projects/mailroom')"

# --- tab title
assert_eq tab_custom_wins 'Live Account Analysis' "$(cn_tab_title "$FIX/transcript_titles.jsonl")"
assert_eq tab_cyr "$(cat "$FIX/expected_cyr.txt")" "$(cn_tab_title "$FIX/transcript_cyr.jsonl")"
assert_eq tab_none '' "$(cn_tab_title "$FIX/transcript_none.jsonl")"
assert_eq tab_missing '' "$(cn_tab_title "$FIX/nope.jsonl")"
assert_eq tab_empty_arg '' "$(cn_tab_title '')"
tmp="${TMPDIR:-${TEMP:-/tmp}}/cn-test-$$"; mkdir -p "$tmp"
printf '%s\n' '{"type":"ai-title","aiTitle":"Only AI","sessionId":"s"}' > "$tmp/ai.jsonl"
assert_eq tab_ai_only 'Only AI' "$(cn_tab_title "$tmp/ai.jsonl")"
# large file: title near the end, > 4 MB of filler before it
{ i=0; while [ $i -lt 600 ]; do printf '{"type":"user","message":"%07000d"}\n' 0; i=$((i+1)); done
  printf '%s\n' '{"type":"custom-title","customTitle":"Tail Title","sessionId":"s"}'; } > "$tmp/big.jsonl"
assert_eq tab_big_tail 'Tail Title' "$(cn_tab_title "$tmp/big.jsonl")"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*)
  wp=$(cygpath -w "$FIX/transcript_titles.jsonl")
  assert_eq tab_backslash_path 'Live Account Analysis' "$(cn_tab_title "$wp")" ;;
esac
rm -rf "$tmp"

# --- clean text
nl='
'
assert_eq clean_md 'Bold and code link item' "$(cn_clean_text "**Bold** and \`code\` [link](http://x)${nl}- item")"
long=$(awk 'BEGIN{for(i=0;i<300;i++) printf "a"}')
out=$(cn_clean_text "$long")
assert_eq clean_len 180 "${#out}"
case "$out" in *...) echo "ok   clean_ellipsis" ;; *) echo "FAIL clean_ellipsis [$out]"; fails=$((fails+1)) ;; esac
assert_eq clean_ws 'a b c' "$(cn_clean_text "  a${nl}${nl}  b	c  ")"
assert_eq clean_heading 'Title body' "$(cn_clean_text "## Title${nl}body")"
assert_eq clean_short_untouched 'hello' "$(cn_clean_text hello)"

# --- records
rec=$(cn_build_record permission "$(fx perm.json)")
assert_has rec_title 'title=Claude needs permission' "$rec"
assert_eq rec_line1 'fixture-repo - Live Account Analysis' "$(field line1 "$rec")"
assert_eq rec_tabtitle 'Live Account Analysis' "$(field tabtitle "$rec")"
assert_eq rec_root fixture-repo "$(field root "$rec")"
assert_eq rec_session sess-perm-1 "$(field session "$rec")"
assert_eq rec_event permission "$(field event "$rec")"
assert_has rec_line2_text 'Bash' "$(field line2 "$rec")"
assert_lacks rec_line2_no_bold '**' "$(field line2 "$rec")"
assert_has rec_line2_keeps_meta '<tag> & "q"' "$(field line2 "$rec")"
assert_eq rec_line_count 8 "$(printf '%s\n' "$rec" | wc -l | tr -d ' ')"
assert_eq rec_field_order 'event session root projectdir title tabtitle line1 line2' "$(printf '%s\n' "$rec" | sed 's/=.*//' | tr '\n' ' ' | sed 's/ $//')"

rec=$(cn_build_record question "$(fx question.json)")
assert_has rec_question_title 'title=Claude has a question' "$rec"
rec=$(cn_build_record done "$(fx stop.json)")
assert_has rec_done_title 'title=Claude is done' "$rec"
assert_has rec_done_line2 'refactor' "$(field line2 "$rec")"
assert_lacks rec_done_no_link '](http' "$(field line2 "$rec")"
assert_lacks rec_done_no_hash '##' "$(field line2 "$rec")"
l2=$(field line2 "$rec"); assert_eq rec_done_line2_len 180 "${#l2}"

rec=$(cn_build_record permission "$(fx notitle.json)")
assert_eq no_title_line1 fixture-repo "$(field line1 "$rec")"
assert_eq no_title_tabtitle '' "$(field tabtitle "$rec")"
rec=$(cn_build_record permission "$(fx notranscript.json)")
assert_eq no_transcript_line1 fixture-repo "$(field line1 "$rec")"

rec=$(cn_build_record permission "$(fx cyr.json)")
assert_eq cyr_tabtitle "$(cat "$FIX/expected_cyr.txt")" "$(field tabtitle "$rec")"
assert_eq cyr_line2 "$(cat "$FIX/expected_cyr_msg.txt")" "$(field line2 "$rec")"

# env vs cwd for root/projectdir
rec=$(cn_build_record permission "$(fx winwt.json)")
assert_eq root_from_cwd_worktree mailroom "$(field root "$rec")"
assert_eq projectdir_cwd_worktree 'F:\Claude\Projects\mailroom' "$(field projectdir "$rec")"
CLAUDE_PROJECT_DIR='c:/Users/maxa2/claude'; export CLAUDE_PROJECT_DIR
rec=$(cn_build_record permission "$(fx winwt.json)")
assert_eq root_from_env claude "$(field root "$rec")"
assert_eq projectdir_from_env 'c:/Users/maxa2/claude' "$(field projectdir "$rec")"
CLAUDE_PROJECT_DIR='f:/Claude/Projects/quant-atelier/.claude/worktrees/x'
rec=$(cn_build_record permission "$(fx perm.json)")
assert_eq root_from_env_worktree quant-atelier "$(field root "$rec")"
assert_eq projectdir_env_worktree 'f:/Claude/Projects/quant-atelier' "$(field projectdir "$rec")"
unset CLAUDE_PROJECT_DIR

# --- no jq: build a PATH without any dir that holds jq
nojq=""
oldifs=$IFS; IFS=:
for d in $PATH; do
  if [ -x "$d/jq" ] || [ -x "$d/jq.exe" ]; then continue; fi
  nojq="${nojq:+$nojq:}$d"
done
IFS=$oldifs
if PATH="$nojq" command -v jq >/dev/null 2>&1; then
  echo "SKIP no_jq (cannot remove jq from PATH)"
else
  rec=$(PATH="$nojq" cn_build_record permission "$(fx notitle.json)")
  assert_has no_jq_title 'title=Claude needs permission' "$rec"
  assert_eq no_jq_line1 fixture-repo "$(field line1 "$rec")"
  assert_eq no_jq_line2 '' "$(field line2 "$rec")"
  assert_eq no_jq_session sess-nt-1 "$(field session "$rec")"
  rec=$(PATH="$nojq" cn_build_record permission "$(fx winwt.json)")
  assert_eq no_jq_cwd_worktree mailroom "$(field root "$rec")"
fi

rm -rf "$FIXROOT"
if [ "$fails" = 0 ]; then echo "content: PASS"; exit 0; else echo "content: $fails FAILED"; exit 1; fi
