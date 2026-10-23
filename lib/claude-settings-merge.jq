# Merge the repo's portable Claude Code settings ($base) into the live
# ~/.claude/settings.json ($live). Called by step_claude_settings:
#   jq -n --slurpfile live L --slurpfile base B --arg home "$HOME" -f this-file
#
# Rules:
# - Objects merge key by key. Keys that only the live file has stay.
# - For any other value both sides set, the base wins.
# - Arrays: a live item is replaced by the base item with the same identity;
#   base items with no match are added at the end. A hook group's identity is
#   its matcher and its commands; any other item's identity is its value.
# - When comparing, a leading "~/" counts as "$home/", so "~/x" and
#   "/Users/me/x" are the same hook command.

def same_form:
  walk(if type == "string" and startswith("~/") then $home + .[1:] else . end);

def identity:
  if type == "object" and has("hooks")
  then {matcher, commands: [.hooks[]?.command]} | same_form
  else same_form
  end;

# position($x) — the index of the first item equal to $x, or null.
def position($x): first(range(length) as $i | select(.[$i] == $x) | $i) // null;

def merge($base):
  if type == "object" and ($base | type) == "object" then
    reduce ($base | keys_unsorted[]) as $k (.;
      .[$k] = (if has($k) then (.[$k] | merge($base[$k])) else $base[$k] end))
  elif type == "array" and ($base | type) == "array" then
    ($base | map(identity)) as $base_ids
    | (map(identity)) as $live_ids
    | map(identity as $id | ($base_ids | position($id)) as $n
          | if $n == null then . else $base[$n] end)
      + [$base[] | select(identity as $id | ($live_ids | position($id)) == null)]
  else $base
  end;

$live[0] | merge($base[0])
