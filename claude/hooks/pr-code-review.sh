#!/bin/bash
# PostToolUse hook (matcher: Bash): after a Bash call creates a pull request,
# tell Claude to run `/code-review high` on it in a fresh subagent.
#
# It does nothing unless the command ran `gh pr create` AND its output holds
# a pull request URL, so a failed create triggers no review. It only adds a
# note to Claude's context; it never runs a review itself.

input=$(cat)

command=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
case "$command" in
  *"gh pr create"*) ;;
  *) exit 0 ;;
esac

# The PR URL that `gh pr create` prints. The last one wins, in case the
# command printed others first.
output=$(printf '%s' "$input" | jq -r '[.tool_response.stdout?, .tool_response.output?] | map(select(. != null)) | join("\n")')
url=$(printf '%s\n' "$output" | grep -Eo 'https://[^[:space:]]+/pull/[0-9]+' | tail -n 1)
[ -n "$url" ] || exit 0

context="A pull request was just created: ${url}. The user's standing global rule is to code-review every pull request they create. Before ending this turn, invoke the code-review skill with the arguments \"high in subagent with clear context for ${url}\": dispatch a fresh subagent that has none of this conversation's context and reviews only that pull request's diff at high effort, then report its findings with ReportFindings. Do not fix anything unless the user asks."

jq -n --arg context "$context" --arg url "$url" '{
  systemMessage: ("Queued /code-review high for " + $url),
  hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $context}
}'
