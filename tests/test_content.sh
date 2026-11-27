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
assert_eq rec_line_count 11 "$(printf '%s\n' "$rec" | wc -l | tr -d ' ')"
assert_eq rec_field_order 'event session entrypoint root rawroot projectdir title tabtitle line1 line2 marker' "$(printf '%s\n' "$rec" | sed 's/=.*//' | tr '\n' ' ' | sed 's/ $//')"
assert_eq rec_entrypoint_empty '' "$(field entrypoint "$rec")"
assert_eq rec_rawroot_plain fixture-repo "$(field rawroot "$rec")"
assert_eq rec_marker_default '' "$(field marker "$rec")"
rec=$(CLAUDE_CODE_ENTRYPOINT=claude-vscode cn_build_record permission "$(fx perm.json)" '/t/claude-notify/sess-perm-1.pending')
assert_eq rec_entrypoint claude-vscode "$(field entrypoint "$rec")"
assert_eq rec_marker '/t/claude-notify/sess-perm-1.pending' "$(field marker "$rec")"

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
assert_eq rawroot_cwd_worktree foo "$(field rawroot "$rec")"
assert_eq projectdir_cwd_worktree 'F:\Claude\Projects\mailroom' "$(field projectdir "$rec")"
CLAUDE_PROJECT_DIR='c:/Users/maxa2/claude'; export CLAUDE_PROJECT_DIR
rec=$(cn_build_record permission "$(fx winwt.json)")
assert_eq root_from_env claude "$(field root "$rec")"
assert_eq projectdir_from_env 'c:/Users/maxa2/claude' "$(field projectdir "$rec")"
CLAUDE_PROJECT_DIR='f:/Claude/Projects/quant-atelier/.claude/worktrees/x'
rec=$(cn_build_record permission "$(fx perm.json)")
assert_eq root_from_env_worktree quant-atelier "$(field root "$rec")"
assert_eq rawroot_env_worktree x "$(field rawroot "$rec")"
assert_eq projectdir_env_worktree 'f:/Claude/Projects/quant-atelier' "$(field projectdir "$rec")"
unset CLAUDE_PROJECT_DIR

# --- permission tool, tokens, marker attributes
assert_eq perm_tool_plain Bash "$(cn_perm_tool 'Claude needs your permission to use Bash')"
assert_eq perm_tool_bold Bash "$(cn_perm_tool 'Claude needs your permission to use **Bash** with x')"
assert_eq perm_tool_mcp mcp__gh__create_issue "$(cn_perm_tool 'Claude needs your permission to use mcp__gh__create_issue')"
assert_eq perm_tool_none '' "$(cn_perm_tool 'Claude is waiting for your input')"
assert_eq token_clean 'a_b_c' "$(cn_token 'a b;c')"
assert_eq marker_attr_tool Bash "$(cn_marker_attr 'toast tool=Bash agent=ag1' tool)"
assert_eq marker_attr_agent ag1 "$(cn_marker_attr 'toast tool=Bash agent=ag1' agent)"
assert_eq marker_attr_missing '' "$(cn_marker_attr 'toast' tool)"

# --- cn_should_clear: <marker> <event> <tool_name> <agent_id> -> yes/no
sc() { if cn_should_clear "$1" "$2" "$3" "$4"; then echo yes; else echo no; fi; }
assert_eq sc_toast_tool_match yes "$(sc 'toast tool=Bash' PostToolUse Bash '')"
assert_eq sc_toast_tool_other no "$(sc 'toast tool=Bash' PostToolUse Read '')"
assert_eq sc_toast_mcp_match yes "$(sc 'toast tool=Send' PostToolUse mcp__gmail-multi__send_email '')"
assert_eq sc_toast_mcp_other no "$(sc 'toast tool=Send' PostToolUse mcp__other__list_labels '')"
assert_eq sc_toast_mcp_agent_other no "$(sc 'toast tool=Send agent=ag1' PostToolUse mcp__gmail-multi__send_email ag2)"
assert_eq sc_toast_mcp_full_name yes "$(sc 'toast tool=mcp__gh__x' PostToolUse mcp__gh__x '')"
assert_eq sc_toast_agent_match yes "$(sc 'toast tool=Bash agent=ag1' PostToolUse Bash ag1)"
assert_eq sc_toast_agent_other no "$(sc 'toast tool=Bash agent=ag1' PostToolUse Bash ag2)"
assert_eq sc_toast_agent_missing no "$(sc 'toast tool=Bash agent=ag1' PostToolUse Bash '')"
assert_eq sc_toast_agent_only_match yes "$(sc 'toast agent=ag1' PostToolUse Read ag1)"
assert_eq sc_toast_agent_only_other no "$(sc 'toast agent=ag1' PostToolUse Read '')"
assert_eq sc_toast_bare yes "$(sc 'toast' PostToolUse Read '')"
assert_eq sc_toast_prompt yes "$(sc 'toast tool=Bash agent=ag1' UserPromptSubmit '' '')"
assert_eq sc_toast_denied yes "$(sc 'toast tool=Bash agent=ag1' PermissionDenied Read '')"
assert_eq sc_toast_unknown_event no "$(sc 'toast tool=Bash' '' '' '')"
assert_eq sc_toast_bare_unknown_event yes "$(sc 'toast' '' '' '')"
assert_eq sc_question_ask yes "$(sc 'question' PostToolUse AskUserQuestion '')"
assert_eq sc_question_other_tool no "$(sc 'question' PostToolUse Bash '')"
assert_eq sc_question_denied no "$(sc 'question' PermissionDenied Bash '')"
assert_eq sc_question_prompt yes "$(sc 'question' UserPromptSubmit '' '')"
assert_eq sc_question_agent_other no "$(sc 'question agent=ag1' PostToolUse AskUserQuestion ag2)"
assert_eq sc_ping_post no "$(sc 'ping' PostToolUse Bash '')"
assert_eq sc_ping_denied no "$(sc 'ping' PermissionDenied Bash '')"
assert_eq sc_ping_prompt yes "$(sc 'ping' UserPromptSubmit '' '')"

