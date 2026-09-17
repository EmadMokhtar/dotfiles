#!/usr/bin/env bash
# Bootstrap steps, one function each. Requires lib/common.sh and lib/link.sh
# to be sourced first and DOTFILES_ROOT to point at the repository.
# Every function returns non-zero on failure and never exits the shell.

BREW_BIN="${BREW_BIN:-/opt/homebrew/bin/brew}"
INSTALL_EXTRA="${INSTALL_EXTRA:-0}"
HOMEBREW_INSTALLER="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
# Set to 0 in tests: bats itself runs without a tty on stdin.
BOOTSTRAP_REQUIRE_TTY="${BOOTSTRAP_REQUIRE_TTY:-1}"

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
  local status=0 keepalive=""

  # Several casks (docker-desktop, microsoft-office, zoom, ...) call sudo to
  # install. Without a tty sudo cannot ask for a password, and for
  # docker-desktop specifically Homebrew had already removed the existing
  # app (--adopt) before sudo failed, destroying it. Refuse to run instead.
  if [ "$BOOTSTRAP_REQUIRE_TTY" = "1" ] && [ "$DRY_RUN" != "1" ] && [ ! -t 0 ]; then
    log_warn "brew bundle skipped: some casks need sudo and a terminal to ask for your password. Run ./bootstrap.sh from Terminal."
    return 1
  fi

  if [ "$DRY_RUN" != "1" ]; then
    # Ask for the password once up front and keep sudo alive for the whole
    # bundle run, so a cask that needs sudo never fails half-way (Homebrew's
    # --adopt removes the existing app before installing; a late sudo failure
    # would leave the app deleted).
    if ! sudo -v; then
      log_err "sudo authentication failed"
      return 1
    fi
    # Briefly enable job control so this background job gets its own process
    # group: without it, `sleep 60` (or `sudo -n true`) shares the caller's
    # process group, and killing just the subshell's own pid below would
    # orphan whichever of the two is currently running instead of stopping
    # it — leaving it alive for up to 60 more seconds.
    set -m
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 60; done ) >/dev/null 2>&1 &
    keepalive=$!
    set +m
  fi

  # Homebrew >= 6 ignores third-party taps until they are trusted. This is a
  # fallback for whatever the Brewfiles' own `trusted: true` did not cover
  # (e.g. an older Homebrew bundle DSL). Read taps from both Brewfiles so a
  # tap that only brew/Brewfile.extra declares still gets trusted.
  if brew trust --help >/dev/null 2>&1; then
    local tap
    local -a tap_files=("$DOTFILES_ROOT/brew/Brewfile")
    if [ "$INSTALL_EXTRA" = "1" ]; then
      tap_files+=("$DOTFILES_ROOT/brew/Brewfile.extra")
    fi
    while IFS= read -r tap; do
      run_cmd brew trust --taps "$tap" || status=1
    done < <(grep -hE '^tap "' "${tap_files[@]}" | sed -E 's/^tap "([^"]+)".*/\1/')
  fi

  # Homebrew >= 6 fetches/verifies cask downloads concurrently, which makes
  # concurrent DMG mounts collide ("hdiutil: attach failed - Resource busy").
  # Serialise downloads so casks do not race each other.
  run_cmd env HOMEBREW_DOWNLOAD_CONCURRENCY=1 brew bundle --file "$DOTFILES_ROOT/brew/Brewfile" || status=1
  if [ "$INSTALL_EXTRA" = "1" ]; then
    run_cmd env HOMEBREW_DOWNLOAD_CONCURRENCY=1 brew bundle --file "$DOTFILES_ROOT/brew/Brewfile.extra" || status=1
  fi

  # Single exit path: stop the keep-alive loop (if we started one) on both
  # the success and the failure path before returning, so no background
  # process ever outlives this function. Kill the whole process group
  # (negative pid) so whichever of `sudo -n true` / `sleep 60` is currently
  # running dies with it, not just the subshell that spawned it. `wait` on a
  # killed job reports the kill signal (143) as its own exit status; `|| true`
  # stops that from being mistaken for step_brew_bundle's own result under
  # errexit callers (bats runs test bodies with `set -e`, and a bare `wait`
  # failure there would abort the function before it reaches `return
  # "$status"`).
  if [ -n "$keepalive" ]; then
    kill -- "-$keepalive" 2>/dev/null || true
    wait "$keepalive" 2>/dev/null || true
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
    if [ "$DRY_RUN" = "1" ]; then
      printf '  [dry-run] %s\n' "nvm install --lts && nvm alias default 'lts/*' (after brew installs nvm)"
    else
      log_warn "nvm not installed; skipping default Node"
    fi
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
