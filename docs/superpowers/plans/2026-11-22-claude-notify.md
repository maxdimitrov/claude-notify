# claude-notify Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Claude Code plugin that shows a sound + desktop notification naming the session (`<repo> - <tab title>`) when a session needs the user or finishes, and on click focuses the right VS Code window and Claude tab (Windows, macOS), with a minimal Linux fallback.

**Architecture:** `hooks/hooks.json` sends every event to one POSIX `sh` dispatcher. The dispatcher applies the headless guards, builds a normalized UTF-8 record (title, lines, root, session) with `jq`, manages a per-session marker file, and hands the record on stdin to a per-platform backend: PowerShell 5.1 scripts on Windows (port of today's `~/.claude/hooks/notify.ps1` + `focus-session.ps1`), `terminal-notifier`/`osascript` on macOS, `notify-send` on Linux.

**Tech Stack:** POSIX sh + jq (Git Bash on Windows), Windows PowerShell 5.1 + WinRT toasts + Win32 P/Invoke, macOS terminal-notifier/osascript/`code` CLI, Linux notify-send. Tests: plain `sh` assert scripts and plain PowerShell assert scripts (no Pester/bats).

**Spec:** `docs/superpowers/specs/2026-11-22-claude-notify-design.md`

## Global Constraints

- Repo `F:\Claude\Projects\claude-notify`, GitHub `maxdimitrov/claude-notify`, private. Plugin `claude-notify`, marketplace `maxdimitrov-claude-notify`, id `claude-notify@maxdimitrov-claude-notify`, no dependencies. Version starts at `0.1.0`.
- All `.ps1`, `.sh`, `.cmd` files are pure ASCII. Check: `LC_ALL=C grep -rn '[^[:print:][:space:]]' scripts tests hooks` prints nothing.
- Windows toast code runs under `powershell.exe` (5.1), never pwsh. No `Set-StrictMode -Version Latest`.
- Every hook is `async: true`, `timeout: 15`; every script swallows its own failures and exits 0 (a broken notifier never affects a session).
- Titles exactly: `Claude is done`, `Claude needs permission`, `Claude has a question`.
- Line 1: `<repo> - <tab title>` (tab title = latest `customTitle` from `custom-title` transcript entries, else latest `aiTitle` from `ai-title`); just `<repo>` if none.
- Line 2: payload `message` (Notification) or `last_assistant_message` (Stop); whitespace collapsed, markdown stripped, max 180 chars (177 + `...`).
- `<repo>` = leaf of `CLAUDE_PROJECT_DIR`, else payload `cwd`, after cutting any `/.claude/worktrees/<name>` (either slash direction) suffix.
- Headless skip (notify and stop): `CLAUDE_CODE_ENTRYPOINT` matches `sdk*`, or `CLAUDE_CODE_SESSION_ATTENDED` = `0`; Stop also skips when `stop_hook_active` is true.
- Silent while watching: no toast/sound/flash when the foreground window is the session's VS Code window and its title's first segment (minus trailing `.`/`...`) is a prefix of the session's tab title (spec, "Silent while watching").
- Windows: reveal link only when exactly one window matches and it is foreground after a 1000 ms wait. Toast sender "Claude Code" via an AUMID; icon must not be Anthropic's logo.
- Commits signed via normal `git commit`; never `--no-verify` / `--no-gpg-sign`. Work happens on branch `feat/initial` in a worktree; merging to `main` is the user's call.

## Review Focus

- Cyrillic tab titles and messages must render correctly in the Windows toast (Git Bash -> powershell.exe pipe; PS 5.1 default code page is not UTF-8). Test: Task 3 Cyrillic record test; Task 2 Cyrillic transcript fixture.
- Payload text containing XML/shell metacharacters (`<`, `&`, `"`, `'`, backticks, `$(...)`) must neither break the toast XML nor execute anything (macOS `-execute` string). Tests: Task 3 XML escaping test; Task 5 quoting test.
- A transcript with no title entries, or no transcript at all, or `jq` missing: still notify with `<repo>` and a generic line 2. Tests: Task 2 `no_title` and `no_transcript`; Task 2 `no_jq` fallback.
- Plugin update changes `${CLAUDE_PLUGIN_ROOT}` (versioned cache path): registry entries must be re-pointed on the next run. Test: Task 3 re-registration test.
- Clear events fire on every tool call: with no marker present the dispatcher must exit without starting any backend. Test: Task 2 `clear_without_marker`.

---

## File Structure

```
.claude-plugin/plugin.json          plugin manifest (name, version, description)
.claude-plugin/marketplace.json     single-plugin marketplace, source "./"
hooks/hooks.json                    Notification/Stop/PostToolUse/PermissionDenied/UserPromptSubmit -> dispatch.sh
scripts/dispatch.sh                 entry point: guards, record, marker, platform select
scripts/lib/content.sh              pure functions: repo root, tab title, markdown strip, truncate, record build
scripts/windows/Common.ps1          dot-sourced: constants, record parse, toast XML, registry registration, CcWin P/Invoke type
scripts/windows/Notify.ps1          show toast + flash + sound (record on stdin)
scripts/windows/Clear.ps1           remove session toast, stop flash
scripts/windows/Focus.ps1           claude-focus: link handler
scripts/mac/notify.sh, clear.sh, focus.sh
scripts/linux/notify.sh
assets/icon.png                     neutral 256x256 icon
tests/run.sh                        runs all sh tests
tests/test_content.sh, tests/test_dispatch.sh
tests/stub/                         stub platform backend that logs its calls
tests/fixtures/                     payloads (*.json) and transcripts (*.jsonl), incl. Cyrillic
tests/windows/Run-Tests.ps1         plain-PS asserts for Common.ps1
README.md, CHANGELOG.md, CLAUDE.md, .gitattributes
```

**Record format** (dispatcher -> backend, UTF-8, one `key=value` per line, values single-line):

```
event=permission|question|done
session=<session_id>
root=<repo name>
projectdir=<full project dir, native path>
title=<toast title>
tabtitle=<tab title, may be empty>
line1=<repo - tab title>
line2=<message>
```

**Backend contract:** `dispatch.sh` runs `$CLAUDE_NOTIFY_PLATFORM_DIR/notify` with the record on stdin and `$CLAUDE_NOTIFY_PLATFORM_DIR/clear <session> <root>` for clears, where the platform dir defaults per `uname` and is overridable by env `CLAUDE_NOTIFY_PLATFORM_DIR` (tests point it at `tests/stub`). On Windows the "notify"/"clear" entries are small sh shims in `scripts/windows/` that call `powershell.exe`.

---

### Task 1: Repo scaffold, plugin manifests, hooks, and environment probe

**Files:**
- Create: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `hooks/hooks.json`, `scripts/dispatch.sh` (probe version), `.gitattributes`, `CLAUDE.md`, `CHANGELOG.md`, `README.md` (stub)

**Interfaces:**
- Produces: hook commands `sh "${CLAUDE_PLUGIN_ROOT}/scripts/dispatch.sh" notify|stop|clear` with the hook payload on stdin.

- [ ] **Step 1: Create the GitHub repo and push `main`** (docs only): `gh repo create maxdimitrov/claude-notify --private --source F:/Claude/Projects/claude-notify --push` after committing the spec and this plan on `main`. Then create the worktree and branch `feat/initial` (EnterWorktree, rename branch).
- [ ] **Step 2: Write manifests** mirroring `F:/Claude/Projects/agent-issue-tracker/.claude-plugin/` shape: plugin `claude-notify` `0.1.0`, author "Maksim Dimitrov", repository/homepage `https://github.com/maxdimitrov/claude-notify`, license MIT; marketplace name `maxdimitrov-claude-notify`, one plugin with `"source": "./"`.
- [ ] **Step 3: Write `hooks/hooks.json`:** `Notification` (matcher `permission_prompt|elicitation_dialog`) -> `notify`; `Stop` -> `stop`; `PostToolUse`, `PermissionDenied`, `UserPromptSubmit` -> `clear`. Each hook `{"type":"command","command":"sh \"${CLAUDE_PLUGIN_ROOT}/scripts/dispatch.sh\" <arg>","timeout":15,"async":true}`.
- [ ] **Step 4: Probe dispatcher.** `scripts/dispatch.sh` for now only appends one line per call to `${TMPDIR:-${TEMP:-/tmp}}/claude-notify/probe.log`: the arg, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_SESSION_ATTENDED`, `CLAUDE_PROJECT_DIR`, `command -v jq`, and the first 200 chars of stdin.
- [ ] **Step 5: Install locally for the probe.** In `~/.claude/settings.json` add `extraKnownMarketplaces."maxdimitrov-claude-notify" = {"source":{"source":"directory","path":"<worktree path>"}}` and `enabledPlugins."claude-notify@maxdimitrov-claude-notify" = true` (read the file first; merge, don't replace). Ask the user to open `/hooks` (or start a new session) and run one prompt.
- [ ] **Step 6: Verify the probe log** shows `stop` and `clear` lines with entrypoint `claude-vscode`, attended `1`, a non-empty `CLAUDE_PROJECT_DIR`, a jq path, and that the session was not delayed (async honored). If `async` was ignored (session waited), change hook commands to capture stdin and background the dispatcher, and note it in `CLAUDE.md`. Record findings in `CLAUDE.md` under "Verified environment".
- [ ] **Step 7: Commit** `chore: scaffold plugin, hooks and env probe`.

### Task 2: Content library and dispatcher (POSIX)

**Files:**
- Create: `scripts/lib/content.sh`, `tests/test_content.sh`, `tests/test_dispatch.sh`, `tests/run.sh`, `tests/stub/notify`, `tests/stub/clear`, `tests/fixtures/*`
- Modify: `scripts/dispatch.sh` (replace probe)

**Interfaces:**
- Produces (content.sh, sourced, POSIX functions writing to stdout):
  - `cn_repo_root <project_dir_or_cwd>` -> full root path with worktree suffix cut
  - `cn_repo_name <root>` -> leaf name
  - `cn_tab_title <transcript_path>` -> latest customTitle, else aiTitle, else empty (reads at most the last 4 MB)
  - `cn_clean_text <text>` -> whitespace-collapsed, markdown-stripped, truncated to 180
  - `cn_build_record <event> <payload_json>` -> the record (see File Structure)
- Produces (dispatch.sh): marker file `${TMPDIR:-${TEMP:-/tmp}}/claude-notify/<session>.pending`; env override `CLAUDE_NOTIFY_PLATFORM_DIR`.

- [ ] **Step 1: Fixtures.** `tests/fixtures/`: `perm.json` (Notification, `notification_type":"permission_prompt"`, message with `**bold**` and `<tag> & "q"`), `question.json` (`elicitation_dialog`), `stop.json` (`last_assistant_message` 300 chars of markdown incl. a link `[text](http://x)`, a list, a heading), `stop_active.json` (`stop_hook_active: true`), `transcript_titles.jsonl` (ai-title "Old AI", custom-title "Live Account Analysis", ai-title "Newer AI"), `transcript_cyr.jsonl` (custom-title `Анализ на сметка`), `transcript_none.jsonl` (no title lines). Payload `cwd`/`transcript_path` point at fixture paths; one payload uses `cwd` `F:\Claude\Projects\mailroom\.claude\worktrees\foo`.
- [ ] **Step 2: Write failing tests** in `tests/test_content.sh` (tiny `assert_eq name expected actual` helper, non-zero exit on any failure):
  - `cn_repo_root 'F:\Claude\Projects\mailroom\.claude\worktrees\foo'` -> `F:\Claude\Projects\mailroom`; same with forward slashes; `cn_repo_name` of it -> `mailroom`
  - `cn_tab_title transcript_titles.jsonl` -> `Live Account Analysis`; `transcript_cyr.jsonl` -> `Анализ на сметка`; `transcript_none.jsonl` -> empty; missing file -> empty
  - `cn_clean_text '**Bold** and `code` [link](http://x)\n- item'` -> `Bold and code link item`; 300-char input -> length 180 ending `...`
  - `cn_build_record permission perm.json` contains `title=Claude needs permission` and `line1=claude-notify-fixtures - Live Account Analysis` (or the fixture's repo name) and `line2=` with no `**`
  - record from perm.json has `tabtitle=Live Account Analysis`; with transcript_none `tabtitle=` (empty)
  - `no_title`: line1 is just the repo name; `no_transcript`: same; `no_jq`: with `PATH` stripped of jq, record still has the right title and `line1=<repo>` and `line2=` empty or generic
- [ ] **Step 3: Run** `sh tests/run.sh` -> FAIL (functions missing).
- [ ] **Step 4: Implement `scripts/lib/content.sh`** using jq for JSON (`jq -r`), `tail -c 4194304` for the transcript, `sed` for markdown strip. Without jq, extract `session_id`, `cwd`, `notification_type`, `hook_event_name` with `sed` and leave line2 empty.
- [ ] **Step 5: Write failing tests** in `tests/test_dispatch.sh` with `CLAUDE_NOTIFY_PLATFORM_DIR=tests/stub` (stub appends `notify` + its stdin, or `clear <args>`, to `$STUB_LOG`):
  - `notify` with perm.json -> stub got a record with `event=permission`; marker file for the session exists
  - `stop` -> record `event=done`; marker removed
  - `stop` with stop_active.json -> stub not called
  - `CLAUDE_CODE_ENTRYPOINT=sdk-cli` -> stub not called for notify and stop; `CLAUDE_CODE_SESSION_ATTENDED=0` -> same
  - `clear_without_marker` -> stub not called; `clear` with marker -> stub called `clear <session> <root>` and marker removed
- [ ] **Step 6: Implement `scripts/dispatch.sh`:** read stdin once; route by `$1`; guards; select platform dir by `uname -s` (`MINGW*|MSYS*|CYGWIN*` -> `scripts/windows`, `Darwin` -> `scripts/mac`, `Linux` -> `scripts/linux`) unless `CLAUDE_NOTIFY_PLATFORM_DIR` is set; call backend; always `exit 0`.
- [ ] **Step 7: Run** `sh tests/run.sh` -> all PASS; ASCII check on `scripts/` and test scripts (fixtures may contain Cyrillic, they are not scripts).
- [ ] **Step 8: Commit** `feat: content record and dispatcher with guards and markers`.

### Task 3: Windows common library (pure parts, tested)

**Files:**
- Create: `scripts/windows/Common.ps1`, `tests/windows/Run-Tests.ps1`, `assets/icon.png`

**Interfaces:**
- Produces (Common.ps1, dot-sourced):
  - `$CnAppId = 'maxdimitrov.ClaudeNotify'`, `$CnGroup = 'claude-code'`
  - `Read-CnRecord([byte[]]$Bytes) -> hashtable` (UTF-8 decode, split on first `=`)
  - `Read-CnStdinRecord() -> hashtable` (reads raw stdin bytes, calls Read-CnRecord)
  - `New-CnToastXml([hashtable]$Record, [string]$Link) -> string`: permission/question -> `<toast scenario="reminder" activationType="protocol" launch="$Link">` with actions `Go to session` (protocol, `$Link`) and a dismiss action (`activationType="system" arguments="dismiss"`); done -> `duration="long"` with the same launch link and no actions; always `<audio silent="true"/>`; every text XML-escaped
  - `Test-CnWatching([string]$ForegroundTitle, [string]$Root, [string]$TabTitle) -> bool`: true when the title ends with ` - <Root> - Visual Studio Code` (case-insensitive) and its first segment, with a trailing `...` or `.` removed, is non-empty and a case-insensitive prefix of `$TabTitle`; false when `$TabTitle` is empty
  - `Get-CnLink([hashtable]$Record) -> string`: `claude-focus:?root=<urlencoded root>&session=<urlencoded session>`
  - `Register-CnHandlers([string]$PluginRoot, [string]$ClassesKey = 'HKCU:\Software\Classes')`: writes `$ClassesKey\AppUserModelId\$CnAppId` (`DisplayName`=`Claude Code`, `IconUri`=`<PluginRoot>\assets\icon.png`) and `$ClassesKey\claude-focus` (`URL:Claude Code focus`, `URL Protocol`, command `conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<PluginRoot>\scripts\windows\Focus.ps1" "%1"`); rewrites only when a stored value differs
  - `CcWin` type (Add-Type, once per process): `FindAll(string root) -> IntPtr[]`, `Flash(IntPtr)`, `StopFlash(IntPtr)`, `Focus(IntPtr) -> bool`, `Foreground() -> IntPtr`. Port the C# from `~/.claude/hooks/notify.ps1` and `focus-session.ps1` (title match: ends with ` - <root> - Visual Studio Code` or equals `<root> - Visual Studio Code`, case-insensitive; Focus: restore, SetForegroundWindow, AttachThreadInput, Alt tap)

- [ ] **Step 1: Write failing tests** in `tests/windows/Run-Tests.ps1` (helper `Assert-Eq`; exit 1 on any failure):
  - Read-CnRecord of UTF-8 bytes of `line1=x - Анализ на сметка` -> `line1` equals that string exactly
  - New-CnToastXml permission record -> loads as XML; root has `scenario="reminder"`; has an action with content `Go to session`; done record -> `duration="long"`, no `scenario`
  - XML escaping: record with `line2=<b> & "q" 'a'` -> `[xml]` parse succeeds and text node equals the raw string
  - Test-CnWatching: (`Desktop and audio notifi. - claude - Visual Studio Code`, `claude`, `Desktop and audio notifications for input`) -> true; (`Notifications - claude - Visual Studio Code`, `claude`, `Notifications`) -> true; (`notify.ps1 - claude - Visual Studio Code`, `claude`, `Notifications`) -> false; (`Notifications - mailroom - Visual Studio Code`, `claude`, `Notifications`) -> false; empty TabTitle -> false
  - Get-CnLink with root `my repo` -> `claude-focus:?root=my%20repo&session=<id>`
  - Register-CnHandlers with `$ClassesKey='HKCU:\Software\ClaudeNotifyTest\Classes'` and PluginRoot `C:\p\1` -> command contains `C:\p\1\scripts\windows\Focus.ps1`; call again with `C:\p\2` -> command now contains `C:\p\2`; cleanup removes the test key
- [ ] **Step 2: Run** `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/windows/Run-Tests.ps1` -> FAIL.
- [ ] **Step 3: Implement `Common.ps1`.**
- [ ] **Step 4: Run tests** -> PASS. ASCII check.
- [ ] **Step 5: Icon.** Generate a 256x256 PNG with System.Drawing (one-off command, not committed as a script): rounded square, solid color, simple white bell or speech-bubble shape. No Anthropic logo or wordmark. Commit `assets/icon.png`.
- [ ] **Step 6: Commit** `feat(windows): common library, toast xml, registration`.

### Task 4: Windows backend scripts and end-to-end check

**Files:**
- Create: `scripts/windows/notify` (sh shim), `scripts/windows/clear` (sh shim), `scripts/windows/Notify.ps1`, `scripts/windows/Clear.ps1`, `scripts/windows/Focus.ps1`

**Interfaces:**
- Consumes: Common.ps1 (Task 3), record + backend contract (Task 2).
- Produces: `notify` shim = `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w <dir>/Notify.ps1)"` with stdin passed through; `clear` shim passes `-Session <id> -Root <root>` to Clear.ps1.

- [ ] **Step 1: Notify.ps1:** `Read-CnStdinRecord`; if `Test-CnWatching` on the foreground window's title is true, exit 0 before anything else (log `watching` to `%TEMP%\claude-notify
otify.log`); `Register-CnHandlers` with the plugin root (two levels up from `$PSScriptRoot`); show toast under `$CnAppId` with `Tag` = session (truncate to 64 chars), `Group` = `$CnGroup`; flash all `FindAll(root)` matches; play the WAV (permission/question `Windows Notify Messaging.wav`, done `Windows Notify Email.wav`, fallback `SystemSounds.Exclamation`) with `PlaySync`. Each part in its own try/catch.
- [ ] **Step 2: Clear.ps1 `-Session -Root`:** `ToastNotificationManager.History.Remove(tag, $CnGroup, $CnAppId)`; `StopFlash` on matches.
- [ ] **Step 3: Focus.ps1 `"%1"`:** port `~/.claude/hooks/focus-session.ps1` onto Common.ps1; new rule: `FindAll` count 0 -> log + exit; >1 -> focus first, log `ambiguous`, no reveal; 1 -> focus, wait 1000 ms, reveal only if still foreground. Log to `%TEMP%\claude-notify\focus.log`.
- [ ] **Step 4: Pipe test** each event with fixtures through the real dispatcher (`CLAUDE_NOTIFY_PLATFORM_DIR` unset): `sh scripts/dispatch.sh notify < tests/fixtures/perm.json` etc. Expected: exit 0, toast appears with sender "Claude Code" and the icon, Cyrillic fixture renders correctly, no console window flashes. Then `clear` removes the permission toast.
- [ ] **Step 5: ASCII check; commit** `feat(windows): notify, clear and focus backends`.

### Task 5: macOS backend

**Files:**
- Create: `scripts/mac/notify`, `scripts/mac/clear`, `scripts/mac/focus.sh`, `tests/test_mac.sh`

**Interfaces:**
- Consumes: record on stdin (Task 2).
- Produces: `notify` uses `terminal-notifier -title "$title" -subtitle "$line1" -message "$line2" -sound <Glass for done, Ping otherwise> -group "$session" -execute "<focus cmd>"` when `command -v terminal-notifier`; else `osascript` `display notification` + `afplay /System/Library/Sounds/<same>.aiff` and a one-time stderr hint (marker `${TMPDIR}/claude-notify/hint-shown`). Before notifying, if `osascript` can read the frontmost window title (System Events) and the frontmost app is VS Code and the title's first segment (separators ` - ` or ` — `, trailing `.`/`...` removed) is a prefix of `$tabtitle` and another segment equals `$root`, exit silently; if the read fails, notify. `clear <session> <root>` -> `terminal-notifier -remove "$session"`. `focus.sh <projectdir> <session>`: `code "$projectdir"` (fallback `/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code`), `sleep 1`, guard via `osascript -e 'tell application "System Events" to get name of front window of (first process whose frontmost is true)'`: if it succeeds and the name contains `$root` as a ` - `/` — ` separated segment -> open `vscode://anthropic.claude-code/open?session=$session`; if it errors (no Accessibility) -> open the link anyway and log `unguarded`; if it succeeds and does not match -> skip.

- [ ] **Step 1: Write failing tests** `tests/test_mac.sh` with PATH stubs for `terminal-notifier`, `osascript`, `afplay`, `code`, `open` that log argv: record with `line2='$(touch /tmp/pwned) "q" `x`'` -> the `-execute` string, when run through `sh -c`, calls the focus script with the exact projectdir and session and creates no file; without the terminal-notifier stub, `osascript` is called and the hint marker is written once.
- [ ] **Step 2: Run** `sh tests/test_mac.sh` -> FAIL. **Step 3: Implement.** **Step 4: Run** -> PASS (runs on this PC with stubs).
- [ ] **Step 5: Mark unverified:** README "macOS" section lists the real-Mac check (install `brew install terminal-notifier`, set terminal-notifier to Alerts in System Settings > Notifications, click from another window) as pending.
- [ ] **Step 6: ASCII check; commit** `feat(mac): terminal-notifier backend and focus`.

### Task 5b: Background-turn filter and deliberate ping

**Files:**
- Modify: `scripts/lib/content.sh`, `scripts/dispatch.sh`, `tests/test_content.sh`, `tests/test_dispatch.sh`, `tests/fixtures/` (new transcripts), `scripts/windows/Common.ps1` + `tests/windows/Run-Tests.ps1` (title for `ping`), `scripts/mac/notify` (+ its test) and `scripts/linux/notify` if present (treat `ping` like `question`)

**Interfaces:**
- Produces: `cn_turn_origin <transcript_path>` -> last `origin.kind` in the transcript tail (same 4 MB cap), empty if none. `dispatch.sh ping "<message>"`: builds the record from env instead of stdin (session = `CLAUDE_CODE_SESSION_ID`, project dir = `CLAUDE_PROJECT_DIR` else `$PWD`, transcript = newest `*.jsonl` named `<session>.jsonl` under `$HOME/.claude/projects/*/` if found), `event=ping`, `title=Claude needs you`, `line2=<message>` (cleaned like other line2s); writes the marker like permission/question.

- [ ] **Step 1: Fixtures + failing tests.** Transcripts ending in origin `peer`, `task-notification`, `human`, and one with no origin. Tests: `cn_turn_origin` returns each kind / empty; dispatcher `stop` with the peer and task-notification transcripts -> stub not called; with human and with no-origin -> called; `notify` (permission) with the peer transcript -> still called; `ping "ready to test"` with env set -> stub got `event=ping`, `title=Claude needs you`, `line2=ready to test`, marker written; `ping` honors the headless guards.
- [ ] **Step 2: Run** `sh tests/run.sh` -> FAIL. **Step 3: Implement.** Match `"origin":{"kind":"..."}` exactly as Claude Code writes it (no spaces); fail open.
- [ ] **Step 4: Backends treat `ping` like `question`:** Windows `New-CnToastXml` reminder scenario + "Go to session" for `ping` (test), sound as permission; macOS sound as permission (test); Linux urgency critical.
- [ ] **Step 5: Run** both suites -> PASS; ASCII check; commit `feat: skip done for background turns; add deliberate ping`.

### Task 6: Linux backend (minimal)

**Files:**
- Create: `scripts/linux/notify`, `scripts/linux/clear` (no-op, exit 0), extend `tests/run.sh` with a stubbed `notify-send` test

- [ ] **Step 1: Failing test:** stub `notify-send` logs argv; permission record -> args include `-a "Claude Code" -u critical`; done record -> `-u normal`; no `notify-send` on PATH -> exit 0, nothing logged.
- [ ] **Step 2: Implement** `notify-send -a "Claude Code" -u <urgency> "$title" "$line1"$'\n'"$line2"` (POSIX: build the newline with printf); sound via `paplay /usr/share/sounds/freedesktop/stereo/dialog-warning.oga` (permission/question) or `complete.oga` (done) when both exist, else `canberra-gtk-play -i <dialog-warning|complete>` if present.
- [ ] **Step 3: Run** `sh tests/run.sh` -> PASS. **Step 4: Commit** `feat(linux): minimal notify-send backend`.

### Task 7: Docs, cut-over on this PC, and live verification

**Files:**
- Modify: `README.md`, `CHANGELOG.md` (`0.1.0`), `CLAUDE.md`; `~/.claude/settings.json`; delete `~/.claude/hooks/notify.ps1`, `~/.claude/hooks/focus-session.ps1` (claude-config repo)

- [ ] **Step 1: README:** what it does, install on Windows (settings.json marketplace + enabledPlugins; Git Bash and jq required) and macOS (`/plugin marketplace add maxdimitrov/claude-notify`, install, `brew install terminal-notifier`, Alerts style for persistent notifications, residual unguarded-click note), Linux (notify-send), how to disable, logs location.
- [ ] **Step 2: Cut over:** remove the `Notification` and `Stop` entries from `~/.claude/settings.json` (keep everything else), delete the two old scripts; the plugin (still installed from the worktree directory) re-points `HKCU\Software\Classes\claude-focus` on its next run. Commit claude-config: `notify: move to claude-notify plugin`.
- [ ] **Step 3: Live check with the user** (new session or `/hooks`): permission prompt toast stays with "Go to session"; approving in VS Code clears it; done toast shows `<repo> - <tab title>` and disappears after ~25 s; click from another VS Code window focuses window and tab; exactly one notification per event; no console flash. Fix anything found before continuing.
- [ ] **Step 4: Commit** `docs: readme and changelog for 0.1.0`; push `feat/initial`; open a PR to `main`. Merging, and switching the marketplace source in `~/.claude/settings.json` from the worktree directory to `{"source":"github","repo":"maxdimitrov/claude-notify"}`, happen after the user merges.
