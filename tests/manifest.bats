load helpers

@test "every manifest source exists in the repo" {
  while read -r src dst || [ -n "$src" ]; do
    case "$src" in ''|'#'*) continue ;; esac
    [ -e "$REPO_ROOT/$src" ] || { echo "missing: $src"; return 1; }
  done < "$REPO_ROOT/links.txt"
}

@test "every manifest target is under the home directory" {
  while read -r src dst || [ -n "$src" ]; do
    case "$src" in ''|'#'*) continue ;; esac
    [[ "$dst" == "~/"* ]] || { echo "not under ~: $dst"; return 1; }
  done < "$REPO_ROOT/links.txt"
}
