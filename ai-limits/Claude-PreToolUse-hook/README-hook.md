# PreToolUse approval gate for Claude Code

A `PreToolUse` hook that **blocks git state-changes (`git add`/`commit`/`push`
and friends), test runs, `pw ssh` remote-shell invocations, and recursive
deletes of shared container directories until you explicitly approve them.**
It is enforced
by the Claude Code client (exit code 2), not merely suggested to the model, so
it holds regardless of what Claude decides to do.

## Why a hook and not CLAUDE.md

Anthropic's docs are explicit: CLAUDE.md is *context, not enforced
configuration* — "no guarantee of strict compliance." To **block an action
regardless of what Claude decides, use a PreToolUse hook.** This gate uses
`exit 2`, which the docs say blocks a `PreToolUse` tool call unconditionally —
even a JSON `"permissionDecision":"allow"` can't override it. (It deliberately
does NOT use the JSON `"deny"` path, which has a known bug where it's silently
ignored when `Bash` is on your permission allow-list — a safety gate must never
fail open.)

## What it blocks / allows

- BLOCKS (exit 2): `git add|commit|push|merge|rebase|reset|tag|cherry-pick|am|apply|stash`,
  test runners: `pytest`, `py.test`, `python -m pytest|unittest`, `npm/yarn/pnpm/bun (run) test`,
  `make/just … test`, `go test`, `cargo test`, `tox`, `nox`, and `pw workflows run`,
  and any `pw ssh <cluster> ...` remote-shell invocation (closes the workaround
  of piping a gated command, e.g. `git add`, through a remote shell to bypass
  the git-write rule above), and `rm -rf` (or similar) of a shared CONTAINER
  directory such as `~/pw`, `~/pw/jobs`, `~/.claude`, `~/`, `/tmp`, or `/`
  (deleting a named child underneath, e.g. `~/pw/jobs/my-run`, is still allowed).
- ALLOWS (exit 0): read-only git (`status`, `log`, `diff`, `branch`, `show`),
  other `pw` subcommands (e.g. `pw status`, `pw jobs`), and everything else
  (ls, cat, pip install, editing files, etc.).
- FAILS CLOSED: if the command can't be parsed, it blocks. Uses `jq` when
  present; falls back to a `sed` extractor when `jq` isn't installed.

## Install (one time)

```bash
mkdir -p ~/.claude/hooks
cp require-approval.sh ~/.claude/hooks/require-approval.sh
chmod +x ~/.claude/hooks/require-approval.sh
```

Then add the hook to your **user-level** settings so it applies to every project
(`~/.claude/settings.json`). Merge the contents of `settings-hook-snippet.json`
into that file. If the file doesn't exist yet, create it with exactly that
snippet. If it already has other keys, add only the `"hooks"` block (or merge
into an existing `"hooks"` block).

> Scope choice: `~/.claude/settings.json` = all your projects, machine-local,
> never committed. Use `.claude/settings.json` inside a repo instead if you want
> the gate committed and shared with the team; use `.claude/settings.local.json`
> for a gitignored per-project copy.

## Load it

Hooks are read at session start, and Claude Code's file watcher also picks up
edits to settings files during a session. So either:
- Start a new Claude Code session, or
- If already running, saving the settings file is normally detected
  automatically. To be certain, restart the session.

## Verify it loaded (do this once after install)

1. **`/hooks`** — opens a read-only browser of configured hooks. You should see
   a `PreToolUse` entry, matcher `Bash`, type `[command]`, source
   `User Settings`, pointing at `require-approval.sh`. This confirms Claude Code
   registered it.
2. **Live test — block path (git).** Ask Claude to run a harmless *blocked*
   command, e.g. "run `git status && git add -n .`" (the `add` triggers the
   gate). You should see the tool call blocked with the reason text from the
   hook. A plain "run `git status`" should NOT be blocked.
3. **Live test — block path (pw ssh).** Ask Claude to run a harmless *blocked*
   command, e.g. "run `pw ssh aws echo hi`". You should see the tool call
   blocked with the pw-ssh reason text from the hook.
4. **Live test — block path (protected rm).** Ask Claude to run a harmless
   *blocked* command, e.g. "run `rm -rf ~/pw`". You should see the tool call
   blocked with the protected-directory reason text from the hook. A plain
   "run `rm -rf ~/pw/jobs/my-run`" should NOT be blocked.
5. **Live test — allow path.** Ask Claude to run `ls`. It should proceed
   normally. This confirms the gate isn't over-blocking.
6. **Watch for a silent-disable notice.** If you ever see
   `Failed with non-blocking status code: … require-approval.sh: No such file
   or directory`, the path in settings is wrong and **the gate is off** — fix
   the path. (A mistyped hook path fails open, so this check matters.)

Optional deeper check: enable debug logging to see exactly when the hook fires
and what it returned (`claude --debug`, or the `InstructionsLoaded`/debug
tooling described in the hooks docs).

## How to approve a blocked command (per-action, no standing hole)

The gate is deny-by-default. When YOU decide to allow a specific blocked action,
approve it by setting an environment variable **for that action**, then let
Claude retry. Options, from narrowest to widest:

- Approve the next git-write only:   export `CLAUDE_APPROVE_GIT=1`
- Approve the next test run only:    export `CLAUDE_APPROVE_TESTS=1`
- Approve the next pw ssh only:      export `CLAUDE_APPROVE_SSH=1`
- Approve the next protected-dir rm only: export `CLAUDE_APPROVE_RM=1`
- Approve everything (escape hatch): export `CLAUDE_APPROVE_ALL=1`

Because the hook reads the environment Claude Code was launched with, the
simplest reliable pattern is: keep the gate on by default (launch Claude Code
with none of these set); when you want to permit, say, a test run, stop Claude
Code and relaunch it with `CLAUDE_APPROVE_TESTS=1 claude`, let the test run,
then relaunch without it to re-arm the gate. This keeps approval an explicit,
deliberate act on your part rather than something Claude can grant itself.

> Note: these env vars intentionally can't be set by Claude from inside a
> blocked Bash call — the gate would block the very command trying to set them,
> and even if exported in a child shell they wouldn't reach the already-running
> hook's parent environment. Approval stays with you.

## Turn it off

- Temporarily, for one launch: `claude --settings '{"disableAllHooks": true}'`.
- Permanently: remove the `PreToolUse` block from your settings file.
