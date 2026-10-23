# Tool initialisation. Every block is skipped when its tool is not installed.

_brew_prefix="${HOMEBREW_PREFIX:-/opt/homebrew}"

# ---- pyenv: Python versions and virtualenvs --------------------------------
# PYENV_ROOT and the shims on PATH are set in zsh/zprofile (login profile);
# only the interactive prompt/completions hooks are set up here.
export PYENV_ROOT="$HOME/.pyenv"
if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init -)"
  if pyenv commands 2>/dev/null | grep -qx virtualenv-init; then
    eval "$(pyenv virtualenv-init -)"
  fi
fi

# ---- goenv: Go versions (installed by git clone in bootstrap) --------------
export GOENV_ROOT="$HOME/.goenv"
if [[ -d "$GOENV_ROOT/bin" ]]; then
  path_prepend "$GOENV_ROOT/bin"
  eval "$(goenv init -)"
  [[ -n "$GOROOT" ]] && path_prepend "$GOROOT/bin"
  [[ -n "$GOPATH" ]] && path_append "$GOPATH/bin"
fi

# ---- nvm: Node versions -----------------------------------------------------
export NVM_DIR="$HOME/.nvm"
[[ -s "$_brew_prefix/opt/nvm/nvm.sh" ]] && source "$_brew_prefix/opt/nvm/nvm.sh"
[[ -s "$_brew_prefix/opt/nvm/etc/bash_completion.d/nvm" ]] && source "$_brew_prefix/opt/nvm/etc/bash_completion.d/nvm"

# ---- autojump: `j <partial dir name>` ---------------------------------------
[[ -f "$_brew_prefix/etc/profile.d/autojump.sh" ]] && source "$_brew_prefix/etc/profile.d/autojump.sh"

# ---- completions -----------------------------------------------------------
[[ -d "$HOME/.docker/completions" ]] && fpath=("$HOME/.docker/completions" $fpath)
autoload -Uz compinit && compinit
autoload -U +X bashcompinit && bashcompinit
command -v terraform >/dev/null 2>&1 && complete -o nospace -C "$(command -v terraform)" terraform

# ---- worktrunk: `wt` git worktree manager ----------------------------------
command -v wt >/dev/null 2>&1 && eval "$(command wt config shell init zsh)"

# ---- Claude Code: secrets from `secret` -------------------------------------
# The GitHub MCP plugin reads ${GITHUB_PERSONAL_ACCESS_TOKEN}. Claude Code signs
# in with ${CLAUDE_CODE_OAUTH_TOKEN} (the subscription). `secret` reads them
# (see ~/.config/secrets/secrets.map) and gives them to this one process only.
# ANTHROPIC_API_KEY is not passed: Claude Code would use it before the OAuth
# token and bill the API account.
# --optional: start claude even when a token cannot be read.
if command -v secret >/dev/null 2>&1; then
  claude() { secret run --optional GITHUB_PERSONAL_ACCESS_TOKEN CLAUDE_CODE_OAUTH_TOKEN -- claude "$@"; }
fi

unset _brew_prefix
