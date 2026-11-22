# CLAUDE.md

Claude Code plugin `claude-notify`: desktop notifications (sound + toast naming the session) when a session needs the user or finishes; click focuses the VS Code window and Claude tab. Spec and plan under `docs/superpowers/`.

## Rules

- All `.ps1`, `.sh`, `.cmd` files are pure ASCII, comments included. Check: `LC_ALL=C grep -rn '[^[:print:][:space:]]' scripts tests hooks` prints nothing.
- Windows toast code runs under `powershell.exe` (5.1), never pwsh. No `Set-StrictMode -Version Latest`.
- Every hook is `async: true`, `timeout: 15`; every script swallows its own failures and exits 0.
- Commits are signed via plain `git commit`; never bypass signing.

## Tests

TBD (added with the test tasks).

## Verified environment

