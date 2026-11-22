# claude-notify: design

Date: 2026-11-22. Status: draft for approval. Moves to `docs/superpowers/specs/2026-11-22-claude-notify-design.md` in the new repo once approved.

## Intent

Maksim runs many Claude Code sessions at once: six or so VS Code windows on the Windows PC, each with one or more Claude extension tabs, and the same setup (VS Code + Claude extension) on his Macs. When a session needs him, he wants to know at a glance **which** session, and one click should take him straight to it. Today that works on the Windows PC only, as two scripts in `~/.claude/hooks` wired into this PC's `~/.claude/settings.json`. The goal is a Claude Code plugin of its own that gives the same experience on Windows and macOS, with a minimal Linux fallback, installed per machine from its own repo and marketplace.

## Goals

1. A notification with sound when a session needs him: permission prompt, a question (elicitation), or a finished turn.
2. A glance tells which session: repo/folder name plus the tab's title.
3. Clicking takes him to the right VS Code window and the right Claude tab (Windows, macOS).
4. Works on every machine he installs the plugin on, with no per-machine scripting.
5. Replaces the current `~/.claude` setup on this PC with no double notifications.

## Non-goals

- Linux beyond a basic notification + sound (no Linux machine in use yet).
- Terminal / CLI sessions outside VS Code (the click target is always a VS Code window). Notifications themselves still show for them; only click-to-focus assumes VS Code.
- Mobile push (Claude Code's own `inputNeededNotifEnabled` covers that).
- Notifications from headless runs (`claude -p`, scheduled jobs, SDK, tracker loops).

## Anti-goals (failure even if it "works")

- Clicking lands in the wrong window and opens the session as a **duplicate tab** there (two processes on one session). Never send the reveal link unless the right window is confirmed in front.
- Noise: a ping per headless/scheduled run, or two pings for one event.
- Console windows flashing up on click or on each hook run.
- Hook slowing down or blocking the session (hooks run async; failures are swallowed).

## What exists today (Windows, working, to be ported)

`~/.claude/hooks/notify.ps1` and `~/.claude/hooks/focus-session.ps1` (also in the private `claude-config` repo, commits 53e84fd..latest). Behavior verified with the user on 2026-11-22:

- Hooked on `Notification` (matcher `permission_prompt|elicitation_dialog`) and `Stop`, both `async: true`, run via `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...` (Windows PowerShell 5.1, because the WinRT toast types are not loaded in pwsh 7).
- Stop is skipped when `stop_hook_active` is true, when `CLAUDE_CODE_ENTRYPOINT` starts with `sdk`, or when `CLAUDE_CODE_SESSION_ATTENDED` is `0`. (VS Code sessions have `CLAUDE_CODE_ENTRYPOINT=claude-vscode`, `CLAUDE_CODE_SESSION_ATTENDED=1`.)
- Toast via `Windows.UI.Notifications` under the PowerShell AUMID, silent, plus an explicit `System.Media.SoundPlayer` WAV from `C:\Windows\Media` (distinct WAV per event type) so sound plays even when toasts are muted.
- Taskbar flash: `EnumWindows` for a visible window whose title ends in ` - <root> - Visual Studio Code` (or equals `<root> - Visual Studio Code`), then `FlashWindowEx(FLASHW_TRAY | FLASHW_TIMERNOFG)`.
- `<root>` = leaf of `CLAUDE_PROJECT_DIR`, else of payload `cwd`, with any `\.claude\worktrees\<name>` suffix cut off (worktree sessions belong to the primary checkout's window). VS Code titles here are `<session/editor title> - <folder> - Visual Studio Code`.
- Click: the toast uses `activationType="protocol"` with `launch="claude-focus:?root=<root>&session=<session_id>"`. `HKCU\Software\Classes\claude-focus` (self-registered by notify.ps1) runs `conhost.exe --headless powershell.exe ... focus-session.ps1 "%1"`. That script finds the window as above, restores + `SetForegroundWindow` (falls back to `AttachThreadInput`, then a synthetic Alt tap), and only if the window is foreground waits **1000 ms** (400 ms proved too short when coming from another VS Code window: window came up, tab did not change), re-checks foreground, then opens `vscode://anthropic.claude-code/open?session=<id>`. Logs to `%TEMP%\claude-focus.log`.
- The Claude extension (anthropic.claude-code 2.1.330) handles `/open?session=<uuid>` via `primaryEditor.open` -> `createPanel`, which **reveals** an existing panel for that session (verified: no duplicate process), else revives a remembered tab, else opens a new panel. The new-panel path is why the foreground guard matters.

## Decided behavior (from the conversation)

### Notification content, all platforms

- **Title**: `Claude is done` (Stop), `Claude needs permission` (permission_prompt), `Claude has a question` (elicitation_dialog). Nothing else in the title (no folder).
- **First line**: `<repo> - <tab title>`, e.g. `quant-atelier - Live Account Analysis`. Repo = `<root>` as defined above. Tab title = the latest `custom-title` entry (`customTitle`) in the session transcript (payload `transcript_path`), else the latest `ai-title` (`aiTitle`). If no title is found, just `<repo>`.
- **Second line**: for Notification events the payload `message`; for Stop the payload `last_assistant_message`. Whitespace collapsed, **markdown stripped** (`**`, `*`, `_`, backticks, leading `#`/`-`/`>`/list markers, link syntax to link text), truncated to about 180 characters with an ellipsis.

### Duration

- Permission / question: stays on screen until acted on (Claude is blocked).
- Done: transient (about 25 s on Windows), then sits in the notification center.

### Windows

- Port the existing behavior (sound, flash, click-to-focus with guard) unchanged except:
  - New title/lines as above.
  - Permission/question toasts use `scenario="reminder"` with a **"Go to session"** button (protocol activation, same `claude-focus:` link) and a dismiss button. Reminder toasts need at least one button to persist. Done toasts use `duration="long"`.
  - Sender shows **"Claude Code"** instead of "Windows PowerShell": register an AUMID for the user (`HKCU\Software\Classes\AppUserModelId\<id>` with `DisplayName` and `IconUri`) and send toasts under it. Icon: a PNG shipped in the repo, **not Anthropic's logo** (neutral design).
- Per-machine registry entries (AUMID, `claude-focus:` handler) are self-registered on first run **and re-registered whenever the stored command/icon path differs from the current plugin path**: the plugin cache path changes with every plugin version, so a path written once would break after the next update.
- Same headless guards for Stop as today. Notification events in headless runs are not expected; apply the same entrypoint guard to them too.

### macOS

- Notification via `terminal-notifier` (Homebrew) when installed: title, subtitle = first line, message = second line, `-sound` per event type, `-group <session_id>` so a newer notification for the same session replaces the older, and `-execute` running the plugin's mac focus script with the full project path and session id.
- Click: bring the right window forward with the `code` CLI on the full project directory (VS Code focuses the existing window that has that folder open), wait about 1 s, then `open "vscode://anthropic.claude-code/open?session=<id>"`. Guard: if a frontmost-window check is possible without extra permissions, use it; if it needs Accessibility permission, the builder decides whether to skip the check or make it optional, weighing the duplicate-tab anti-goal (see Open for the builder).
- Without `terminal-notifier`: `osascript -e 'display notification ...'` + sound, no click action, and a one-time hint (e.g. in the hook's stderr or a log) that installing `terminal-notifier` enables click-to-focus.
- Duration on macOS is a per-app system setting (Banners vs Alerts) for terminal-notifier, not per notification. Document in the README that setting terminal-notifier to "Alerts" makes notifications stay; the permission/done split cannot be done per notification with terminal-notifier.
- No Dock bounce: an outside process cannot make VS Code's Dock icon bounce. (Correction to what was said in conversation.)

### Linux (minimal)

- `notify-send` if present: app name `Claude Code`, title and lines as above, `--urgency=critical` for permission/question (most desktops keep critical notifications until dismissed), normal for done. Sound via `paplay` or `canberra-gtk-play` if present, else none. No click handling. Silent no-op if `notify-send` is missing.

## Packaging (approach B, chosen)

- New repo `F:\Claude\Projects\claude-notify`, GitHub `maxdimitrov/claude-notify`, **private** (can be made public later; the icon and content must not use Anthropic branding either way).
- Self-contained single-plugin marketplace, same shape as `agent-issue-tracker`: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (marketplace name `maxdimitrov-claude-notify`), `hooks/hooks.json`, scripts under the plugin root.
- One hook entry per event, command pointing at a POSIX `sh` dispatcher via `${CLAUDE_PLUGIN_ROOT}` (the precedent: agent-issue-tracker runs `.sh` hooks on this Windows PC through Git Bash). The dispatcher picks the platform by `uname` (MINGW/MSYS/CYGWIN -> Windows PowerShell script, Darwin -> macOS script, Linux -> Linux script) and passes stdin through.
- Install per machine: add the marketplace and enable the plugin (on this PC via `extraKnownMarketplaces` + `enabledPlugins` in `~/.claude/settings.json`, same as the other two plugins; on each Mac via `/plugin marketplace add` + install). README covers both, plus `brew install terminal-notifier` on Macs.
- Versioning and releases follow the user's existing plugin repos: version in `plugin.json` and `marketplace.json`, CHANGELOG, PRs; commits signed (normal `git commit`).

## Migration on this PC

1. Install the plugin; verify it fires (Notification and Stop) and click-to-focus works from another VS Code window.
2. In the same change window, remove the `Notification` and `Stop` entries from `~/.claude/settings.json` and delete `~/.claude/hooks/notify.ps1` and `~/.claude/hooks/focus-session.ps1` (commit to claude-config), so there are never two notifiers live at once for longer than the verification step.
3. The plugin's re-registration points `HKCU\Software\Classes\claude-focus` at the plugin's script, replacing the old path.

## Settled after the builder check (calls marked [call] are Claude's, for the user to check)

- **Async in plugin hooks**: the hooks schema allows `async` per hook regardless of source (settings or plugin `hooks.json`), so the plugin uses `async: true` like today. [call] The first build task verifies on this PC that `async`, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_SESSION_ATTENDED` and `CLAUDE_PROJECT_DIR` all reach the plugin hook process (log them once); if `async` turns out to be ignored, the dispatcher captures stdin and backgrounds itself.
- **Launch path on Windows**: today's settings hook already runs through Git Bash (Claude Code runs hook commands via Git Bash when present) and shows no console flash, so `sh` dispatcher -> `powershell.exe -NoProfile -ExecutionPolicy Bypass -File` is the same path. [call] Keep it; add `-WindowStyle Hidden` only if a flash shows up in testing.
- **UTF-8**: [call] the PowerShell script reads stdin as UTF-8 explicitly (bytes -> UTF8 decode), not via the console code page, because tab titles and messages are often Cyrillic. Test with a Cyrillic payload.
- **Window match ambiguity**: matching by folder name is kept (existing behavior). [call] If **more than one** VS Code window matches, the click still focuses the first match but **does not send the reveal link** (logs `ambiguous`), so a same-named second checkout can never get a duplicate tab. Flash goes to all matches (harmless).
- **Plugin ids**: plugin `claude-notify`, marketplace `maxdimitrov-claude-notify`, enabled as `claude-notify@maxdimitrov-claude-notify`. No plugin dependencies.
- **macOS / Linux acceptance**: [call] built and checked on this PC as far as possible (shellcheck, fake-payload runs of the dispatcher's platform selection with stubbed commands); the real notification + click flow on a Mac is verified by the user on a Mac afterwards, and the plan marks it "unverified until Mac test". macOS click guard: no Accessibility requirement; rely on `code <full project dir>` + ~1 s delay, and if `osascript` can read the frontmost VS Code window title without prompting, use it as the guard; otherwise document the residual duplicate-tab risk in the README.
- **Toast replacement**: one toast per session at a time: a newer event for a session replaces that session's earlier toast (Windows `Tag`/`Group`, macOS `-group`), as today.
- **Auto-clear stale toasts (user decision, 2026-11-22: yes)**: when the user handles a permission prompt or question inside VS Code, that session's on-screen toast disappears by itself as soon as the session moves on. Triggers: `PostToolUse` (a permission was granted and the tool ran), `PermissionDenied`, and `UserPromptSubmit` (question answered or user typed). Stop already replaces it. Cost control: showing a permission/question toast writes a per-session marker file (temp dir, keyed by session id); the clear hooks are handled by the `sh` dispatcher, which exits immediately unless that marker exists, so PowerShell/osascript only start when a toast is actually up. Clearing: Windows `ToastNotificationManager.History.Remove(tag, group, appId)` under the plugin's AUMID; macOS `terminal-notifier -remove <session_id>`; Linux: not cleared (minimal). Clearing also stops that window's taskbar flash only if it is cheap to do (`FlashWindowEx` with `FLASHW_STOP`); otherwise the flash ends when the window is focused, as today.

- **Silent while watching (user request, 2026-11-22)**: if, at the moment of an event, the foreground window is that session's VS Code window **and** its active tab is that session's tab, show nothing (no toast, sound or flash). The active tab is read from the window title's first segment (`<active tab label> - <root> - Visual Studio Code`); the Claude extension truncates long tab labels (e.g. `Desktop and audio notifi.`), so it matches when the session's tab title starts with the label minus a trailing `.`/`...`. Same window but another tab, another window, or another app: notify as usual. macOS: same rule only when the frontmost window title can be read (Accessibility granted); otherwise always notify. Linux: always notify.
- **No "done" for background turns (user request, 2026-11-22)**: a Stop event pings only when the turn was started by the user. Each user-type transcript entry carries `"origin":{"kind":"<kind>"}`; kinds seen: `human` (the user typed), `peer` (a subagent/background agent reported back), `task-notification` (a background task finished). On Stop, find the last `origin.kind` in the transcript tail; if it is present and not `human`, skip. If no origin entry is found, notify (fail open). Permission prompts and questions always notify regardless of origin.
- **Deliberate ping**: a `ping` event Claude can fire on purpose (e.g. the user said "ping me when it's ready") because the background-turn rule would otherwise silence that moment. Invoked as `sh <plugin>/scripts/dispatch.sh ping "<message>"` with the session's env (session id from `CLAUDE_CODE_SESSION_ID`, project dir from `CLAUDE_PROJECT_DIR`, transcript for the tab title located from them where possible). Title `Claude needs you`; line 1 `<repo> - <tab title>`; line 2 the message; behaves like a permission/question toast (stays until acted on, click-to-focus, auto-clears on the session's next user prompt). The watching rule still applies: if the user is watching that tab, stay silent.

## Constraints

- Windows scripts (`.ps1`, `.sh`, `.cmd`) are **pure ASCII** (Windows PowerShell 5.1 reads BOM-less files as ANSI). Verify with a non-ASCII grep before calling anything done.
- Windows toast code runs under **Windows PowerShell 5.1** (`powershell.exe`), not pwsh.
- No `Set-StrictMode -Version Latest` in the PowerShell scripts.
- Windows hook commands need Git Bash on PATH (true on this PC). If Git Bash is absent, Claude Code runs hook commands through PowerShell and the `sh` dispatcher will not start; the README states this requirement.
- Hooks are `async: true` with a short timeout; every failure is swallowed so a broken notifier never affects a session.
- No secrets involved; nothing is sent off the machine.

## Approaches considered

- **A. Hooks inside the personal-skills plugin.** Already installed on every machine, zero extra setup; but turns a skills plugin into a grab bag. Not chosen.
- **B. Plugin of its own, own repo + marketplace (chosen).** Clean separation, can be shared or published later; costs one more repo and a one-time install per machine.
- **C. Keep it in `~/.claude` per machine.** Rejected: the Macs don't share `~/.claude` (only plugins sync), so every Mac would need manual setup.

## Open for the builder

- Script layout, file names, and how the content-building logic (title lookup, markdown stripping, truncation) is shared or duplicated across the PowerShell and POSIX sides.
- macOS foreground guard: whether a frontmost-window check is feasible without Accessibility permission; if not, whether to rely on `code <dir>` + delay alone (document the residual duplicate-tab risk) or make the check optional when permission is granted.
- Exact sounds per event on macOS/Linux; the AUMID id string; icon design.
- Testing approach: at minimum a fake-payload pipe test per platform script (permission, question, done, headless-skip), the ASCII check, and the manual click-from-another-window check on Windows. Pester or bats only if cheap.
- Whether reading the transcript for the title needs a size cap (transcripts can be large; title entries recur, so reading the tail is likely enough).

## Follow-ups (after 0.1.0)

1. **Answer Claude's multiple-choice questions from the toast (user priority, 2026-11-22).** When Claude asks a question with options (AskUserQuestion), the toast shows one button per option; a click answers the question without opening VS Code. Candidate mechanism: a PreToolUse or PermissionRequest hook on AskUserQuestion that, when the user is not watching the tab, shows the option buttons and waits (bounded, e.g. 2 minutes) for a click delivered through the `claude-focus:`-style link, then returns the answer via `updatedInput` (`answers`); on timeout it returns nothing and the normal dialog appears. Spike first: confirm the hook can supply answers, and see how the VS Code tab behaves while the hook waits.
2. **Quick-reply buttons on "done" and Allow/Deny on permission prompts.** Same waiting-hook pattern (Stop hook returning a continue instruction; PermissionRequest hook returning allow/deny). Lower priority than 1; same spike answers the UX question.
