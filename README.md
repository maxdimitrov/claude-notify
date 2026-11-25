# claude-notify

A Claude Code plugin that plays a sound and shows a desktop notification naming the session when it needs you or finishes. Clicking it focuses the right VS Code window and Claude tab. Windows and macOS are supported, with a minimal Linux fallback.

## What it does

Three events notify, plus a deliberate `ping`:

| Event | Toast title | Behavior |
| --- | --- | --- |
| Permission prompt | `Claude needs permission` | Stays until acted on |
| Question (elicitation dialog) | `Claude has a question` | Stays until acted on |
| Turn finished | `Claude is done` | Transient (about 25 s on Windows), then sits in the notification center |
| `ping` | `Claude needs you` | Stays until your next prompt in that session |

The first line of every notification is `<repo> - <tab title>` (for example `quant-atelier - Live Account Analysis`); the second line is the message or Claude's last reply, with markdown stripped and truncated. Without a tab title the first line is just `<repo>`.

- Permission and question toasts clear themselves when the session moves on: a permission toast when the tool it asked about runs (for a subagent's prompt, when that subagent's tool runs) or when you send your next prompt; a question toast when you answer it or send a prompt. Denying a permission in the dialog does not clear it right away; it goes on your next prompt or on the session's next use of that tool. (`PermissionDenied` also clears it, but that hook appears to fire for auto-mode classifier denials, not for a manual deny.) A finished turn's done toast replaces it either way.
- It stays silent while you are watching that session's tab in the foreground VS Code window.
- No "done" notification for turns started by background agents, nor for a turn that already sent a `ping`.
- Clicking a notification from a terminal session (not a VS Code Claude tab) focuses the project's VS Code window but does not open the session there, so it never starts a duplicate of a terminal session.
- A worktree opened as its own VS Code window is found by its own folder name; otherwise the repo's window is used.
- Headless and helper sessions (SDK runs, sessions other plugins spawn) never notify.
- Windows also flashes the taskbar entry of the session's window.

## Install

### Windows

Requires Git Bash on PATH (hooks run as `sh ...`) and `jq` (the scripts read the hook JSON and the transcript with it).

```
claude plugin marketplace add maxdimitrov/claude-notify
claude plugin install claude-notify@maxdimitrov-claude-notify
```

Listing the plugin in `settings.json` alone does not install it; use the commands above. The first notification registers the "Claude Code" sender and the `claude-focus:` click handler under `HKCU` automatically, and re-registers them after plugin updates (the plugin path changes with each version).

### macOS

Same two commands, then:

```
brew install terminal-notifier
```

Set terminal-notifier to the Alerts style in System Settings > Notifications so notifications stay on screen (Banners vs Alerts is a per-app setting, so the permission/done difference cannot be made on macOS). Without terminal-notifier it falls back to `osascript` + `afplay`, with no click action. Grant Accessibility/Automation permission for System Events to enable the watching check and the click guard (details in the macOS section below).

### Linux

Uses `notify-send` if present, plus `paplay` or `canberra-gtk-play` for sound. No click action.

## Deliberate ping

The plugin ships a `ping` skill (`skills/ping/SKILL.md`), so Claude finds it on its own when you say "ping me when it's ready" or a long job you are waiting on finishes. The skill derives the plugin root from its base directory and runs `scripts/dispatch.sh ping "<message>"` from the session's Bash tool.

It shows a `Claude needs you` toast with the message that stays until your next prompt in that session, and that turn's own `Claude is done` is skipped. It is silent if you are already watching that tab.

## Disable / uninstall

```
claude plugin uninstall claude-notify@maxdimitrov-claude-notify
```

or disable it in `/plugin`.

## Logs

- Windows: `%TEMP%\claude-notify\` (`notify.log`, `focus.log`)
- macOS: `$TMPDIR/claude-notify/mac.log` (without terminal-notifier, the first notification logs a one-time `hint: claude-notify: terminal-notifier not found ...` line here)

## Tests

```
sh tests/run.sh
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/windows/Run-Tests.ps1
```

The first runs under Git Bash, `sh` or `dash`; the second is the Windows PowerShell 5.1 suite.

## macOS

Backend: `scripts/mac/` (terminal-notifier, with an `osascript` + `afplay` fallback). Click focuses the project's VS Code window and opens the Claude tab. Silent-while-watching and the click guard read the frontmost window through System Events, which needs Accessibility permission; without it the plugin still notifies and the click still opens the tab (logged as `unguarded` in `${TMPDIR}/claude-notify/mac.log`). Residual risk: without that permission the click cannot confirm the right window is in front, so if VS Code is slow to raise the window the session can open as a duplicate tab in another VS Code window; granting the permission to the app running the hooks enables the check. Worktrees on macOS: the click runs `code` on the repo root (the worktree suffix cut), and the watching check and guard accept either the repo or the worktree folder name; a session living in a worktree opened as its own window is therefore not raised in that window by the click.

Real-Mac check: PENDING (tested only with PATH stubs on Windows). To verify: `brew install terminal-notifier`, set terminal-notifier to Alerts in System Settings > Notifications, trigger a permission prompt, then click the notification from another window.
