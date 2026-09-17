load helpers

@test "Brewfile parses and lists the expected items" {
  run brew bundle list --file "$REPO_ROOT/brew/Brewfile" --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"nvm"* ]] || false
  [[ "$output" == *"visual-studio-code"* ]] || false
  [[ "$output" != *$'\nnode\n'* ]] || false
  # terraform moved to the hashicorp/tap tap; it is no longer in homebrew-core
  [[ "$output" == *"hashicorp/tap/terraform"* ]] || false
  [[ "$output" != *$'\nterraform\n'* ]] || false
  # youtube-music comes from the th-ch/youtube-music tap, not an official
  # cask. `brew bundle list` prints casks by their short name only (never
  # tap-qualified, unlike formulae), so the observable proof is that the tap
  # itself is declared and trusted.
  [[ "$output" == *"th-ch/youtube-music"* ]] || false
  [[ "$output" == *"youtube-music"* ]] || false
}

@test "Brewfile.extra parses" {
  run brew bundle list --file "$REPO_ROOT/brew/Brewfile.extra" --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"reaper"* ]] || false
}
