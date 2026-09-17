#!/usr/bin/env bash
# =============================================================================
# require-approval.sh  —  Claude Code PreToolUse gate
#
# Blocks four classes of Bash command until YOU explicitly approve them:
#   1. git state changes:  git add / commit / push  (and a few close cousins)
#   2. test runs:          pytest, npm/yarn/pnpm test, tox, make test, etc.
#   3. pw ssh:             any `pw ssh <cluster> ...` remote-shell invocation
#                          (closes the workaround of piping a gated command,
#                          e.g. a git write, through a remote shell)
#   4. recursive deletes:  rm -rf (or similar) of a shared CONTAINER directory
#                          (e.g. ~/pw, ~/pw/jobs, ~/.claude, ~/, /tmp, /) —
#                          deleting a named child underneath is still allowed
#
# HOW IT BLOCKS: on a match it writes a reason to stderr and exits 2. For a
# PreToolUse hook, exit code 2 blocks the tool call unconditionally — the
# Claude Code docs are explicit that a JSON "permissionDecision":"allow" can't
# override an exit 2, and (unlike the JSON "deny" path, which has a known bug
# when Bash is on the permission allow-list, issue #18312) exit 2 cannot fail
# open. That is why this gate uses exit 2 rather than JSON output.
#
# "APPROVAL" MODEL: this hook makes the gate DENY by default. When you want to
# allow a specific blocked command, you approve it out-of-band by setting an
# environment variable for that one action (see APPROVAL below), then let Claude
# retry. This keeps "approval" in your hands, per-command, with no standing hole.
#
# FAIL-CLOSED: if the input can't be parsed into a command, the hook blocks
# rather than allowing an unchecked command through. A safety gate should err
# toward blocking. jq is used when present; a sed fallback covers hosts without it.
# =============================================================================

set -uo pipefail

# ---- APPROVAL SWITCHES (you set these to allow a blocked action once) -------
# Approve the NEXT git-write:   CLAUDE_APPROVE_GIT=1
# Approve the NEXT test run:    CLAUDE_APPROVE_TESTS=1
# Approve the NEXT pw ssh:      CLAUDE_APPROVE_SSH=1
# Approve the NEXT rm of a protected directory: CLAUDE_APPROVE_RM=1
# Approve absolutely everything (escape hatch): CLAUDE_APPROVE_ALL=1
# These are read from the hook process environment, i.e. the environment Claude
# Code itself was launched with. See the "How to approve" notes below.
APPROVE_GIT="${CLAUDE_APPROVE_GIT:-0}"
APPROVE_TESTS="${CLAUDE_APPROVE_TESTS:-0}"
APPROVE_SSH="${CLAUDE_APPROVE_SSH:-0}"
APPROVE_RM="${CLAUDE_APPROVE_RM:-0}"
APPROVE_ALL="${CLAUDE_APPROVE_ALL:-0}"

if [[ "$APPROVE_ALL" == "1" ]]; then
  exit 0
fi

# ---- Read and parse the event JSON from stdin -------------------------------
input="$(cat)"

# Extract tool_name and the Bash command string. Prefer jq; fall back to a
# tolerant sed/grep extractor when jq isn't installed, so the gate still works
# on hosts without jq. If BOTH extraction paths yield nothing on a non-empty
# input, we treat that as a parse failure and fail closed (block).
extract() { # $1 = jq filter, $2 = python-ish key path for fallback (unused marker)
  printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null
}

if command -v jq >/dev/null 2>&1; then
  tool_name="$(extract '.tool_name')"
  command="$(extract '.tool_input.command')"
else
  # Fallback: extract "tool_name":"..." and "command":"..." with sed.
  # Handles the common case; escaped quotes inside commands are rare in this
  # gate's target commands (git/test invocations).
  tool_name="$(printf '%s' "$input" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  command="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
fi

# Only Bash carries git/test commands. Anything else: no opinion, let it pass.
if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

# If we somehow got no command string, fail closed for Bash specifically.
if [[ -z "$command" ]]; then
  echo "require-approval hook: empty Bash command string; blocking to fail safe." >&2
  exit 2
fi

# Normalize whitespace for easier matching.
norm="$(printf '%s' "$command" | tr '\n' ' ' | tr -s ' ')"

# ---- Rule 1: git state changes ----------------------------------------------
# Match git add / commit / push anywhere in the command (covers `&&` chains and
# leading VAR=val assignments). Deliberately does NOT block read-only git
# (status, log, diff, branch, show) so Claude can still inspect the repo freely.
if printf '%s' "$norm" | grep -qE '(^|[^[:alnum:]_])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+(add|commit|push|merge|rebase|reset|tag|cherry-pick|am|apply|stash[[:space:]]+(push|pop|drop|apply)?)([^[:alnum:]_]|$)'; then
  if [[ "$APPROVE_GIT" == "1" ]]; then
    exit 0
  fi
  {
    echo "BLOCKED (require-approval hook): git state-changing command detected."
    echo "Command: ${norm}"
    echo
    echo "Per the user's standing rule, do NOT run git add/commit/push (or other"
    echo "history-changing git subcommands) without explicit approval. Stop and ask"
    echo "the user to approve. Do not attempt a workaround."
  } >&2
  exit 2
