#!/bin/sh
# claude-notify content library (POSIX sh, sourced). Pure functions, output on stdout.
# No bashisms, no `local`; internal variables are prefixed _cn_.
#
# Record (dispatcher -> backend): UTF-8, one key=value per line, values single-line,
# backends parse by key (order is informational):
#   event=permission|question|done|ping
#   session=<session_id>
#   entrypoint=<CLAUDE_CODE_ENTRYPOINT, may be empty; claude-vscode = VS Code tab>
#   root=<repo name: leaf of the project dir after cutting /.claude/worktrees/<name>>
#   rawroot=<leaf of the UNCUT project dir; differs from root in a worktree>
#   projectdir=<project dir with the worktree suffix cut, native path>
#   title=<toast title>
#   tabtitle=<tab title, may be empty>
#   line1=<repo - tab title>
#   line2=<message>
#   marker=<pending-marker path, native path; empty for done>

cn_have_jq() { command -v jq >/dev/null 2>&1; }

# cn_field <json> <name> -> value of a top-level field, empty if absent.
# jq when available; otherwise a sed fallback that handles simple strings and literals.
cn_field() {
  if cn_have_jq; then
    printf '%s' "$1" | jq -r --arg k "$2" '.[$k] // empty' 2>/dev/null | tr -d '\r'
  else
    _cn_v=$(printf '%s' "$1" | tr '\n' ' ' | sed -n "s/.*\"$2\" *: *\"\([^\"]*\)\".*/\1/p" | sed 's/\\\\/\\/g' | head -n 1)
    if [ -z "$_cn_v" ]; then
      _cn_v=$(printf '%s' "$1" | tr '\n' ' ' | sed -n "s/.*\"$2\" *: *\([^,}\" ]*\).*/\1/p" | head -n 1)
    fi
    printf '%s' "$_cn_v"
  fi
}

# cn_repo_root <dir> -> dir with any /.claude/worktrees/<name> suffix (either slash) cut.
cn_repo_root() {
  printf '%s' "$1" | sed 's#[/\]*$##; s#[/\]\.claude[/\]worktrees\([/\].*\)\{0,1\}$##'
}

# cn_repo_name <root> -> leaf name.
cn_repo_name() {
  printf '%s' "$1" | sed 's#[/\]*$##; s#.*[/\]##'
}

# cn_token <value> -> value reduced to [A-Za-z0-9_.:-] (other bytes become _), for marker attributes.
cn_token() {
  printf '%s' "$1" | tr -d '\r\n' | tr -c 'A-Za-z0-9_.:-' '_'
}

# cn_perm_tool <notification message> -> tool name after "permission to use ", else empty.
cn_perm_tool() {
  printf '%s\n' "$1" | tr -d '*`' | sed -n 's/.*permission to use \([A-Za-z0-9_.:-][A-Za-z0-9_.:-]*\).*/\1/p' | head -n 1
}

# cn_marker_attr <marker content> <key> -> value of " key=value" in the marker, else empty.
cn_marker_attr() {
  printf '%s\n' "$1" | sed -n "s/.* $2=\([^ ]*\).*/\1/p" | head -n 1
}

# cn_should_clear <marker content> <hook_event_name> <tool_name> <agent_id> -> status 0 = clear.
# Marker kinds: "ping"; "question[ agent=<id>]"; "toast[ tool=<Tool>][ agent=<id>]" (a bare
# "toast" is the pre-0.1.0 form). UserPromptSubmit clears everything. PermissionDenied clears
# toast markers. PostToolUse: ping never; question only for AskUserQuestion; toast only when
# the marker's tool (if any) equals tool_name and its agent (if any) equals agent_id.
cn_should_clear() {
  _cn_kind=${1%% *}
  [ "$2" = UserPromptSubmit ] && return 0
  [ "$_cn_kind" = ping ] && return 1
  _cn_mt=$(cn_marker_attr "$1" tool)
  _cn_ma=$(cn_marker_attr "$1" agent)
  case "$2" in
    PermissionDenied)
      [ "$_cn_kind" = question ] && return 1
      return 0 ;;
    PostToolUse)
      if [ "$_cn_kind" = question ]; then [ "$3" = AskUserQuestion ] || return 1; fi
      if [ -n "$_cn_mt" ] && [ "$3" != "$_cn_mt" ]; then
        # MCP tools: the message shows "Send Email" for mcp__srv__send_email, so the marker holds
        # "Send". Compare the payload's display-form first word, case-insensitively.
        _cn_pt=$(printf '%s' "$3" | sed -e 's/.*__//' -e 's/_.*//' | tr 'A-Z' 'a-z')
        _cn_mtl=$(printf '%s' "$_cn_mt" | tr 'A-Z' 'a-z')
        [ -n "$_cn_pt" ] && [ "$_cn_pt" = "$_cn_mtl" ] || return 1
      fi
      if [ -n "$_cn_ma" ] && [ "$4" != "$_cn_ma" ]; then return 1; fi
      return 0 ;;
  esac
  # Unknown event (e.g. unparsable payload): only a bare toast clears, as before.
  [ "$_cn_kind" = toast ] && [ -z "$_cn_mt$_cn_ma" ] && return 0
  return 1
}