# --- transcript cwd
assert_eq tcwd_first 'C:\Users\u\Projects\from-transcript\.claude\worktrees\wt1' "$(cn_transcript_cwd "$FIX/transcript_cwd.jsonl")"
assert_eq tcwd_none '' "$(cn_transcript_cwd "$FIX/transcript_titles.jsonl")"
assert_eq tcwd_missing '' "$(cn_transcript_cwd "$FIX/nope.jsonl")"
assert_eq tcwd_empty_arg '' "$(cn_transcript_cwd '')"

# --- turn origin
assert_eq origin_peer peer "$(cn_turn_origin "$FIX/transcript_origin_peer.jsonl")"
assert_eq origin_task task-notification "$(cn_turn_origin "$FIX/transcript_origin_task.jsonl")"
assert_eq origin_human human "$(cn_turn_origin "$FIX/transcript_origin_human.jsonl")"
assert_eq origin_none '' "$(cn_turn_origin "$FIX/transcript_origin_none.jsonl")"
assert_eq origin_missing '' "$(cn_turn_origin "$FIX/nope.jsonl")"
assert_eq origin_empty_arg '' "$(cn_turn_origin '')"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*)
  # payload transcript_path arrives with backslashes on Windows
  wp=$(cygpath -w "$FIX/transcript_origin_peer.jsonl")
  assert_eq origin_backslash_path peer "$(cn_turn_origin "$wp")" ;;
esac
assert_eq origin_backslash_relative peer "$(cd "$FIX/.." && cn_turn_origin 'fixtures\transcript_origin_peer.jsonl')"

# --- ping record
mkdir -p "$FIXROOT/home/.claude/projects/-x"
cp "$FIX/transcript_titles.jsonl" "$FIXROOT/home/.claude/projects/-x/sess-ping-1.jsonl"
rec=$(HOME="$FIXROOT/home" CLAUDE_CODE_SESSION_ID=sess-ping-1 CLAUDE_PROJECT_DIR=/p/my-repo cn_build_ping 'ready **to** test')
assert_eq ping_event ping "$(field event "$rec")"
assert_eq ping_title 'Claude needs you' "$(field title "$rec")"
assert_eq ping_session sess-ping-1 "$(field session "$rec")"
assert_eq ping_root my-repo "$(field root "$rec")"
assert_eq ping_line2 'ready to test' "$(field line2 "$rec")"
assert_has ping_tab ' - ' "$(field line1 "$rec")"
assert_eq ping_marker_default '' "$(field marker "$rec")"
# Bash tool env: no CLAUDE_PROJECT_DIR, cwd elsewhere -> project dir from the transcript's cwd
cp "$FIX/transcript_cwd.jsonl" "$FIXROOT/home/.claude/projects/-x/sess-cwd-1.jsonl"
mkdir -p "$FIXROOT/elsewhere/wrong-repo"
rec=$(cd "$FIXROOT/elsewhere/wrong-repo" && HOME="$FIXROOT/home" CLAUDE_CODE_SESSION_ID=sess-cwd-1 cn_build_ping 'done' "$FIXROOT/m.pending")
assert_eq ping_cwd_root from-transcript "$(field root "$rec")"
assert_eq ping_cwd_rawroot wt1 "$(field rawroot "$rec")"
assert_eq ping_cwd_projectdir 'C:\Users\u\Projects\from-transcript' "$(field projectdir "$rec")"
assert_eq ping_cwd_line1 'from-transcript - Cwd Tab' "$(field line1 "$rec")"
assert_eq ping_cwd_marker "$FIXROOT/m.pending" "$(field marker "$rec")"
rec=$(cd "$FIXROOT/elsewhere/wrong-repo" && HOME="$FIXROOT/home" CLAUDE_CODE_SESSION_ID=sess-cwd-1 CLAUDE_PROJECT_DIR=/p/env-repo cn_build_ping 'done')
assert_eq ping_env_beats_transcript env-repo "$(field root "$rec")"
rec=$(cd "$FIXROOT/elsewhere/wrong-repo" && HOME="$FIXROOT/home" CLAUDE_CODE_SESSION_ID=sess-none cn_build_ping 'done')
assert_eq ping_pwd_last wrong-repo "$(field root "$rec")"

# --- markdown strip keeps dunder names
assert_eq md_dunder 'edit __init__.py now' "$(cn_clean_text 'edit __init__.py now')"
assert_eq md_bold 'a bold b' "$(cn_clean_text 'a **bold** b')"

# --- no jq: a PATH without jq that keeps the other tools of jq's dir
. "$here/pathlib.sh"
nojq=$(path_without jq "$FIXROOT")
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
  assert_eq no_jq_tcwd 'C:\Users\u\Projects\from-transcript\.claude\worktrees\wt1' "$(PATH="$nojq" cn_transcript_cwd "$FIX/transcript_cwd.jsonl")"
fi

rm -rf "$FIXROOT"
if [ "$fails" = 0 ]; then echo "content: PASS"; exit 0; else echo "content: $fails FAILED"; exit 1; fi
