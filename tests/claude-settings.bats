load helpers

setup() {
  make_sandbox
  export DOTFILES_ROOT="$REPO_ROOT"
  export BACKUP_DIR="$HOME/.dotfiles-backup/test-run"
  . "$REPO_ROOT/lib/common.sh"
  . "$REPO_ROOT/lib/link.sh"
  . "$REPO_ROOT/lib/steps.sh"
  LIVE="$HOME/.claude/settings.json"
  mkdir -p "$HOME/.claude"
  export CLAUDE_SETTINGS_BASE="$BATS_TEST_TMPDIR/base.json"
  cat > "$CLAUDE_SETTINGS_BASE" <<'EOF'
{
  "model": "sonnet",
  "enabledPlugins": {"a@m": true},
  "hooks": {
    "PostToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "~/.claude/hooks/review.sh", "timeout": 10}]}
    ]
  }
}
EOF
}

# same_json <a> <b> — the two files hold the same JSON value.
same_json() { [ "$(jq -S . "$1")" = "$(jq -S . "$2")" ]; }

@test "claude settings: the repo does not link settings.json any more" {
  run grep -E '^claude/settings\.json' "$REPO_ROOT/links.txt"
  [ "$status" -eq 1 ]
}

@test "claude settings: the real base is portable (no machine paths, no tool hooks)" {
  run grep -E '/Users/|claude-sd|iterm2/cc-status' "$REPO_ROOT/claude/settings.json"
  [ "$status" -eq 1 ]
}

@test "claude settings: creates the live file from the base when it is missing" {
  unset CLAUDE_SETTINGS_BASE
  run step_claude_settings
  [ "$status" -eq 0 ]
  [ -f "$LIVE" ] && [ ! -L "$LIVE" ]
  same_json "$LIVE" "$REPO_ROOT/claude/settings.json"
}

@test "claude settings: replaces an old link to the repo with a regular file" {
  cp "$CLAUDE_SETTINGS_BASE" "$BATS_TEST_TMPDIR/repo-copy.json"
  ln -s "$CLAUDE_SETTINGS_BASE" "$LIVE"
  run step_claude_settings
  [ "$status" -eq 0 ]
  [ -f "$LIVE" ] && [ ! -L "$LIVE" ]
  same_json "$LIVE" "$CLAUDE_SETTINGS_BASE"
  # The repo file behind the old link is not changed.
  cmp -s "$CLAUDE_SETTINGS_BASE" "$BATS_TEST_TMPDIR/repo-copy.json"
}

@test "claude settings: keeps what only the live file has and adds the base" {
  cat > "$LIVE" <<'EOF'
{
  "tui": "fullscreen",
  "enabledPlugins": {"local@m": true},
  "hooks": {
    "PostToolUse": [
      {"matcher": ".*", "hooks": [{"type": "command", "command": "/opt/tool/hook light"}]}
    ]
  }
}
EOF
  run step_claude_settings
  [ "$status" -eq 0 ]
  [ "$(jq -r .tui "$LIVE")" = "fullscreen" ]
  [ "$(jq -r '.enabledPlugins["local@m"]' "$LIVE")" = "true" ]
  [ "$(jq -r '.enabledPlugins["a@m"]' "$LIVE")" = "true" ]
  [ "$(jq -r '[.hooks.PostToolUse[].hooks[0].command] | join(",")' "$LIVE")" = "/opt/tool/hook light,~/.claude/hooks/review.sh" ]
}

@test "claude settings: the base wins for a value both files set, and the log names the key" {
  echo '{"model": "opus"}' > "$LIVE"
  run step_claude_settings
  [ "$status" -eq 0 ]
  [ "$(jq -r .model "$LIVE")" = "sonnet" ]
  [[ "$output" == *"model"* ]] || false
}

@test "claude settings: a hook written with \$HOME is the same as the base's ~ hook" {
  jq --arg c "$HOME/.claude/hooks/review.sh" '.hooks.PostToolUse[0].hooks[0].command = $c' \
    "$CLAUDE_SETTINGS_BASE" > "$LIVE"
  run step_claude_settings
  [ "$status" -eq 0 ]
  [ "$(jq '.hooks.PostToolUse | length' "$LIVE")" -eq 1 ]
}

@test "claude settings: a changed hook in the base replaces the live one, no duplicate" {
  jq '.hooks.PostToolUse[0].hooks[0].timeout = 99' "$CLAUDE_SETTINGS_BASE" > "$LIVE"
  run step_claude_settings
  [ "$status" -eq 0 ]
  [ "$(jq '.hooks.PostToolUse | length' "$LIVE")" -eq 1 ]
  [ "$(jq '.hooks.PostToolUse[0].hooks[0].timeout' "$LIVE")" -eq 10 ]
}

@test "claude settings: backs up the old live file before changing it" {
  echo '{"model": "opus"}' > "$LIVE"
  step_claude_settings
  [ "$(jq -r .model "$BACKUP_DIR/.claude/settings.json")" = "opus" ]
}

@test "claude settings: a second run changes nothing and makes no backup" {
  echo '{"tui": "fullscreen"}' > "$LIVE"
  step_claude_settings
  rm -rf "$BACKUP_DIR"
  cp "$LIVE" "$BATS_TEST_TMPDIR/after-first.json"
  run step_claude_settings
  [ "$status" -eq 0 ]
  [[ "$output" == *"already up to date"* ]] || false
  cmp -s "$LIVE" "$BATS_TEST_TMPDIR/after-first.json"
  [ ! -e "$BACKUP_DIR" ]
}

@test "claude settings: refuses a live file that is not valid JSON and leaves it alone" {
  echo '{"model": "opus",}' > "$LIVE"
  cp "$LIVE" "$BATS_TEST_TMPDIR/broken.json"
  run step_claude_settings
  [ "$status" -ne 0 ]
  cmp -s "$LIVE" "$BATS_TEST_TMPDIR/broken.json"
}

@test "claude settings: dry run reports the change and writes nothing" {
  echo '{"model": "opus"}' > "$LIVE"
  DRY_RUN=1 run step_claude_settings
  [ "$status" -eq 0 ]
  [[ "$output" == *"model"* ]] || false
  [ "$(jq -r .model "$LIVE")" = "opus" ]
  [ ! -e "$BACKUP_DIR" ]
}
