#!/usr/bin/env bash
# Shared helpers for bootstrap.sh and the step functions.
# Source this file; do not execute it. Must work on bash 3.2.

# When DRY_RUN=1, run_cmd prints commands instead of executing them.
DRY_RUN="${DRY_RUN:-0}"

# Names of steps that returned non-zero. Filled by run_step.
FAILED_STEPS=()

log_info() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
log_ok()   { printf '\033[32m   ok %s\033[0m\n' "$*"; }
log_skip() { printf '\033[33m skip %s\033[0m\n' "$*"; }
log_warn() { printf '\033[33m warn %s\033[0m\n' "$*" >&2; }
log_err()  { printf '\033[31m fail %s\033[0m\n' "$*" >&2; }

# run_cmd <command...> — execute the command, or print it when DRY_RUN=1.
run_cmd() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '  [dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

# expand_tilde <path> — replace a leading ~ with $HOME.
expand_tilde() {
  # shellcheck disable=SC2088
  case "$1" in
    "~")   printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s\n' "$HOME/${1#\~/}" ;;
    *)     printf '%s\n' "$1" ;;
  esac
}

# run_step <name> <function> — run one bootstrap step and record a failure.
# Never aborts the script; bootstrap.sh prints FAILED_STEPS at the end.
run_step() {
  local name="$1" fn="$2" status
  log_info "$name"
  "$fn"
  status=$?
  if [ "$status" -ne 0 ]; then
    log_err "$name failed (exit $status)"
    FAILED_STEPS+=("$name")
  fi
  return "$status"
}

# clone_if_missing <git-url> <dir> — shallow clone unless <dir> already exists.
clone_if_missing() {
  local url="$1" dir="$2"
  if [ -d "$dir" ]; then
    log_skip "$dir exists"
    return 0
  fi
  run_cmd git clone --depth 1 "$url" "$dir"
}
