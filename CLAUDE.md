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

Probed on the Windows PC on 2026-11-22 (plugin installed from a directory marketplace, probe dispatcher logging each call):

- Plugin hooks fire in every session, including sessions that were already open when the plugin was installed (Notification/Stop/clear events all arrive).
- `sh` resolves under the hook runner (Git Bash) and `${CLAUDE_PLUGIN_ROOT}` works inside the quoted command.
- `CLAUDE_CODE_ENTRYPOINT=claude-vscode`, `CLAUDE_CODE_SESSION_ATTENDED=1`, `CLAUDE_PROJECT_DIR` (e.g. `c:/Users/maxa2/claude`: lowercase drive, forward slashes) and `jq` (`/c/Users/maxa2/bin/jq`) all reach the hook process.
- Helper sessions that other plugins spawn (e.g. agent-issue-tracker's session-title generator) inherit `CLAUDE_CODE_ENTRYPOINT=claude-vscode` but report `CLAUDE_CODE_SESSION_ATTENDED=0`. The attended check is what keeps them silent; do not drop it.
- No session lag was observed with `async: true` (the probe itself is fast, so this is not a strict proof).
- Installing needs the CLI (`claude plugin marketplace add <dir>` + `claude plugin install claude-notify@maxdimitrov-claude-notify`); listing the plugin in settings.json alone did not install it. A directory marketplace is copied into the plugin cache, so changes in the worktree need `claude plugin update` (or reinstall) to take effect.