# cn_tab_title <transcript_path> -> latest customTitle, else latest aiTitle, else empty.
# Reads at most the last 4 MB. Needs jq (empty without it).
cn_tab_title() {
  _cn_p=$1
  [ -n "$_cn_p" ] || return 0
  cn_have_jq || return 0
  [ -f "$_cn_p" ] || _cn_p=$(printf '%s' "$_cn_p" | sed 's#\\#/#g')
  [ -f "$_cn_p" ] || return 0
  _cn_tail=$(tail -c 4194304 "$_cn_p" 2>/dev/null)
  _cn_t=$(printf '%s\n' "$_cn_tail" | grep '"type" *: *"custom-title"' | tail -n 1 | jq -r '.customTitle // empty' 2>/dev/null | tr -d '\r')
  if [ -z "$_cn_t" ]; then
    _cn_t=$(printf '%s\n' "$_cn_tail" | grep '"type" *: *"ai-title"' | tail -n 1 | jq -r '.aiTitle // empty' 2>/dev/null | tr -d '\r')
  fi
  printf '%s' "$_cn_t"
}

# cn_transcript_cwd <transcript_path> -> first top-level "cwd" in the first 50 lines, unescaped.
cn_transcript_cwd() {
  [ -n "$1" ] && [ -f "$1" ] || return 0
  if cn_have_jq; then
    head -n 50 "$1" 2>/dev/null | jq -R -r 'fromjson? | objects | .cwd // empty | strings' 2>/dev/null | head -n 1 | tr -d '\r'
  else
    head -n 50 "$1" 2>/dev/null | grep -o '"cwd":"[^"]*"' | head -n 1 | sed 's/^"cwd":"//; s/"$//; s/\\\\/\\/g'
  fi
}

# cn_clean_text <text> -> whitespace collapsed, markdown stripped, max 180 chars (177 + "...").
cn_clean_text() {
  _cn_c=$(printf '%s\n' "$1" | tr '\t\r' '  ' \
    | sed -e 's/^[[:space:]]*[-*+][[:space:]][[:space:]]*//' \
          -e 's/^[[:space:]]*#\{1,6\}[[:space:]]*//' \
          -e 's/^[[:space:]]*>[[:space:]]*//' \
          -e 's/!\{0,1\}\[\([^]]*\)\]([^)]*)/\1/g' \
          -e 's/\*\*//g' -e 's/~~//g' -e 's/`//g' \
    | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')
  if cn_have_jq; then
    printf '%s' "$_cn_c" | jq -Rrj 'if length > 180 then .[0:177] + "..." else . end' 2>/dev/null | tr -d '\r'
  elif [ "${#_cn_c}" -gt 180 ]; then
    # Fallback: cut by length, then drop a trailing partial UTF-8 sequence.
    _cn_c=$(printf '%.177s' "$_cn_c" | LC_ALL=C sed "s/[$(printf '\300')-$(printf '\377')][$(printf '\200')-$(printf '\277')]*\$//")
    printf '%s...' "$_cn_c"
  else
    printf '%s' "$_cn_c"
  fi
}

# cn_event_title <event> -> toast title
cn_event_title() {
  case "$1" in
    permission) printf '%s' 'Claude needs permission' ;;
    question) printf '%s' 'Claude has a question' ;;
    done) printf '%s' 'Claude is done' ;;
    ping) printf '%s' 'Claude needs you' ;;
  esac
}

