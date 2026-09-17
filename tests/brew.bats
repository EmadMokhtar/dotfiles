load helpers

@test "Brewfile parses and lists the expected items" {
  run brew bundle list --file "$REPO_ROOT/brew/Brewfile" --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"nvm"* ]] || false
  [[ "$output" == *"visual-studio-code"* ]] || false
  [[ "$output" != *$'\nnode\n'* ]] || false
}

@test "Brewfile.extra parses" {
  run brew bundle list --file "$REPO_ROOT/brew/Brewfile.extra" --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"reaper"* ]] || false
}
