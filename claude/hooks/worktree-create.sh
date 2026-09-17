#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
NAME=$(echo "$INPUT" | jq -r '.name')

REPO_ROOT="$CLAUDE_PROJECT_DIR"
WORKTREE_DIR="${REPO_ROOT}/.claude/worktrees/${NAME}"
BRANCH="worktree-${NAME}"

# Find the repo's default branch on origin.
DEFAULT_BRANCH=$(git -C "$REPO_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
  | sed 's@^refs/remotes/origin/@@' || true)

if [[ -z "$DEFAULT_BRANCH" ]]; then
  git -C "$REPO_ROOT" remote set-head origin -a >/dev/null
  DEFAULT_BRANCH=$(git -C "$REPO_ROOT" symbolic-ref refs/remotes/origin/HEAD \
    | sed 's@^refs/remotes/origin/@@')
fi

# Update only the remote-tracking ref (origin/<default branch>).
# This never touches your local branch, so it works no matter what
# your main checkout currently has checked out.
git -C "$REPO_ROOT" fetch origin "$DEFAULT_BRANCH"

# Branch the worktree from that remote-tracking ref directly, not
# from the local branch — guarantees the latest commit on origin.
git -C "$REPO_ROOT" worktree add "$WORKTREE_DIR" -b "$BRANCH" "origin/${DEFAULT_BRANCH}"

echo "$WORKTREE_DIR"
