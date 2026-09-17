load helpers

@test "no secret-looking values anywhere in the repo" {
  cd "$REPO_ROOT"
  # Allowed matches: variable names and documentation, never a value.
  # git grep exits 1 when nothing matches; -I skips binary files;
  # --untracked also scans files not yet committed (ignored files stay excluded).
  # Exclude test file and plan documentation that legitimately contain pattern text for reference.
  run git grep --untracked -nIiE '(github_pat_|gh[posur]_|glpat-|sk-[A-Za-z0-9_-]{20}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30}|BEGIN [A-Z ]*PRIVATE KEY|xox[baprs]-)' -- ':!tests/secrets.bats' ':!docs/superpowers/'
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
