#!/usr/bin/env bash
# Claude Code statusLine command
# Reads JSON from stdin and prints a formatted status line

input=$(cat)

user=$(whoami)
host=$(hostname -s)
dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$dir" ] && dir=$(pwd)
dir_display=$(echo "$dir" | sed "s|$HOME|~|")

model=$(echo "$input" | jq -r '.model.display_name // empty')
repo=$(echo "$input" | jq -r '.workspace.repo | if . then .owner + "/" + .name else empty end')
branch=$(echo "$input" | jq -r '.worktree.branch // empty')

# Git branch (fallback to git command if not in worktree)
if [ -z "$branch" ]; then
  branch=$(git -C "$dir" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

# Context usage
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Build the status line with ANSI colors
# Colors: cyan for user@host, blue for dir, yellow for git, green for model, magenta for context
printf "\033[36m%s@%s\033[0m:\033[34m%s\033[0m" "$user" "$host" "$dir_display"

if [ -n "$repo" ] && [ -n "$branch" ]; then
  printf " \033[33m(%s:%s)\033[0m" "$repo" "$branch"
elif [ -n "$branch" ]; then
  printf " \033[33m(%s)\033[0m" "$branch"
fi

if [ -n "$model" ]; then
  printf " \033[32m[%s]\033[0m" "$model"
fi

if [ -n "$remaining" ]; then
  printf " \033[35mctx:%s%%\033[0m" "$(printf '%.0f' "$remaining")"
fi

echo ""