# cn_project_dir <payload_json> -> CLAUDE_PROJECT_DIR if set, else payload cwd (uncut).
cn_project_dir() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then printf '%s' "$CLAUDE_PROJECT_DIR"; else cn_field "$1" cwd; fi
}

# cn_emit_record <event> <session> <uncut dir> <tab title> <line2> <marker> -> the record.
cn_emit_record() {
  _cn_cut=$(cn_repo_root "$3")
  _cn_name=$(cn_repo_name "$_cn_cut")
  _cn_t1=$(printf '%s' "$4" | tr '\n' ' ')
  if [ -n "$_cn_t1" ]; then _cn_l1="$_cn_name - $_cn_t1"; else _cn_l1=$_cn_name; fi
  printf 'event=%s\nsession=%s\nentrypoint=%s\nroot=%s\nrawroot=%s\nprojectdir=%s\ntitle=%s\ntabtitle=%s\nline1=%s\nline2=%s\nmarker=%s\n' \
    "$1" "$2" "$(printf '%s' "${CLAUDE_CODE_ENTRYPOINT:-}" | tr '\n' ' ')" "$_cn_name" "$(cn_repo_name "$3")" \
    "$_cn_cut" "$(cn_event_title "$1")" "$_cn_t1" "$(printf '%s' "$_cn_l1" | tr '\n' ' ')" "$5" \
    "$(printf '%s' "$6" | tr '\n' ' ')"
}

# cn_build_record <event> <payload_json> [marker] -> the record (format at the top).
cn_build_record() {
  _cn_ev=$1; _cn_pl=$2
  _cn_sid=$(cn_field "$_cn_pl" session_id)
  _cn_dir=$(cn_project_dir "$_cn_pl")
  _cn_tab=''; _cn_l2=''
  if cn_have_jq; then
    _cn_tab=$(cn_tab_title "$(cn_field "$_cn_pl" transcript_path)")
    if [ "$_cn_ev" = done ]; then _cn_msg=$(cn_field "$_cn_pl" last_assistant_message)
    else _cn_msg=$(cn_field "$_cn_pl" message); fi
    _cn_l2=$(cn_clean_text "$_cn_msg")
  fi
  cn_emit_record "$_cn_ev" "$_cn_sid" "$_cn_dir" "$_cn_tab" "$_cn_l2" "${3:-}"
}

# cn_turn_origin <transcript_path> -> last "origin":{"kind":"<kind>"} in the last 4 MB, else empty.
# Kinds seen: human, peer, task-notification. Plain text match, no jq needed.
cn_turn_origin() {
  _cn_p=$1
  [ -n "$_cn_p" ] || return 0
  [ -f "$_cn_p" ] || _cn_p=$(printf '%s' "$_cn_p" | sed 's#\\#/#g')
  [ -f "$_cn_p" ] || return 0
  tail -c 4194304 "$_cn_p" 2>/dev/null | grep -o '"origin":{"kind":"[^"]*"}' | tail -n 1 \
    | sed 's/^"origin":{"kind":"\(.*\)"}$/\1/' | tr -d '\r'
}

# cn_build_ping <message> [marker] -> the record for a deliberate ping, built from env:
# CLAUDE_CODE_SESSION_ID; the transcript found under $HOME/.claude/projects; project dir =
# CLAUDE_PROJECT_DIR, else the transcript's first cwd, else $PWD (the Bash tool's cwd can
# be anywhere, and CLAUDE_PROJECT_DIR is not set in the Bash tool's environment).
cn_build_ping() {
  _cn_sid=${CLAUDE_CODE_SESSION_ID:-}
  _cn_tp=''
  if [ -n "$_cn_sid" ]; then
    for _cn_f in "$HOME"/.claude/projects/*/"$_cn_sid".jsonl; do
      [ -f "$_cn_f" ] && { _cn_tp=$_cn_f; break; }
    done
  fi
  _cn_dir=${CLAUDE_PROJECT_DIR:-}
  [ -n "$_cn_dir" ] || _cn_dir=$(cn_transcript_cwd "$_cn_tp")
  [ -n "$_cn_dir" ] || _cn_dir=$PWD
  _cn_tab=''; _cn_l2=''
  if cn_have_jq; then
    _cn_tab=$(cn_tab_title "$_cn_tp")
    _cn_l2=$(cn_clean_text "$1")
  fi
  cn_emit_record ping "$_cn_sid" "$_cn_dir" "$_cn_tab" "$_cn_l2" "${2:-}"
}
