#!/usr/bin/env bash
# macOS preferences, captured from the baseline machine on 2026-09-17.
# Run alone: bash macos/defaults.sh   (DRY_RUN=1 to print only)
# Log out and back in for keyboard and trackpad changes to fully apply.

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$DOTFILES_ROOT/lib/common.sh"

w() { run_cmd defaults write "$@" || status=1; }
status=0

log_info "Keyboard and text"
w NSGlobalDomain KeyRepeat -int 2                          # fastest key repeat
w NSGlobalDomain InitialKeyRepeat -int 15                  # short delay before repeat
w NSGlobalDomain ApplePressAndHoldEnabled -bool false      # hold a key = repeat, not accent menu
w NSGlobalDomain AppleKeyboardUIMode -int 0                # Tab moves between text fields only
w NSGlobalDomain NSAutomaticCapitalizationEnabled -bool true
w NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool true
w com.apple.HIToolbox AppleFnUsageType -int 2              # Fn/Globe key press: 2 = Show Emoji & Symbols

log_info "Appearance and language"
w NSGlobalDomain AppleInterfaceStyle -string "Dark"
w NSGlobalDomain AppleLanguages -array "en-US" "en-NL" "nl-NL" "ar-NL"
w NSGlobalDomain AppleLocale -string "en_US@rg=nlzzzz"     # US English, Netherlands region formats

log_info "Trackpad"
w NSGlobalDomain com.apple.swipescrolldirection -bool false # "natural" scrolling off
w com.apple.AppleMultitouchTrackpad Clicking -bool true    # tap to click
w com.apple.AppleMultitouchTrackpad TrackpadRightClick -bool true
w com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool false
w com.apple.AppleMultitouchTrackpad Dragging -bool false
w com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true

log_info "Finder"
w com.apple.finder AppleShowAllFiles -bool true            # show hidden files
w com.apple.finder ShowPathbar -bool true
w com.apple.finder ShowStatusBar -bool true
w com.apple.finder FXPreferredViewStyle -string "icnv"     # icon view
w com.apple.finder NewWindowTarget -string "PfHm"          # new windows open at home
w com.apple.finder NewWindowTargetPath -string "file://$HOME/"
w com.apple.finder ShowExternalHardDrivesOnDesktop -bool false
w com.apple.finder ShowHardDrivesOnDesktop -bool false
w com.apple.finder ShowRemovableMediaOnDesktop -bool false
w com.apple.desktopservices DSDontWriteNetworkStores -bool true  # no .DS_Store on network shares

log_info "Dock"
w com.apple.dock autohide -bool true
w com.apple.dock autohide-delay -float 0
w com.apple.dock autohide-time-modifier -float 0
w com.apple.dock tilesize -int 48
w com.apple.dock orientation -string "bottom"
w com.apple.dock show-recents -bool false
w com.apple.dock showhidden -bool true                     # dim hidden apps
w com.apple.dock wvous-br-corner -int 14                   # bottom-right hot corner: Quick Note
w com.apple.dock wvous-br-modifier -int 0
w com.apple.dock wvous-bl-corner -int 0
w com.apple.dock wvous-tr-corner -int 0
w com.apple.dock wvous-tl-corner -int 0

log_info "Windows and menu bar"
w com.apple.WindowManager GloballyEnabled -bool false      # Stage Manager off
w com.apple.WindowManager EnableTilingByEdgeDrag -bool true
w com.apple.menuextra.clock ShowSeconds -bool true
w com.apple.menuextra.clock ShowDate -int 0
w com.apple.ActivityMonitor ShowCategory -int 100          # show all processes

log_info "Restarting Finder, Dock and the menu bar"
for app in Finder Dock SystemUIServer; do
  run_cmd killall "$app" 2>/dev/null || true
done

exit "$status"
