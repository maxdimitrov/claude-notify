# CLAUDE.md

Claude Code plugin `claude-notify`: desktop notifications (sound + toast naming the session) when a session needs the user or finishes; click focuses the VS Code window and Claude tab. Spec and plan under `docs/superpowers/`.

## Rules

- All `.ps1`, `.sh`, `.cmd` files and skills are pure ASCII, comments included. Check: `LC_ALL=C grep -rn '[^[:print:][:space:]]' scripts hooks tests skills --exclude-dir=fixtures` prints nothing.
- Windows toast code runs under `powershell.exe` (5.1), never pwsh. No `Set-StrictMode -Version Latest`.
- Every hook is `async: true`, `timeout: 15`; every script swallows its own failures and exits 0.
- Commits are signed via plain `git commit`; never bypass signing.

## Tests

- `sh tests/run.sh` runs the POSIX suites (content, dispatch, linux, mac; PATH stubs in `tests/stub/`, fixtures in `tests/fixtures/`). Run under Git Bash, `sh` or `dash`.
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/windows/Run-Tests.ps1` runs the Windows PowerShell 5.1 suite.
- Run both before committing. The mac backend is only tested with PATH stubs (no real-Mac check yet).

## Verified environment

Probed on the Windows PC on 2026-11-22 (plugin installed from a directory marketplace, probe dispatcher logging each call):

- Plugin hooks fire in every session, including sessions that were already open when the plugin was installed (Notification/Stop/clear events all arrive).
- `sh` resolves under the hook runner (Git Bash) and `${CLAUDE_PLUGIN_ROOT}` works inside the quoted command.
- `CLAUDE_CODE_ENTRYPOINT=claude-vscode`, `CLAUDE_CODE_SESSION_ATTENDED=1`, `CLAUDE_PROJECT_DIR` (e.g. `c:/Users/maxa2/claude`: lowercase drive, forward slashes) and `jq` (`/c/Users/maxa2/bin/jq`) all reach the hook process.
- Helper sessions that other plugins spawn (e.g. agent-issue-tracker's session-title generator) inherit `CLAUDE_CODE_ENTRYPOINT=claude-vscode` but report `CLAUDE_CODE_SESSION_ATTENDED=0`. The attended check is what keeps them silent; do not drop it.
- No session lag was observed with `async: true` (the probe itself is fast, so this is not a strict proof).
- Installing needs the CLI (`claude plugin marketplace add <dir>` + `claude plugin install claude-notify@maxdimitrov-claude-notify`); listing the plugin in settings.json alone did not install it.
- Installed from a directory marketplace, the hooks run from the marketplace source directory itself (on this PC: this worktree), not from a copy in the plugin cache. Every saved edit is live in all running sessions at once: keep each file change complete and the tree working between edits (hooks swallow failures, so a half-edited state means missed or wrong notifications, not errors).

## Record format

`scripts/dispatch.sh` hands each backend's `notify` a UTF-8 record on stdin, one `key=value` per line: `event` (permission, question, done, ping), `session`, `entrypoint` (`CLAUDE_CODE_ENTRYPOINT`; only `claude-vscode` gets the click's reveal link), `root` (repo name, worktree suffix cut), `rawroot` (leaf of the uncut dir: the worktree folder), `projectdir` (cut), `title`, `tabtitle`, `line1`, `line2`, `marker` (pending-marker path, empty for done). The header of `scripts/lib/content.sh` is the reference. Clears call `clear <session> <root> <rawroot>`.

Pending markers (`$TMPDIR/claude-notify/<session>.pending`): `ping`, `question[ agent=<id>]`, or `toast[ tool=<Tool>][ agent=<id>]`; `cn_should_clear` in `content.sh` decides which clear event removes which.

