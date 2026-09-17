load helpers

setup() {
  make_sandbox
  export DOTFILES_ROOT="$REPO_ROOT"
  # bats itself runs tests without a tty; disable the tty requirement here so
  # the other step_brew_bundle tests below keep working. The tests that
  # exercise the requirement explicitly re-enable it.
  export BOOTSTRAP_REQUIRE_TTY=0
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
  stub brew 'echo "conc=$HOMEBREW_DOWNLOAD_CONCURRENCY" >> "$CALL_LOG"'
  step_brew_bundle
  [ "$(calls_matching "brew bundle --file $REPO_ROOT/brew/Brewfile$")" -eq 1 ]
  [ "$(calls_matching 'Brewfile.extra')" -eq 0 ]
  [ "$(calls_matching 'conc=1')" -eq 1 ]
}

@test "step_brew_bundle trusts every tap in the Brewfile before bundling" {
  stub brew
  step_brew_bundle
  [ "$(calls_matching 'brew trust --taps anomalyco/tap')" -eq 1 ]
  [ "$(calls_matching 'brew trust --taps')" -eq 4 ]
  local trust_line bundle_line
  trust_line="$(grep -n 'brew trust --taps' "$CALL_LOG" | head -n1 | cut -d: -f1)"
  bundle_line="$(grep -n 'brew bundle --file' "$CALL_LOG" | head -n1 | cut -d: -f1)"
  [ "$trust_line" -lt "$bundle_line" ] || false
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

@test "step_brew_bundle without a tty warns and skips bundle" {
  stub brew
  BOOTSTRAP_REQUIRE_TTY=1 run step_brew_bundle < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"terminal"* ]] || false
  [ "$(calls_matching 'brew bundle')" -eq 0 ]
}

@test "step_brew_bundle dry-run keeps working without a tty" {
  stub brew
  BOOTSTRAP_REQUIRE_TTY=1 DRY_RUN=1 run step_brew_bundle < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] env HOMEBREW_DOWNLOAD_CONCURRENCY=1 brew bundle"* ]] || false
}
