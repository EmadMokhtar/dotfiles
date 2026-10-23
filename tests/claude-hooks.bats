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

# queued_for_each <command>... — every command must queue a review.
queued_for_each() {
  local cmd
  for cmd in "$@"; do
    run_hook "$cmd" "$URL"
    queued || { echo "no review queued for: $cmd"; return 1; }
  done
}

# ---- a real gh pr create queues a review -------------------------------------

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

@test "pr hook: gh pr create behind a wrapper command queues a review" {
  queued_for_each \
    'env GH_TOKEN=x gh pr create --fill' \
    'command gh pr create --fill' \
    'timeout 30 gh pr create --fill' \
    'exec gh pr create --fill'
}

@test "pr hook: gh pr create inside bash -c, sh -c or eval queues a review" {
  queued_for_each \
    'bash -c "gh pr create --fill"' \
    "sh -c 'cd x; gh pr create --fill'" \
    'eval "gh pr create --fill"'
}

@test "pr hook: gh -R owner/repo pr create queues a review" {
  queued_for_each 'gh -R o/r pr create --fill' 'gh --repo o/r pr create --fill'
}

@test "pr hook: apostrophes around gh pr create do not hide it" {
  queued_for_each \
    $'# it\'s here\ngh pr create --fill\n# that\'s all' \
    "echo don't; gh pr create --fill; echo can't"
}

@test "pr hook: gh pr create after if ! or VAR=\$( ) queues a review" {
  queued_for_each \
    'if ! gh pr create --fill; then echo no; fi' \
    'GH_TOKEN="$(gh auth token)" gh pr create --fill'
}

@test "pr hook: gh pr create split with a line continuation queues a review" {
  run_hook $'gh pr \\\n  create --fill' "$URL"
  queued
}

@test "pr hook: a here-string (<<<) is not a heredoc" {
  run_hook $'cat <<< "x"\ngh pr create --fill\nx' "$URL"
  queued
}

@test "pr hook: a one-line quoted mention still queues a review (accepted false positive)" {
  # The rule prefers a needless review over a missed one. Text on the same
  # line as gh, pr and create counts, even inside quotes.
  queued_for_each \
    'gh pr edit 9 --body "next: gh pr create for the docs"' \
    "gh pr comment 9 --body 'use \`gh pr create\` next'"
}

# ---- no review -----------------------------------------------------------------

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

@test "pr hook: a heredoc with a non-word tag is stripped" {
  run_hook $'gh pr edit 9 --body-file - <<\'END-OF-TEXT\'\ngh pr create\nEND-OF-TEXT' "$URL"
  [ -z "$output" ]
}

@test "pr hook: the second heredoc on a line is stripped" {
  run_hook $'cat <<A > a; cat <<B > b\nx\nA\ngh pr create\nB' "$URL"
  [ -z "$output" ]
}

@test "pr hook: a <<- heredoc with a tab-indented end tag is stripped" {
  run_hook $'gh pr edit 9 --body-file - <<-EOF\n\tgh pr create\n\tEOF' "$URL"
  [ -z "$output" ]
}
