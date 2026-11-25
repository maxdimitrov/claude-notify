---
name: ping
description: Use when the user asks to be pinged, notified, or told when something is ready or done ("ping me when it's ready", "let me know when the build finishes", "notify me when you're done"), or when a long background job the user is waiting on finishes and the user must act on it. Sends a desktop notification naming this session that stays until the user's next prompt.
---

# Ping the user

claude-notify does not send "done" notifications for turns started by background agents or tasks, so the moment the user is waiting for can pass silently. A ping is the deliberate notification for that moment.

## How

1. Take the base directory the skill loader printed for this skill (the line "Base directory for this skill: ..."). The plugin root is two levels up: `<base directory>/../..`. Use forward slashes; on Windows turn `C:\Users\...\skills\ping` into `C:/Users/.../skills/ping`.
2. Run, from the Bash tool of this session:

   ```
   sh "<base directory>/../../scripts/dispatch.sh" ping "<one-line message saying what is ready>"
   ```

   Example: `sh "C:/Users/me/.claude/plugins/cache/maxdimitrov-claude-notify/claude-notify/0.1.0/skills/ping/../../scripts/dispatch.sh" ping "Tests pass; PR ready for review"`

The notification is titled `Claude needs you`, its first line names the repo and this session's tab, and the second line is your message. It stays until the user's next prompt in this session, and it is silent if the user is already watching this tab. The command prints nothing and always exits 0.

## Rules

- One ping per moment the user must act on. Do not ping for progress, and do not ping again for the same thing.
- Keep the message short and concrete: what is ready, or what the user must do (`Deploy finished; check staging`, `Need your answer on the schema question`).
- Run it from this session's Bash tool, not from a subagent or a separate process: it reads this session's id from the environment to find the tab title and to clear itself later.
- Ping at the end of the turn that finished the work, right before you stop. That turn's own "done" notification is then suppressed, so the user gets one notification, not two.
