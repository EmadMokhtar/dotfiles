load helpers

setup() {
  make_sandbox
  # shellcheck source=../lib/common.sh
  . "$REPO_ROOT/lib/common.sh"
}

@test "run_cmd executes the command when DRY_RUN is 0" {
  DRY_RUN=0 run_cmd touch "$HOME/made"
  [ -e "$HOME/made" ]
}

@test "run_cmd prints instead of executing when DRY_RUN is 1" {
  DRY_RUN=1
  run run_cmd touch "$HOME/made"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/made" ]
  [[ "$output" == *"[dry-run] touch $HOME/made"* ]] || false
}

@test "run_cmd returns the command's exit status" {
  run run_cmd false
  [ "$status" -eq 1 ]
}

@test "expand_tilde replaces a leading tilde" {
  [ "$(expand_tilde '~/.zshrc')" = "$HOME/.zshrc" ]
  [ "$(expand_tilde '~')" = "$HOME" ]
  [ "$(expand_tilde '/abs/path')" = "/abs/path" ]
  [ "$(expand_tilde 'rel/~/x')" = "rel/~/x" ]
}

@test "run_step records a failing step and keeps going" {
  good() { return 0; }
  bad() { return 1; }
  run_step "good step" good
  run_step "bad step" bad || true
  [ "${#FAILED_STEPS[@]}" -eq 1 ]
  [ "${FAILED_STEPS[0]}" = "bad step" ]
}

@test "run_step returns the step's status" {
  bad() { return 7; }
  run run_step "bad" bad
  [ "$status" -eq 7 ]
  [[ "$output" == *"==> bad"* ]] || false
}

@test "clone_if_missing clones when the directory is absent" {
  stub git 'for a in "$@"; do last="$a"; done; mkdir -p "$last"'
  clone_if_missing https://example.com/repo.git "$HOME/repo"
  [ -d "$HOME/repo" ]
  [ "$(calls_matching 'git clone --depth 1 https://example.com/repo.git')" -eq 1 ]
}

@test "clone_if_missing skips when the directory exists" {
  stub git
  mkdir -p "$HOME/repo"
  run clone_if_missing https://example.com/repo.git "$HOME/repo"
  [ "$status" -eq 0 ]
  [ "$(calls_matching 'git clone')" -eq 0 ]
  [[ "$output" == *"skip"* ]] || false
}
