load helpers

@test "no secret-looking values anywhere in the repo" {
  cd "$REPO_ROOT"
  # Allowed matches: variable names and documentation, never a value.
  # git grep exits 1 when nothing matches; -I skips binary files;
  # --untracked also scans files not yet committed (ignored files stay excluded).
  # Use base64-encoded pattern to avoid literal secret patterns in source
  local pattern=$(echo "KGdpdGh1Yl9wYXRffGdocF98Z2hvX3xzay1bQS1aYS16MC05XXsyMH18QUtJQVswLTlBLVpdezE2fXxCRUdJTiAoUlNBfE9QRU5TU0gpIFBSSVZBVEUgS0VZfHhveFtiYXByc10tKQo=" | base64 -d | tr -d '\n')
  run git grep --untracked -nIiE "$pattern"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "zed settings contain no personal access token" {
  run grep -c github_personal_access_token "$REPO_ROOT/editors/zed/settings.json"
  [ "$output" = "0" ]
}

@test "claude settings are valid JSON" {
  jq empty "$REPO_ROOT/claude/settings.json"
}
