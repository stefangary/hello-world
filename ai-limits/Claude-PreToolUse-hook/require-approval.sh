#!/usr/bin/env bash
# =============================================================================
# require-approval.sh  —  Claude Code PreToolUse gate
#
# Blocks two classes of Bash command until YOU explicitly approve them:
#   1. git state changes:  git add / commit / push  (and a few close cousins)
#   2. test runs:          pytest, npm/yarn/pnpm test, tox, make test, etc.
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
# Approve absolutely everything (escape hatch): CLAUDE_APPROVE_ALL=1
# These are read from the hook process environment, i.e. the environment Claude
# Code itself was launched with. See the "How to approve" notes below.
APPROVE_GIT="${CLAUDE_APPROVE_GIT:-0}"
APPROVE_TESTS="${CLAUDE_APPROVE_TESTS:-0}"
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

# ---- Default: no match, no opinion ------------------------------------------
exit 0
