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

# ---- 4. oh-my-zsh, custom plugins and the powerlevel10k theme ---------------
# Cloned directly (not via the oh-my-zsh installer) so ~/.zshrc is never touched.
step_omz() {
  local custom="$HOME/.oh-my-zsh/custom" status=0
  clone_if_missing https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" || status=1
  clone_if_missing https://github.com/zsh-users/zsh-autosuggestions.git "$custom/plugins/zsh-autosuggestions" || status=1
  clone_if_missing https://github.com/zsh-users/zsh-syntax-highlighting.git "$custom/plugins/zsh-syntax-highlighting" || status=1
  clone_if_missing https://github.com/zsh-users/zsh-completions.git "$custom/plugins/zsh-completions" || status=1
  clone_if_missing https://github.com/TamCore/autoupdate-oh-my-zsh-plugins.git "$custom/plugins/autoupdate" || status=1
  clone_if_missing https://github.com/romkatv/powerlevel10k.git "$custom/themes/powerlevel10k" || status=1
  return "$status"
}

# ---- 5. Version managers: goenv (git clone) and nvm default Node ------------
# pyenv and nvm themselves come from the Brewfile. One LTS Node is installed so
# that tools expecting `node` on PATH work right after bootstrap.
step_version_managers() {
  local status=0 nvm_prefix nvm_sh
  clone_if_missing https://github.com/go-nv/goenv.git "$HOME/.goenv" || status=1
  run_cmd mkdir -p "$HOME/.nvm" || status=1
  nvm_prefix="$(brew --prefix nvm 2>/dev/null)"
  nvm_sh="$nvm_prefix/nvm.sh"
  if [ -z "$nvm_prefix" ] || [ ! -s "$nvm_sh" ]; then
    log_warn "nvm not installed; skipping default Node"
    return "$status"
  fi
  if [ -e "$HOME/.nvm/alias/default" ]; then
    log_skip "nvm default Node already set"
    return "$status"
  fi
  run_cmd bash -c "export NVM_DIR=\"$HOME/.nvm\"; . \"$nvm_sh\"; nvm install --lts && nvm alias default 'lts/*'" || status=1
  return "$status"
}

# ---- 6. Symlinks ---------------------------------------------------------------
step_links() {
  link_manifest "$DOTFILES_ROOT/links.txt" "$DOTFILES_ROOT"
}

# ---- 7. iTerm2: load preferences from the repo -------------------------------
step_iterm2() {
  local folder="$DOTFILES_ROOT/iterm2"
  if [ "$(defaults read com.googlecode.iterm2 PrefsCustomFolder 2>/dev/null)" = "$folder" ] &&
     [ "$(defaults read com.googlecode.iterm2 LoadPrefsFromCustomFolder 2>/dev/null)" = "1" ]; then
    log_skip "iTerm2 already loads preferences from $folder"
    return 0
  fi
  run_cmd defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$folder" || return 1
  run_cmd defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
}

# ---- 8. macOS defaults ----------------------------------------------------------
step_macos() {
  DRY_RUN="$DRY_RUN" bash "$DOTFILES_ROOT/macos/defaults.sh"
}
