load helpers

setup() { make_sandbox; }

HOOK="$REPO_ROOT/claude/hooks/pr-code-review.sh"
URL="https://github.com/o/r/pull/9"

# run_hook <command> <stdout> — send the hook the JSON that Claude Code sends
# after a Bash call.
run_hook() {
  run bash -c 'jq -n --arg command "$1" --arg stdout "$2" \
    "{tool_input: {command: \$command}, tool_response: {stdout: \$stdout}}" | "$3"' \
    _ "$1" "$2" "$HOOK"
}

queued() { [[ "$output" == *"Queued /code-review high for $URL"* ]]; }

@test "pr hook: a plain gh pr create queues a review" {
  run_hook 'gh pr create --title x --body y' "$URL"
  [ "$status" -eq 0 ]
  queued
}

@test "pr hook: gh pr create after && queues a review" {
  run_hook 'git push -u origin HEAD && gh pr create --fill' "$URL"
  queued
}

@test "pr hook: gh pr create that reads its body from a heredoc queues a review" {
  run_hook $'gh pr create --title x --body-file - <<\'EOF\'\nSome body.\nEOF' "$URL"
  queued
}

@test "pr hook: gh pr create inside \$( ) queues a review" {
  run_hook 'url="$(gh pr create --fill)"; echo "$url"' "$URL"
  queued
}

@test "pr hook: gh pr create after then queues a review" {
  run_hook 'if git push; then gh pr create --fill; fi' "$URL"
  queued
}

@test "pr hook: gh pr create after a quoted \$( ) queues a review" {
  run_hook 'base="$(git branch --show-current)" && gh pr create --title "t"' "$URL"
  queued
}

@test "pr hook: a failed gh pr create (no URL) does nothing" {
  run_hook 'gh pr create --fill' 'error: no commits'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "pr hook: an unrelated command does nothing" {
  run_hook 'ls -la' "$URL"
  [ -z "$output" ]
}

@test "pr hook: gh pr create in a heredoc body does nothing" {
  run_hook $'gh pr edit 9 --body-file - <<\'EOF\'\n- [x] `gh pr create --assignee me` worked\nEOF' "$URL"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "pr hook: gh pr create in a double-quoted argument does nothing" {
  run_hook 'gh pr edit 9 --body "next: gh pr create for the docs"' "$URL"
  [ -z "$output" ]
}

@test "pr hook: gh pr create in a single-quoted argument does nothing" {
  run_hook "gh pr comment 9 --body 'run; gh pr create later'" "$URL#issuecomment-1"
  [ -z "$output" ]
}
