#!/usr/bin/env bash
# Set up a macOS machine from this repository. Safe to run more than once.
#
#   ./bootstrap.sh [--dry-run] [--extra] [--no-brew] [--no-macos] [--help]
#
# Steps: Xcode CLT -> Homebrew -> brew bundle -> oh-my-zsh -> goenv/nvm ->
#        symlinks -> iTerm2 prefs -> macOS defaults. A failing step is reported
#        at the end; the others still run.

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_ROOT

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [options]

  --dry-run   Print what would happen; change nothing.
  --extra     Also install brew/Brewfile.extra (hardware and audio apps).
  --no-brew   Skip the Homebrew install and `brew bundle`.
  --no-macos  Skip macos/defaults.sh.
  --help      Show this help.
EOF
}

DRY_RUN=0
INSTALL_EXTRA=0
SKIP_BREW=0
SKIP_MACOS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)  DRY_RUN=1 ;;
    --extra)    INSTALL_EXTRA=1 ;;
    --no-brew)  SKIP_BREW=1 ;;
    --no-macos) SKIP_MACOS=1 ;;
    --help|-h)  usage; exit 0 ;;
    *) printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
export DRY_RUN INSTALL_EXTRA

if [ "$(id -u)" = "0" ]; then
  printf 'Do not run bootstrap.sh as root.\n' >&2
  exit 1
fi

# shellcheck source=lib/common.sh
. "$DOTFILES_ROOT/lib/common.sh"
# shellcheck source=lib/link.sh
. "$DOTFILES_ROOT/lib/link.sh"
# shellcheck source=lib/steps.sh
. "$DOTFILES_ROOT/lib/steps.sh"

[ "$DRY_RUN" = "1" ] && log_info "Dry run: nothing will be changed"

run_step "Xcode Command Line Tools" step_xcode
if [ "$SKIP_BREW" = "1" ]; then
  log_skip "Homebrew (--no-brew)"
else
  run_step "Homebrew" step_homebrew
  run_step "Homebrew packages" step_brew_bundle
fi
run_step "oh-my-zsh, plugins and theme" step_omz
run_step "Version managers (goenv, nvm)" step_version_managers
run_step "Symlinks" step_links
run_step "iTerm2 preferences" step_iterm2
if [ "$SKIP_MACOS" = "1" ]; then
  log_skip "macOS defaults (--no-macos)"
else
  run_step "macOS defaults" step_macos
fi

printf '\n'
if [ "${#FAILED_STEPS[@]}" -eq 0 ]; then
  log_ok "All steps finished. Open a new terminal window."
  exit 0
fi
log_err "Failed steps:"
for step in "${FAILED_STEPS[@]}"; do
  printf '  - %s\n' "$step"
done
exit 1