fi

# ---- Rule 2: test runs ------------------------------------------------------
# Match common test entrypoints. Tuned to be specific so it doesn't catch
# unrelated commands that merely contain the substring "test".
if printf '%s' "$norm" | grep -qE '(^|[^[:alnum:]_/])(pytest|py\.test|tox|nox|pw[[:space:]]+workflows[[:space:]]+run)([^[:alnum:]_]|$)' \
   || printf '%s' "$norm" | grep -qE '(^|[^[:alnum:]_])(npm|yarn|pnpm|bun)[[:space:]]+(run[[:space:]]+)?test([^[:alnum:]_]|$)' \
   || printf '%s' "$norm" | grep -qE '(^|[^[:alnum:]_])(make|just)[[:space:]]+[^&|;]*test' \
   || printf '%s' "$norm" | grep -qE '(^|[^[:alnum:]_])(go|cargo)[[:space:]]+test([^[:alnum:]_]|$)' \
   || printf '%s' "$norm" | grep -qE '(^|[^[:alnum:]_])python[0-9.]*[[:space:]]+-m[[:space:]]+(pytest|unittest)([^[:alnum:]_]|$)'; then
  if [[ "$APPROVE_TESTS" == "1" ]]; then
    exit 0
  fi
  {
    echo "BLOCKED (require-approval hook): test-execution command detected."
    echo "Command: ${norm}"
    echo
    echo "Per the user's standing rule, do NOT run tests without explicit approval."
    echo "Stop and ask the user to approve running this test command."
  } >&2
  exit 2
fi

# ---- Rule 3: pw ssh ----------------------------------------------------------
# Match any `pw ssh <cluster> ...` invocation, anywhere in the command (covers
# &&/;/| chains, a path prefix like /usr/local/bin/pw, and leading flags like
# `pw --foo ssh ...`). This closes the workaround of piping a gated command
# through a remote shell, e.g. `pw ssh aws "cd hello-world; git add ."`, to
# route around Rule 1 above. Trailing boundary excludes `-` (not just
# alnum/underscore) so a hypothetical distinct subcommand like `ssh-agent`
# doesn't falsely match plain `ssh`.
if printf '%s' "$norm" | grep -qE '(^|[^[:alnum:]_])pw([[:space:]]+-[^[:space:]]+)*[[:space:]]+ssh([^[:alnum:]_-]|$)'; then
  if [[ "$APPROVE_SSH" == "1" ]]; then
    exit 0
  fi
  {
    echo "BLOCKED (require-approval hook): 'pw ssh' remote-shell command detected."
    echo "Command: ${norm}"
    echo
    echo "Per the user's standing rule, do NOT run 'pw ssh' (it opens a remote"
    echo "shell on a cluster and can be used to run git-writes or other gated"
    echo "commands out of this hook's sight) without explicit approval. Stop and"
    echo "ask the user to approve. Do not attempt a workaround."
  } >&2
  exit 2
fi

# ---- Rule 4: recursive deletes of PROTECTED CONTAINER directories -----------
# Approve the NEXT one with: CLAUDE_APPROVE_RM=1
#
# The failure this prevents: an agent asked to clean up its own artifacts ran
#   rm -rf ~/pw/jobs
# instead of naming the two directories it owned, destroying an unrelated
# workflow's job dir that happened to live under the same parent.
#
# The rule is deliberately narrow: it does NOT block deleting a named CHILD
# (rm -rf ~/pw/jobs/my-run is fine). It blocks deleting the CONTAINER itself,
# which is the shape that takes out other people's data.

# Shared roots that hold artifacts from many runs/tools. Add your own.
PROTECTED_DIRS=(
  "$HOME/pw/jobs"
  "$HOME/pw"
  "$HOME/.claude"
  "$HOME"
  "/tmp"
  "/"
)

if printf '%s' "$norm" | grep -qE '(^|[^[:alnum:]_/])rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+|-[a-zA-Z]+[[:space:]]+-[a-zA-Z]+[[:space:]]+)'; then
  for prot in "${PROTECTED_DIRS[@]}"; do
    # Match the protected path as a COMPLETE argument: a trailing slash or nothing,
    # but not when followed by another path segment (that is a child, and allowed).
    if printf '%s' "$norm" | grep -qE "(^|[[:space:]])[\"']?${prot}/?[\"']?([[:space:]]|$)"; then
      if [[ "$APPROVE_RM" == "1" ]]; then break; fi
      {
        echo "BLOCKED (require-approval hook): recursive delete of a protected directory."
        echo "Command: ${norm}"
        echo "Protected path: ${prot}"
        echo
        echo "This deletes a SHARED container directory, not just your own artifacts."
        echo "Delete the specific subdirectories you created instead, e.g."
        echo "    rm -rf ${prot}/<the-one-you-made>"
        echo "If you really mean the whole directory, the user approves it with"
        echo "CLAUDE_APPROVE_RM=1."
      } >&2
      exit 2
    fi
  done
fi

# ---- Default: no match, no opinion ------------------------------------------
exit 0
