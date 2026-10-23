# Merge the repo's portable Claude Code settings ($base) into the live
# ~/.claude/settings.json ($live), using the base applied last time ($anc) to
# tell a local change from a repo change. Called by step_claude_settings:
#   jq -n --slurpfile live L --slurpfile base B --slurpfile anc A \
#     --arg home "$HOME" -f this-file
# $anc is empty when no base was applied before; then the base wins.
#
# Rules, for each value:
# - Only the live file has it (for example a tool's hooks): it stays.
# - Both have it: if the live value is still the one applied last time, the
#   repo's value is used. If it was changed locally, the local value stays.
# - The repo removed it: it is removed if the live value is still the one
#   applied last time. Otherwise it stays.
# - Only the repo has it: it is added, unless the repo had it last time too,
#   unchanged, and it was deleted locally.
# - Objects are merged key by key with these rules.
# - Arrays are matched item by item. A hook group's identity is its matcher
#   and commands; any other item's identity is its value.
# When comparing, "~/", "$HOME/" and "${HOME}/" at the start of a word count
# as "$home/", so "bash ~/x" and "bash /Users/me/x" are the same command.

def same_form:
  walk(if type == "string"
       then gsub("(?<pre>^|[\\s\"'=:])(?:~|\\$HOME|\\$\\{HOME\\})/"; "\(.pre)\($home)/")
       else . end);

def same($a; $b): ($a | same_form) == ($b | same_form);

def identity:
  if type == "object" and has("hooks")
  then {matcher, commands: [.hooks[]?.command]} | same_form
  else same_form
  end;

# position($x) — the index of the first item equal to $x, or null.
def position($x): first(range(length) as $i | select(.[$i] == $x) | $i) // null;

# merge3($anc; $base) — . is the live value; $anc is null when unknown.
def merge3($anc; $base):
  if type == "object" and ($base | type) == "object" then
    ($anc | if type == "object" then . else {} end) as $a
    | reduce ($base | keys_unsorted[]) as $k (.;
        if has($k) then
          .[$k] |= merge3($a[$k]; $base[$k])
        elif ($a | has($k)) and same($a[$k]; $base[$k]) then
          .                                   # deleted locally, repo unchanged
        else
          .[$k] = $base[$k]
        end)
    | reduce ($a | keys_unsorted[] | select(. as $k | $base | has($k) | not)) as $k (.;
        if has($k) | not then .
        elif same(.[$k]; $a[$k]) then del(.[$k])
        elif (.[$k] | type) == "object" and ($a[$k] | type) == "object" then
          .[$k] |= merge3($a[$k]; {})         # retire what the repo had
        elif (.[$k] | type) == "array" and ($a[$k] | type) == "array" then
          .[$k] |= merge3($a[$k]; [])
        else .
        end)
  elif type == "array" and ($base | type) == "array" then
    ($anc | if type == "array" then . else [] end) as $a
    | ($a | map(identity)) as $a_ids
    | ($base | map(identity)) as $base_ids
    | (map(identity)) as $live_ids
    | [ .[]
        | identity as $id
        | ($base_ids | position($id)) as $nb
        | ($a_ids | position($id)) as $na
        | (if $na == null then false else (same(.; $a[$na]) | not) end) as $changed_here
        | if $nb != null then (if $changed_here then . else $base[$nb] end)
          elif $na != null then (if $changed_here then . else empty end)
          else .
          end ]
      + [ $base[]
          | identity as $id
          | select(($live_ids | position($id)) == null)
          | ($a_ids | position($id)) as $na
          | select($na == null or (same(.; $a[$na]) | not)) ]
  elif $anc != null and (same(.; $anc) | not) then
    .                                         # changed locally: keep it
  else
    $base
  end;

($live[0] // {}) | merge3($anc[0]; $base[0])
