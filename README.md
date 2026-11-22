# claude-notify

A Claude Code plugin that plays a sound and shows a desktop notification naming the session when it needs you or finishes; clicking it focuses the right VS Code window and Claude tab (Windows, macOS, minimal Linux fallback).

## macOS

Backend: `scripts/mac/` (terminal-notifier, with an `osascript` + `afplay` fallback). Click focuses the project's VS Code window and opens the Claude tab. Silent-while-watching and the click guard read the frontmost window through System Events, which needs Accessibility permission; without it the plugin still notifies and the click still opens the tab (logged as `unguarded` in `${TMPDIR}/claude-notify/mac.log`).

Real-Mac check: PENDING (tested only with PATH stubs on Windows). To verify: `brew install terminal-notifier`, set terminal-notifier to Alerts in System Settings > Notifications, trigger a permission prompt, then click the notification from another window.
