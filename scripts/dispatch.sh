#!/bin/sh
# claude-notify probe dispatcher (Task 1). Logs the environment; always exits 0.
{
  d="${TMPDIR:-${TEMP:-/tmp}}/claude-notify"
  mkdir -p "$d"
  in=$(head -c 200)
  printf '%s | arg=%s | entrypoint=%s | attended=%s | project_dir=%s | jq=%s | stdin=%s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "${CLAUDE_CODE_ENTRYPOINT:-}" \
    "${CLAUDE_CODE_SESSION_ATTENDED:-}" "${CLAUDE_PROJECT_DIR:-}" \
    "$(command -v jq)" "$in" >> "$d/probe.log"
} 2>/dev/null
exit 0
