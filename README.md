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

- Permission and question toasts clear themselves when the session moves on (you approve, deny or send a prompt).
- It stays silent while you are watching that session's tab in the foreground VS Code window.
- No "done" notification for turns started by background agents.
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

For Claude or agents: when the user asks to be pinged, run this from the session's Bash tool:

```
sh "<plugin root>/scripts/dispatch.sh" ping "message"
```

It shows a `Claude needs you` toast with your message that stays until the user's next prompt in that session. It is silent if the user is already watching that tab.

## Disable / uninstall

```
claude plugin uninstall claude-notify@maxdimitrov-claude-notify
```

or disable it in `/plugin`.

## Logs

- Windows: `%TEMP%\claude-notify\` (`notify.log`, `focus.log`)
- macOS: `$TMPDIR/claude-notify/mac.log`

## Tests

```
sh tests/run.sh
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/windows/Run-Tests.ps1
```

The first runs under Git Bash, `sh` or `dash`; the second is the Windows PowerShell 5.1 suite.

## macOS

Backend: `scripts/mac/` (terminal-notifier, with an `osascript` + `afplay` fallback). Click focuses the project's VS Code window and opens the Claude tab. Silent-while-watching and the click guard read the frontmost window through System Events, which needs Accessibility permission; without it the plugin still notifies and the click still opens the tab (logged as `unguarded` in `${TMPDIR}/claude-notify/mac.log`). Residual risk: without that permission the click cannot confirm the right window is in front, so if VS Code is slow to raise the window the session can open as a duplicate tab in another VS Code window; granting the permission to the app running the hooks enables the check.

Real-Mac check: PENDING (tested only with PATH stubs on Windows). To verify: `brew install terminal-notifier`, set terminal-notifier to Alerts in System Settings > Notifications, trigger a permission prompt, then click the notification from another window.
