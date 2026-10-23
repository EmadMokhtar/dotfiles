#!/bin/bash
# PostToolUse hook (matcher: Bash): after a Bash call creates a pull request,
# tell Claude to run `/code-review high` on it in a fresh subagent.
#
# It does nothing unless the command runs `gh pr create` AND its output holds
# a pull request URL, so a failed create triggers no review. It only adds a
# note to Claude's context; it never runs a review itself.

input=$(cat)

# A jq program that prints true when the command looks like it runs
# `gh pr create`. A missed review is worse than a needless one, so the match
# is broad: any line with the words gh, pr and create, in that order. Only
# heredoc bodies are dropped first, because a PR body written with
# `--body-file - <<'EOF'` often mentions the command.
# - `\` at the end of a line joins it to the next line.
# - Every heredoc on a line is found (`<<TAG`, `<<-TAG`, `<<'TAG'`,
#   `<<"TAG"`, any tag text), but not a here-string (`<<<`). Their bodies
#   follow in order; each ends at a line that is only its tag.
# - Text on the same line still counts, even inside quotes, for example
#   `--body "next: gh pr create"`. That queues a needless review.
read -r -d '' runs_gh_pr_create <<'JQ' || true
def heredoc_tags:
  [match("(?<!<)<<(?!<)-?[ \t]*(?:'(?<sq>[^'\n]+)'|\"(?<dq>[^\"\n]+)\"|(?<bare>[^ \t\n;&|<>()'\"`]+))"; "g")
   | [.captures[] | .string | select(. != null)][0]];

.tool_input.command // ""
| gsub("\\\\\n"; " ")
| split("\n")
| reduce .[] as $line ({kept: [], tags: []};
    if (.tags | length) > 0 then
      if ($line | gsub("^[ \t]+|[ \t]+$"; "")) == .tags[0] then .tags |= .[1:] else . end
    else
      .kept += [$line] | .tags += ($line | heredoc_tags)
    end)
| any(.kept[]; test("\\bgh\\b.*\\bpr\\b.*\\bcreate\\b"))
JQ

[ "$(printf '%s' "$input" | jq -r "$runs_gh_pr_create")" = "true" ] || exit 0

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
