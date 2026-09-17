load helpers

setup() {
  make_sandbox
  stub defaults 'echo "defaults must not run in dry-run" >&2; exit 99'
  stub killall 'echo "killall must not run in dry-run" >&2; exit 99'
}

@test "defaults.sh dry-run prints every write and touches nothing" {
  DRY_RUN=1 run bash "$REPO_ROOT/macos/defaults.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] defaults write com.apple.dock autohide -bool true"* ]] || false
  [[ "$output" == *"[dry-run] defaults write NSGlobalDomain KeyRepeat -int 2"* ]] || false
  [[ "$output" == *"[dry-run] defaults write com.apple.finder AppleShowAllFiles -bool true"* ]] || false
  [[ "$output" == *"[dry-run] killall Dock"* ]] || false
  # ControlCenter owns the menu-bar clock on recent macOS and must be
  # restarted too, alongside Finder, Dock and SystemUIServer.
  [[ "$output" == *"[dry-run] killall ControlCenter"* ]] || false
  [ "$(calls_matching 'defaults')" -eq 0 ]
}

@test "defaults.sh calls defaults write when not in dry-run" {
  stub defaults
  stub killall
  DRY_RUN=0 run bash "$REPO_ROOT/macos/defaults.sh"
  [ "$status" -eq 0 ]
  [ "$(calls_matching 'defaults write com.apple.dock tilesize -int 48')" -eq 1 ]
  [ "$(calls_matching 'killall Finder')" -eq 1 ]
  [ "$(calls_matching 'killall ControlCenter')" -eq 1 ]
  [ "$(calls_matching 'killall')" -eq 4 ]
}

@test "defaults.sh returns 1 when defaults write fails" {
  stub defaults 'exit 1'
  stub killall
  DRY_RUN=0 run bash "$REPO_ROOT/macos/defaults.sh"
  [ "$status" -eq 1 ]
}
