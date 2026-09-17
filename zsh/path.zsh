# PATH entries for interactive shells. A directory is added only if it exists
# and is not already on PATH.

# path_prepend <dir> — put dir first.
path_prepend() {
  [[ -d "$1" ]] || return 0
  case ":$PATH:" in *":$1:"*) return 0 ;; esac
  export PATH="$1:$PATH"
}

# path_append <dir> — put dir last.
path_append() {
  [[ -d "$1" ]] || return 0
  case ":$PATH:" in *":$1:"*) return 0 ;; esac
  export PATH="$PATH:$1"
}

path_prepend "$HOME/.local/bin"
path_prepend "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/postgresql@15/bin"
path_append "$HOME/.lmstudio/bin"
