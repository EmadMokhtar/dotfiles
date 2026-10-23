#!/bin/bash
# PostToolUse hook (matcher: Bash): after a Bash call creates a pull request,
# tell Claude to run `/code-review high` on it in a fresh subagent.
#
# It does nothing unless the command runs `gh pr create` AND its output holds
# a pull request URL, so a failed create triggers no review. It only adds a
# note to Claude's context; it never runs a review itself.

input=$(cat)

# A jq program that prints true when the command runs `gh pr create` as a
# command, and false when the words are only text in it (for example in a PR
# body). It is a heuristic, not a shell parser:
# 1. Drop heredoc bodies; keep the rest of the line that starts the heredoc.
#    So `gh pr create` in backticks inside an unquoted heredoc is missed.
# 2. Drop quoted strings. Keep a double-quoted string that holds $( or a
#    backtick, because those run commands.
# 3. Look for `gh pr create` where a command starts: at the beginning, after
#    ; & | ( { ` or a newline, or after if/then/do/else/elif/!, with optional
#    VAR=value words before it.
read -r -d '' runs_gh_pr_create <<'JQ' || true
.tool_input.command // ""
| gsub("<<-?[ \t]*(?<q>[\"']?)(?<tag>[A-Za-z_][A-Za-z0-9_]*)\\k<q>(?<rest>[^\n]*)\n(?:[^\n]*\n)*?[ \t]*\\k<tag>[ \t]*(?=\n|$)"; "<<\(.rest)")
| gsub("(?<s>'[^']*'|\"(?:[^\"\\\\]|\\\\.)*\")"; if (.s | test("\\$\\(|`")) then .s else "''" end)
| test("(?:^|[\n;&|({`])[ \t]*(?:(?:if|then|do|else|elif|!)[ \t]+)?(?:[A-Za-z_][A-Za-z0-9_]*=[^ \t\n;&|]*[ \t]+)*(?:[^ \t\n;&|(){}`'\"]*/)?gh[ \t]+pr[ \t]+create(?=[ \t\n;&|)}`]|$)")
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
