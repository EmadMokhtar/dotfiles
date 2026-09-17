load helpers

setup() {
  make_sandbox
  # Fake every external command the steps call.
  stub xcode-select 'exit 0'
  stub brew 'case "$*" in "--prefix nvm") exit 1;; shellenv) echo ":";; esac'
  stub git 'for a in "$@"; do last="$a"; done; mkdir -p "$last"'
  stub defaults 'case "$1" in read) exit 1;; esac'
  stub killall
  export BREW_BIN="$STUB_BIN/brew"
  # bats itself runs without a tty on stdin; step_brew_bundle would otherwise
  # refuse to run.
  export BOOTSTRAP_REQUIRE_TTY=0
}

@test "--help prints usage and exits 0" {
  run "$REPO_ROOT/bootstrap.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]] || false
  [[ "$output" == *"--dry-run"* ]] || false
}

@test "unknown flag exits 2" {
  run "$REPO_ROOT/bootstrap.sh" --bogus
  [ "$status" -eq 2 ]
}

@test "--dry-run changes nothing in the sandbox home" {
  run "$REPO_ROOT/bootstrap.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]] || false
  [ ! -e "$HOME/.zshrc" ]
  [ ! -d "$HOME/.oh-my-zsh" ]
  [ ! -d "$HOME/.dotfiles-backup" ]
  [ "$(calls_matching 'defaults write')" -eq 0 ]
}

@test "full run links files, clones repos and is idempotent" {
  echo "old zshrc" > "$HOME/.zshrc"
  run "$REPO_ROOT/bootstrap.sh"
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.zshrc")" = "$REPO_ROOT/zsh/zshrc" ]
  [ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]
  [ -d "$HOME/.goenv" ]
  [ "$(calls_matching "brew bundle --file $REPO_ROOT/brew/Brewfile$")" -eq 1 ]
  [ "$(calls_matching 'Brewfile.extra')" -eq 0 ]
  # trailing space excludes the sibling autohide-delay/autohide-time-modifier keys
  [ "$(calls_matching 'defaults write com.apple.dock autohide ')" -eq 1 ]
  # the old file was backed up, not deleted
  [ "$(cat "$HOME"/.dotfiles-backup/*/.zshrc)" = "old zshrc" ]

  local backups_before; backups_before="$(ls "$HOME/.dotfiles-backup" | wc -l)"
  : > "$CALL_LOG"
  run "$REPO_ROOT/bootstrap.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already linked"* ]] || false
  [ "$(calls_matching 'git clone')" -eq 0 ]
  [ "$(ls "$HOME/.dotfiles-backup" | wc -l)" -eq "$backups_before" ]
}

@test "--extra installs Brewfile.extra and --no-macos skips defaults" {
  run "$REPO_ROOT/bootstrap.sh" --extra --no-macos
  [ "$status" -eq 0 ]
  [ "$(calls_matching 'Brewfile.extra')" -eq 1 ]
  [ "$(calls_matching 'defaults write com.apple')" -eq 0 ]
}

@test "--no-brew skips homebrew steps" {
  run "$REPO_ROOT/bootstrap.sh" --no-brew --no-macos
  [ "$status" -eq 0 ]
  [ "$(calls_matching 'brew bundle')" -eq 0 ]
}

@test "a failing step is reported and the exit code is 1" {
  stub brew 'case "$*" in bundle*) exit 1;; "--prefix nvm") exit 1;; shellenv) echo ":";; esac'
  run "$REPO_ROOT/bootstrap.sh" --no-macos
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed steps:"* ]] || false
  [[ "$output" == *"Homebrew packages"* ]] || false
  # later steps still ran
  [ -L "$HOME/.zshrc" ]
}
