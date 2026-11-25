# Changelog

## 0.1.0

- Desktop notifications (sound + toast naming the session as `<repo> - <tab title>`) for permission prompts, questions and finished turns, plus a deliberate `ping`.
- Windows: "Claude Code" sender, persistent reminder toasts with a "Go to session" button, transient done toasts, taskbar flash, self-registered `claude-focus:` click handler that focuses the VS Code window and Claude tab.
- macOS: terminal-notifier backend with `osascript` fallback, click-to-focus, Accessibility-gated watching check and click guard (not yet verified on a real Mac).
- Linux: minimal `notify-send` backend with sound.
- Silent while watching the session's tab; toasts auto-clear when the session moves on (a permission toast only on the asked tool, and the asking subagent's tool, running); no notifications for headless/helper sessions or background-agent turns.
- `ping` skill so Claude finds the deliberate ping on its own; a turn that pinged sends no second done notification.
- A permission toast for an MCP tool (shown as e.g. `Send Email`) now clears when the tool runs, instead of lingering until the next prompt.
- Click from a terminal session focuses the window without opening a duplicate of the session in VS Code; a worktree opened as its own window is found by its folder name (Windows).
