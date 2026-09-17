load helpers

setup() { make_sandbox; }

@test "every zsh file parses" {
  for f in "$REPO_ROOT"/zsh/zshrc "$REPO_ROOT"/zsh/zprofile "$REPO_ROOT"/zsh/*.zsh; do
    zsh -n "$f"
  done
}

@test "zshrc resolves DOTFILES through the symlink and loads without errors" {
  ln -s "$REPO_ROOT/zsh/zshrc" "$HOME/.zshrc"
  run zsh -ic 'echo "DOTFILES=$DOTFILES"; alias vim; type mkd; type path_prepend'
  [ "$status" -eq 0 ]
  [[ "$output" == *"DOTFILES=$REPO_ROOT"* ]] || false
  [[ "$output" == *"vim=nvim"* ]] || false
  [[ "$output" == *"mkd is a shell function"* ]] || false
  [[ "$output" != *"no such file"* ]] || false
  [[ "$output" != *"command not found"* ]] || false
}

@test "path_prepend ignores missing directories and duplicates" {
  # $HOME/bin is created here, before PATH is restricted below: on macOS
  # mkdir lives in /bin, not /usr/bin, so calling it after "PATH=/usr/bin"
  # inside the subshell would itself fail with "command not found".
  mkdir -p "$HOME/bin"
  run zsh -c "
    source '$REPO_ROOT/zsh/path.zsh'
    PATH=/usr/bin
    path_prepend /nonexistent/dir
    path_prepend /usr/bin
    path_prepend '$HOME/bin'
    path_prepend '$HOME/bin'
    echo \$PATH"
  [ "$output" = "$HOME/bin:/usr/bin" ]
}

@test "zprofile only adds directories that exist" {
  run zsh -c "PATH=/usr/bin; source '$REPO_ROOT/zsh/zprofile'; echo \$PATH"
  [[ "$output" != *"Toolbox/scripts"* ]] || [ -d "$HOME/Library/Application Support/JetBrains/Toolbox/scripts" ]
}
