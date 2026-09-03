#!/bin/bash
#==============================
# Deploy the PreToolUse hook
# based on the instructions
# in the README.
#==============================

# Optionally install Claude Code
# if working on new VM
#curl -fsSL https://claude.ai/install.sh | bash

mkdir -p ~/.claude/hooks
cp -iv require-approval.sh ~/.claude/hooks/require-approval.sh
chmod +x ~/.claude/hooks/require-approval.sh

# Add hook to user-level settings so it applies to 
# every project (~/.claude/settings.json). Merge the 
# contents of settings-hook-snippet.json into that file.
# If the file doesn't exist yet, create it with exactly 
# that snippet. If it already has other keys, add only 
# the "hooks" block (or merge into an existing "hooks" block).
# ASSUME NO SETTINGS ARE PRESENT
cp -iv settings-hook-snippet.json ~/.claude/settings.json

