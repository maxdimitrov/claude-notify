# Changelog

## Unreleased

- "Done" only when the session waits on the user: silent while a background agent or command it launched has not reported back (matched by id between the launch's tool result and the `task-notification`), and now sent for the turn that handles the last background result. Turns from peer messages stay silent.
- Turn origin is read from `task-notification` entries that carry fields after `kind` (`producer`, `runId`); before, those were missed and the previous origin was used.
- macOS: notifications carry the Claude icon as their content image, taken from `/Applications/Claude.app` (the plugin's bell without it). The sender icon stays terminal-notifier's: `-appIcon` is ignored on current macOS, and `-sender` would break the click handler.
- Tests: the no-jq and no-terminal-notifier tests hide only that command, so they pass on a real Mac (jq in `/usr/bin`, terminal-notifier from Homebrew).

## 0.1.0

- Desktop notifications (sound + toast naming the session as `<repo> - <tab title>`) for permission prompts, questions and finished turns, plus a deliberate `ping`.
- Windows: "Claude Code" sender, persistent reminder toasts with a "Go to session" button, transient done toasts, taskbar flash, self-registered `claude-focus:` click handler that focuses the VS Code window and Claude tab.
- macOS: terminal-notifier backend with `osascript` fallback, click-to-focus, Accessibility-gated watching check and click guard (not yet verified on a real Mac).
- Linux: minimal `notify-send` backend with sound.
- Silent while watching the session's tab; toasts auto-clear when the session moves on (a permission toast only on the asked tool, and the asking subagent's tool, running); no notifications for headless/helper sessions or background-agent turns.
- `ping` skill so Claude finds the deliberate ping on its own; a turn that pinged sends no second done notification.
- A permission toast for an MCP tool (shown as e.g. `Send Email`) now clears when the tool runs, instead of lingering until the next prompt.
- Click from a terminal session focuses the window without opening a duplicate of the session in VS Code; a worktree opened as its own window is found by its folder name (Windows).
