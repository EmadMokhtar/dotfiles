load helpers

setup() {
  make_sandbox
  export SRC="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$SRC/zsh" "$SRC/claude/skills"
  echo "zshrc content" > "$SRC/zsh/zshrc"
  echo "skill" > "$SRC/claude/skills/SKILL.md"
  export BACKUP_DIR="$HOME/.dotfiles-backup/test-run"
  . "$REPO_ROOT/lib/common.sh"
  . "$REPO_ROOT/lib/link.sh"
}

@test "link_file creates a symlink and parent directories" {
  link_file "$SRC/zsh/zshrc" "$HOME/.config/deep/zshrc"
  [ -L "$HOME/.config/deep/zshrc" ]
  [ "$(readlink "$HOME/.config/deep/zshrc")" = "$SRC/zsh/zshrc" ]
}

@test "link_file backs up an existing regular file" {
  echo "old" > "$HOME/.zshrc"
  link_file "$SRC/zsh/zshrc" "$HOME/.zshrc"
  [ -L "$HOME/.zshrc" ]
  [ "$(cat "$BACKUP_DIR/.zshrc")" = "old" ]
}

@test "link_file backs up an existing symlink that points elsewhere" {
  echo "other" > "$HOME/other"
  ln -s "$HOME/other" "$HOME/.zshrc"
  link_file "$SRC/zsh/zshrc" "$HOME/.zshrc"
  [ "$(readlink "$HOME/.zshrc")" = "$SRC/zsh/zshrc" ]
  [ -L "$BACKUP_DIR/.zshrc" ]
  [ -e "$HOME/other" ]
}

@test "link_file is a no-op when already linked and creates no backup dir" {
  link_file "$SRC/zsh/zshrc" "$HOME/.zshrc"
  run link_file "$SRC/zsh/zshrc" "$HOME/.zshrc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already linked"* ]] || false
  [ ! -d "$BACKUP_DIR" ]
}

@test "link_file links a directory as one symlink" {
  link_file "$SRC/claude/skills" "$HOME/.claude/skills"
  [ -L "$HOME/.claude/skills" ]
  [ -f "$HOME/.claude/skills/SKILL.md" ]
}

@test "link_file fails when the source is missing" {
  run link_file "$SRC/nope" "$HOME/.nope"
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/.nope" ]
}

@test "link_file changes nothing in dry-run" {
  echo "old" > "$HOME/.zshrc"
  DRY_RUN=1
  run link_file "$SRC/zsh/zshrc" "$HOME/.zshrc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] ln -s"* ]] || false
  [ "$(cat "$HOME/.zshrc")" = "old" ]
  [ ! -d "$BACKUP_DIR" ]
}

@test "link_manifest links every entry, skipping comments and blank lines" {
  cat > "$BATS_TEST_TMPDIR/links.txt" <<EOF
# comment line
zsh/zshrc        ~/.zshrc

claude/skills    ~/.claude/skills
EOF
  link_manifest "$BATS_TEST_TMPDIR/links.txt" "$SRC"
  [ "$(readlink "$HOME/.zshrc")" = "$SRC/zsh/zshrc" ]
  [ "$(readlink "$HOME/.claude/skills")" = "$SRC/claude/skills" ]
}

@test "link_manifest returns 1 if any entry fails but links the rest" {
  cat > "$BATS_TEST_TMPDIR/links.txt" <<EOF
missing/file     ~/.missing
zsh/zshrc        ~/.zshrc
EOF
  run link_manifest "$BATS_TEST_TMPDIR/links.txt" "$SRC"
  [ "$status" -eq 1 ]
  [ -L "$HOME/.zshrc" ]
}

@test "link_manifest handles file without trailing newline" {
  printf 'zsh/zshrc ~/.zshrc' > "$BATS_TEST_TMPDIR/links.txt"
  link_manifest "$BATS_TEST_TMPDIR/links.txt" "$SRC"
  [ "$(readlink "$HOME/.zshrc")" = "$SRC/zsh/zshrc" ]
}

@test "link_file fails when parent directory is a regular file" {
  touch "$HOME/.config"
  run link_file "$SRC/zsh/zshrc" "$HOME/.config/x/zshrc"
  [ "$status" -eq 1 ]
}
