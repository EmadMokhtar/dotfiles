#!/usr/bin/env bash
# Bootstrap steps, one function each. Requires lib/common.sh and lib/link.sh
# to be sourced first and DOTFILES_ROOT to point at the repository.
# Every function returns non-zero on failure and never exits the shell.

BREW_BIN="${BREW_BIN:-/opt/homebrew/bin/brew}"
INSTALL_EXTRA="${INSTALL_EXTRA:-0}"
HOMEBREW_INSTALLER="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

# ---- 1. Xcode Command Line Tools (compilers and git needed by Homebrew) -----
step_xcode() {
  if xcode-select -p >/dev/null 2>&1; then
    log_skip "Xcode Command Line Tools installed"
    return 0
  fi
  run_cmd xcode-select --install || return 1
  [ "$DRY_RUN" = "1" ] && return 0
  log_info "Finish the Command Line Tools dialog; waiting for it..."
  until xcode-select -p >/dev/null 2>&1; do sleep 5; done
}

# ---- 2. Homebrew -------------------------------------------------------------
step_homebrew() {
  if [ -x "$BREW_BIN" ]; then
    log_skip "Homebrew installed at $BREW_BIN"
  elif [ "$DRY_RUN" = "1" ]; then
    printf '  [dry-run] install Homebrew from %s\n' "$HOMEBREW_INSTALLER"
    return 0
  else
    /bin/bash -c "$(curl -fsSL "$HOMEBREW_INSTALLER")" || return 1
  fi
  eval "$("$BREW_BIN" shellenv)"
}

# ---- 3. Packages and apps ----------------------------------------------------
step_brew_bundle() {
  local status=0
  run_cmd brew bundle --file "$DOTFILES_ROOT/brew/Brewfile" || status=1
  if [ "$INSTALL_EXTRA" = "1" ]; then
    run_cmd brew bundle --file "$DOTFILES_ROOT/brew/Brewfile.extra" || status=1
  fi
  return "$status"
}
