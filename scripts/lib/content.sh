#!/bin/sh
# claude-notify content library (POSIX sh, sourced). Pure functions, output on stdout.
# No bashisms, no `local`; internal variables are prefixed _cn_.

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

# cn_clean_text <text> -> whitespace collapsed, markdown stripped, max 180 chars (177 + "...").
cn_clean_text() {
  _cn_c=$(printf '%s\n' "$1" | tr '\t\r' '  ' \
    | sed -e 's/^[[:space:]]*[-*+][[:space:]][[:space:]]*//' \
          -e 's/^[[:space:]]*#\{1,6\}[[:space:]]*//' \
          -e 's/^[[:space:]]*>[[:space:]]*//' \
          -e 's/!\{0,1\}\[\([^]]*\)\]([^)]*)/\1/g' \
          -e 's/\*\*//g' -e 's/__//g' -e 's/~~//g' -e 's/`//g' \
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
  esac
}

# cn_project_dir <payload_json> -> CLAUDE_PROJECT_DIR if set, else payload cwd (uncut).
cn_project_dir() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then printf '%s' "$CLAUDE_PROJECT_DIR"; else cn_field "$1" cwd; fi
}

# cn_build_record <event> <payload_json> -> the 8-line record (see plan File Structure).
cn_build_record() {
  _cn_ev=$1; _cn_pl=$2
  _cn_sid=$(cn_field "$_cn_pl" session_id)
  _cn_dir=$(cn_project_dir "$_cn_pl")
  _cn_name=$(cn_repo_name "$(cn_repo_root "$_cn_dir")")
  _cn_tab=''; _cn_l2=''
  if cn_have_jq; then
    _cn_tab=$(cn_tab_title "$(cn_field "$_cn_pl" transcript_path)")
    if [ "$_cn_ev" = done ]; then _cn_raw=$(cn_field "$_cn_pl" last_assistant_message)
    else _cn_raw=$(cn_field "$_cn_pl" message); fi
    _cn_l2=$(cn_clean_text "$_cn_raw")
  fi
  if [ -n "$_cn_tab" ]; then _cn_l1="$_cn_name - $_cn_tab"; else _cn_l1=$_cn_name; fi
  # values must be single-line
  printf 'event=%s\nsession=%s\nroot=%s\nprojectdir=%s\ntitle=%s\ntabtitle=%s\nline1=%s\nline2=%s\n' \
    "$_cn_ev" "$_cn_sid" "$_cn_name" "$_cn_dir" "$(cn_event_title "$_cn_ev")" \
    "$(printf '%s' "$_cn_tab" | tr '\n' ' ')" "$(printf '%s' "$_cn_l1" | tr '\n' ' ')" "$_cn_l2"
}
