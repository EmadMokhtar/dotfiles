load helpers

setup() {
  make_sandbox
  export DOTFILES_ROOT="$REPO_ROOT"
  . "$REPO_ROOT/lib/common.sh"
  . "$REPO_ROOT/lib/link.sh"
  . "$REPO_ROOT/lib/steps.sh"
}

@test "step_xcode skips when the tools are installed" {
  stub xcode-select 'exit 0'
  run step_xcode
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip"* ]] || false
  [ "$(calls_matching 'xcode-select --install')" -eq 0 ]
}

@test "step_xcode dry-run prints the install command when tools are missing" {
  stub xcode-select 'case "$1" in -p) exit 2;; esac'
  DRY_RUN=1 run step_xcode
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] xcode-select --install"* ]] || false
}

@test "step_homebrew skips when brew exists" {
  stub brew 'case "$1" in shellenv) echo "export HOMEBREW_TEST=1";; esac'
  BREW_BIN="$STUB_BIN/brew" run step_homebrew
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip"* ]] || false
}

@test "step_homebrew dry-run prints the installer when brew is missing" {
  BREW_BIN="$BATS_TEST_TMPDIR/nope/brew" DRY_RUN=1 run step_homebrew
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] install Homebrew"* ]] || false
}

@test "step_brew_bundle installs the core Brewfile only by default" {
  stub brew
  step_brew_bundle
  [ "$(calls_matching "brew bundle --file $REPO_ROOT/brew/Brewfile$")" -eq 1 ]
  [ "$(calls_matching 'Brewfile.extra')" -eq 0 ]
}

@test "step_brew_bundle also installs Brewfile.extra when INSTALL_EXTRA=1" {
  stub brew
  INSTALL_EXTRA=1 step_brew_bundle
  [ "$(calls_matching 'Brewfile.extra')" -eq 1 ]
}

@test "step_brew_bundle returns 1 when brew bundle fails" {
  stub brew 'exit 1'
  run step_brew_bundle
  [ "$status" -eq 1 ]
}
