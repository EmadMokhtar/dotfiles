load helpers

setup() {
  make_sandbox
  export DOTFILES_ROOT="$REPO_ROOT"
  export BACKUP_DIR="$HOME/.dotfiles-backup/test-run"
  . "$REPO_ROOT/lib/common.sh"
  . "$REPO_ROOT/lib/link.sh"
  . "$REPO_ROOT/lib/steps.sh"
  # git clone stub: create the target directory (last argument)
  stub git 'for a in "$@"; do last="$a"; done; mkdir -p "$last"'
}

@test "step_omz clones oh-my-zsh, four plugins and the theme" {
  step_omz
  [ -d "$HOME/.oh-my-zsh" ]
  for p in zsh-autosuggestions zsh-syntax-highlighting zsh-completions autoupdate; do
    [ -d "$HOME/.oh-my-zsh/custom/plugins/$p" ]
  done
  [ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]
  [ "$(calls_matching 'git clone')" -eq 6 ]
}

@test "step_omz is idempotent" {
  step_omz
  : > "$CALL_LOG"
  step_omz
  [ "$(calls_matching 'git clone')" -eq 0 ]
}

@test "step_version_managers clones goenv and installs the default Node" {
  local prefix="$BATS_TEST_TMPDIR/nvm-prefix"
  mkdir -p "$prefix"
  # fake nvm.sh: defines an nvm function that logs its calls
  printf 'nvm() { printf "nvm %%s\\n" "$*" >> "%s"; }\n' "$CALL_LOG" > "$prefix/nvm.sh"
  stub brew "case \"\$*\" in '--prefix nvm') echo '$prefix';; esac"
  step_version_managers
  [ -d "$HOME/.goenv" ]
  [ -d "$HOME/.nvm" ]
  [ "$(calls_matching 'nvm install --lts')" -eq 1 ]
  [ "$(calls_matching "nvm alias default lts/\*")" -eq 1 ]
}

@test "step_version_managers skips Node install when a default alias exists" {
  local prefix="$BATS_TEST_TMPDIR/nvm-prefix"
  mkdir -p "$prefix" "$HOME/.nvm/alias"
  echo "lts/*" > "$HOME/.nvm/alias/default"
  printf 'nvm() { printf "nvm %%s\\n" "$*" >> "%s"; }\n' "$CALL_LOG" > "$prefix/nvm.sh"
  stub brew "case \"\$*\" in '--prefix nvm') echo '$prefix';; esac"
  run step_version_managers
  [ "$status" -eq 0 ]
  [ "$(calls_matching 'nvm install')" -eq 0 ]
}

@test "step_version_managers warns but succeeds when nvm is not installed" {
  stub brew 'exit 1'
  run step_version_managers
  [ "$status" -eq 0 ]
  [[ "$output" == *"nvm not installed"* ]]
}

@test "step_links links the real manifest into the sandbox home" {
  step_links
  [ "$(readlink "$HOME/.zshrc")" = "$REPO_ROOT/zsh/zshrc" ]
  [ "$(readlink "$HOME/.claude/skills")" = "$REPO_ROOT/claude/skills" ]
  [ "$(readlink "$HOME/.config/git/ignore")" = "$REPO_ROOT/git/ignore" ]
}

@test "step_iterm2 writes both preference keys" {
  stub defaults 'case "$1" in read) exit 1;; esac'
  step_iterm2
  [ "$(calls_matching "defaults write com.googlecode.iterm2 PrefsCustomFolder -string $REPO_ROOT/iterm2")" -eq 1 ]
  [ "$(calls_matching 'defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true')" -eq 1 ]
}

@test "step_iterm2 skips when already configured" {
  stub defaults "case \"\$*\" in *PrefsCustomFolder) echo '$REPO_ROOT/iterm2';; *LoadPrefsFromCustomFolder) echo 1;; esac"
  run step_iterm2
  [[ "$output" == *"skip"* ]]
  [ "$(calls_matching 'defaults write')" -eq 0 ]
}

@test "step_macos runs defaults.sh and passes DRY_RUN through" {
  stub defaults 'exit 99'
  stub killall 'exit 99'
  DRY_RUN=1 run step_macos
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] defaults write com.apple.dock autohide -bool true"* ]]
}
