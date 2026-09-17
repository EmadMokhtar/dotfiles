# Dotfiles Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A public dotfiles repository whose `./bootstrap.sh` takes a blank macOS machine to this machine's shell, tools, apps, preferences and app configs.

**Architecture:** Plain bash 3.2 scripts. `lib/common.sh` (logging, dry-run, step tracking), `lib/link.sh` (symlinks with backup), `lib/steps.sh` (one function per bootstrap step), `bootstrap.sh` (flag parsing + step order). Content lives in topic folders (`zsh/`, `git/`, `brew/`, `macos/`, `editors/`, `claude/`, `iterm2/`) and `links.txt` says what gets symlinked where.

**Tech Stack:** bash 3.2 (Apple's `/bin/bash`), zsh, Homebrew (`brew bundle`), `defaults`, bats-core (Bash Automated Testing System — a test runner for shell scripts), shellcheck (a linter for shell scripts).

**Spec:** `docs/superpowers/specs/2026-09-17-dotfiles-bootstrap-design.md`

## Global Constraints

- All `.sh` files must run on `/bin/bash` 3.2: no associative arrays, no `${@: -1}`, no `mapfile`, no `|&`.
- No `set -e` in `bootstrap.sh`; every step reports and continues (spec §4, §9).
- Every side-effecting command in steps goes through `run_cmd` so `--dry-run` prints it (spec §9).
- Nothing is ever deleted; existing files are moved to `~/.dotfiles-backup/<YYYYMMDD-HHMMSS>/` (spec §4 step 6).
- No secrets in the repo: no `.ssh`, no history, no tokens. `grep -riE 'token|password|secret|api_key'` over the repo must only hit documented, non-secret lines (spec §8).
- Test helpers must not shadow bats builtins: our helpers are `log_*`, `run_cmd`, `run_step` (bats owns `run` and `skip`).
- Commit messages follow Conventional Commits (user rule).
- All tests run with `bats tests/`; lint with `shellcheck bootstrap.sh lib/*.sh macos/defaults.sh`.

## File map

| Path | Responsibility |
|---|---|
| `bootstrap.sh` | Parse flags, source libs, run steps in order, print summary |
| `lib/common.sh` | `log_info/log_ok/log_skip/log_warn/log_err`, `run_cmd`, `expand_tilde`, `run_step`, `clone_if_missing`, `FAILED_STEPS` |
| `lib/link.sh` | `link_file`, `link_manifest`, `BACKUP_DIR` |
| `lib/steps.sh` | `step_xcode`, `step_homebrew`, `step_brew_bundle`, `step_omz`, `step_version_managers`, `step_links`, `step_iterm2`, `step_macos` |
| `links.txt` | Symlink manifest |
| `zsh/*` | Shell config (spec §5) |
| `git/*` | gitconfig + global ignore |
| `brew/Brewfile`, `brew/Brewfile.extra` | Packages (spec §6) |
| `macos/defaults.sh` | Preferences (spec §7) |
| `editors/zed/settings.json`, `claude/*`, `iterm2/*` | App configs (spec §8) |
| `tests/helpers.bash`, `tests/*.bats` | Tests |
| `README.md` | Usage, flags, manual installs |

Tasks 1–3 build the helpers with TDD. Tasks 4–10 add content (data files; verified by checks, not unit tests). Tasks 11–13 build the steps and entry point with TDD against fake commands. Task 14 is the real run on this machine.

---

### Task 1: Test tooling, repo skeleton, shell baseline capture

**Files:**
- Create: `tests/helpers.bash`
- Create: `.shellcheckrc`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `make_sandbox` (sets `HOME`, `STUB_BIN`, `CALL_LOG`, prepends `STUB_BIN` to `PATH`), `stub <name> [body]` (creates a fake command in `STUB_BIN` that appends `"<name> <args>"` to `CALL_LOG` then runs `body`), `REPO_ROOT`.

- [ ] **Step 1: Install the test tools**

`brew install bats-core shellcheck` — installs the bats test runner and the shellcheck linter.

```bash
brew install bats-core shellcheck && bats --version && shellcheck --version | head -2
```
Expected: `Bats 1.14.0` (or newer) and a shellcheck version line.

- [ ] **Step 2: Capture today's shell state for the regression check in Task 14**

This must happen before anything replaces `~/.zshrc`. Only names are captured, never values (the environment contains a GitHub token).

```bash
mkdir -p ~/.dotfiles-backup/baseline
zsh -lic 'alias' | sort > ~/.dotfiles-backup/baseline/aliases.txt
zsh -lic 'print -l ${(k)functions}' | sort > ~/.dotfiles-backup/baseline/functions.txt
zsh -lic 'print -l ${(s.:.)PATH}' > ~/.dotfiles-backup/baseline/path.txt
zsh -lic 'env' | cut -d= -f1 | sort > ~/.dotfiles-backup/baseline/env-names.txt
wc -l ~/.dotfiles-backup/baseline/*.txt
```
Expected: four files with non-zero line counts.

- [ ] **Step 3: Write the test helper**

`tests/helpers.bash`:
```bash
# Shared setup for bats tests. Each .bats file does `load helpers`.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export REPO_ROOT

# make_sandbox — give the test its own HOME and a directory of fake commands.
make_sandbox() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export STUB_BIN="$BATS_TEST_TMPDIR/bin"
  export CALL_LOG="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$HOME" "$STUB_BIN"
  : > "$CALL_LOG"
  export PATH="$STUB_BIN:$PATH"
}

# stub <name> [body...] — create a fake command that records "<name> <args>"
# in CALL_LOG and then runs <body> (default: nothing, exit 0).
stub() {
  local name="$1"; shift
  local body="${*:-:}"
  cat > "$STUB_BIN/$name" <<EOF
#!/bin/bash
printf '%s %s\n' "$name" "\$*" >> "$CALL_LOG"
$body
EOF
  chmod +x "$STUB_BIN/$name"
}

# calls_matching <pattern> — how many logged calls match a grep pattern.
calls_matching() {
  grep -c -- "$1" "$CALL_LOG" || true
}
```

- [ ] **Step 4: Add shellcheck config and ignore rules**

`.shellcheckrc`:
```
# Follow `source` lines so lib/*.sh functions are known.
external-sources=true
```

Append to `.gitignore`:
```
tests/.bats-tmp/
```

- [ ] **Step 5: Smoke-test the helper with a throwaway test**

```bash
mkdir -p tests && cat > tests/helpers.bats <<'EOF'
load helpers

@test "stub records its arguments" {
  make_sandbox
  stub hello
  hello world
  [ "$(cat "$CALL_LOG")" = "hello world" ]
}

@test "stub body runs" {
  make_sandbox
  stub hello 'echo hi; exit 3'
  run hello
  [ "$status" -eq 3 ]
  [ "$output" = "hi" ]
}
EOF
bats tests/helpers.bats
```
Expected: `2 tests, 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add tests/helpers.bash tests/helpers.bats .shellcheckrc .gitignore
git commit -m "test: add bats helper with sandbox home and command stubs"
```

---

### Task 2: `lib/common.sh` — logging, dry-run, step tracking

**Files:**
- Create: `lib/common.sh`
- Test: `tests/common.bats`

**Interfaces:**
- Produces:
  - `log_info <msg>`, `log_ok <msg>`, `log_skip <msg>` (stdout); `log_warn <msg>`, `log_err <msg>` (stderr)
  - `run_cmd <command...>` — runs the command, or prints `  [dry-run] <command...>` when `DRY_RUN=1`
  - `expand_tilde <path>` — prints path with leading `~` replaced by `$HOME`
  - `run_step <name> <function>` — prints `==> name`, calls function, appends `name` to `FAILED_STEPS` on non-zero, returns the function's status
  - `clone_if_missing <url> <dir>` — `git clone --depth 1` unless `<dir>` exists
  - `FAILED_STEPS` array, `DRY_RUN` (default `0`)

- [ ] **Step 1: Write the failing tests**

`tests/common.bats`:
```bash
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
  [[ "$output" == *"[dry-run] touch $HOME/made"* ]]
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
  [[ "$output" == *"==> bad"* ]]
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
  [[ "$output" == *"skip"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bats tests/common.bats
```
Expected: all 8 fail with `lib/common.sh: No such file or directory`.

- [ ] **Step 3: Write `lib/common.sh`**

```bash
#!/usr/bin/env bash
# Shared helpers for bootstrap.sh and the step functions.
# Source this file; do not execute it. Must work on bash 3.2.

# When DRY_RUN=1, run_cmd prints commands instead of executing them.
DRY_RUN="${DRY_RUN:-0}"

# Names of steps that returned non-zero. Filled by run_step.
FAILED_STEPS=()

log_info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
log_ok()   { printf '\033[32m   ok\033[0m %s\n' "$*"; }
log_skip() { printf '\033[33m skip\033[0m %s\n' "$*"; }
log_warn() { printf '\033[33m warn\033[0m %s\n' "$*" >&2; }
log_err()  { printf '\033[31m fail\033[0m %s\n' "$*" >&2; }

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
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bats tests/common.bats && shellcheck lib/common.sh
```
Expected: `8 tests, 0 failures`, shellcheck silent.

- [ ] **Step 5: Commit**

```bash
git add lib/common.sh tests/common.bats
git commit -m "feat: add common helpers with dry-run and step tracking"
```

---

### Task 3: `lib/link.sh` — symlinks with backup

**Files:**
- Create: `lib/link.sh`
- Test: `tests/link.bats`

**Interfaces:**
- Consumes: `run_cmd`, `log_*`, `expand_tilde` from `lib/common.sh`
- Produces:
  - `BACKUP_DIR` — default `$HOME/.dotfiles-backup/<YYYYMMDD-HHMMSS>`; only created when a backup happens
  - `link_file <source> <target>` — makes `<target>` a symlink to `<source>`; moves an existing target to `$BACKUP_DIR/<target relative to HOME>`; returns 1 if `<source>` does not exist
  - `link_manifest <manifest> <root>` — for each non-comment, non-blank `"<src> <dst>"` line calls `link_file "<root>/<src>" "$(expand_tilde <dst>)"`; returns 1 if any line failed

- [ ] **Step 1: Write the failing tests**

`tests/link.bats`:
```bash
load helpers

setup() {
  make_sandbox
  export SRC="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$SRC/zsh" "$SRC/claude/skills"
  echo "zshrc content" > "$SRC/zsh/zshrc"
  echo "skill" > "$SRC/claude/skills/SKILL.md"
  export BACKUP_DIR="$HOME/.dotfiles-backup/test-run"
  . "$REPO_ROOT/lib/common.sh"
  . "$REPO_ROOT/lib/link.sh"
}

@test "link_file creates a symlink and parent directories" {
  link_file "$SRC/zsh/zshrc" "$HOME/.config/deep/zshrc"
  [ -L "$HOME/.config/deep/zshrc" ]
  [ "$(readlink "$HOME/.config/deep/zshrc")" = "$SRC/zsh/zshrc" ]
}

@test "link_file backs up an existing regular file" {
  echo "old" > "$HOME/.zshrc"
  link_file "$SRC/zsh/zshrc" "$HOME/.zshrc"
  [ -L "$HOME/.zshrc" ]
  [ "$(cat "$BACKUP_DIR/.zshrc")" = "old" ]
}

@test "link_file backs up an existing symlink that points elsewhere" {
  echo "other" > "$HOME/other"
  ln -s "$HOME/other" "$HOME/.zshrc"
  link_file "$SRC/zsh/zshrc" "$HOME/.zshrc"
  [ "$(readlink "$HOME/.zshrc")" = "$SRC/zsh/zshrc" ]
  [ -L "$BACKUP_DIR/.zshrc" ]
  [ -e "$HOME/other" ]
}

@test "link_file is a no-op when already linked and creates no backup dir" {
  link_file "$SRC/zsh/zshrc" "$HOME/.zshrc"
  run link_file "$SRC/zsh/zshrc" "$HOME/.zshrc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already linked"* ]]
  [ ! -d "$BACKUP_DIR" ]
}

@test "link_file links a directory as one symlink" {
  link_file "$SRC/claude/skills" "$HOME/.claude/skills"
  [ -L "$HOME/.claude/skills" ]
  [ -f "$HOME/.claude/skills/SKILL.md" ]
}

@test "link_file fails when the source is missing" {
  run link_file "$SRC/nope" "$HOME/.nope"
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/.nope" ]
}

@test "link_file changes nothing in dry-run" {
  echo "old" > "$HOME/.zshrc"
  DRY_RUN=1
  run link_file "$SRC/zsh/zshrc" "$HOME/.zshrc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] ln -s"* ]]
  [ "$(cat "$HOME/.zshrc")" = "old" ]
  [ ! -d "$BACKUP_DIR" ]
}

@test "link_manifest links every entry, skipping comments and blank lines" {
  cat > "$BATS_TEST_TMPDIR/links.txt" <<EOF
# comment line
zsh/zshrc        ~/.zshrc

claude/skills    ~/.claude/skills
EOF
  link_manifest "$BATS_TEST_TMPDIR/links.txt" "$SRC"
  [ "$(readlink "$HOME/.zshrc")" = "$SRC/zsh/zshrc" ]
  [ "$(readlink "$HOME/.claude/skills")" = "$SRC/claude/skills" ]
}

@test "link_manifest returns 1 if any entry fails but links the rest" {
  cat > "$BATS_TEST_TMPDIR/links.txt" <<EOF
missing/file     ~/.missing
zsh/zshrc        ~/.zshrc
EOF
  run link_manifest "$BATS_TEST_TMPDIR/links.txt" "$SRC"
  [ "$status" -eq 1 ]
  [ -L "$HOME/.zshrc" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bats tests/link.bats
```
Expected: 9 failures, `lib/link.sh: No such file or directory`.

- [ ] **Step 3: Write `lib/link.sh`**

```bash
#!/usr/bin/env bash
# Symlink helpers. Requires lib/common.sh to be sourced first.

# Where existing files are moved before they are replaced by symlinks.
# One directory per bootstrap run; created only when something is backed up.
BACKUP_DIR="${BACKUP_DIR:-$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)}"

# link_file <source> <target> — make <target> a symlink to <source>.
# An existing <target> (file, directory or other symlink) is moved into
# BACKUP_DIR first. Nothing is ever deleted.
link_file() {
  local src="$1" dst="$2" rel backup
  if [ ! -e "$src" ]; then
    log_err "source missing: $src"
    return 1
  fi
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    log_skip "$dst already linked"
    return 0
  fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    rel="${dst#"$HOME"/}"
    rel="${rel#/}"
    backup="$BACKUP_DIR/$rel"
    run_cmd mkdir -p "$(dirname "$backup")"
    run_cmd mv "$dst" "$backup"
    log_ok "backed up $dst -> $backup"
  fi
  run_cmd mkdir -p "$(dirname "$dst")"
  run_cmd ln -s "$src" "$dst"
  log_ok "linked $dst -> $src"
}

# link_manifest <manifest> <root> — link every "<src> <dst>" line.
# <src> is relative to <root>; <dst> may start with ~. Lines starting with #
# and blank lines are ignored. Returns 1 if any entry failed.
link_manifest() {
  local manifest="$1" root="$2" src dst status=0
  while read -r src dst; do
    case "$src" in ''|'#'*) continue ;; esac
    link_file "$root/$src" "$(expand_tilde "$dst")" || status=1
  done < "$manifest"
  return "$status"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bats tests/link.bats && shellcheck lib/link.sh
```
Expected: `9 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add lib/link.sh tests/link.bats
git commit -m "feat: add symlink helpers with backup and manifest support"
```

---

### Task 4: zsh configuration

**Files:**
- Create: `zsh/zshrc`, `zsh/zprofile`, `zsh/path.zsh`, `zsh/exports.zsh`, `zsh/tools.zsh`, `zsh/aliases.zsh`, `zsh/functions.zsh`, `zsh/local.zsh.example`
- Copy: `~/.p10k.zsh` → `zsh/p10k.zsh`
- Test: `tests/zsh.bats`

**Interfaces:**
- Produces: `~/.zshrc` exports `DOTFILES` (repo root, resolved through the symlink) and sources `$DOTFILES/zsh/{path,exports,tools,aliases,functions}.zsh`; `path.zsh` defines `path_prepend <dir>` and `path_append <dir>` used by `tools.zsh`.

- [ ] **Step 1: Write the failing tests**

`tests/zsh.bats`:
```bash
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
  [[ "$output" == *"DOTFILES=$REPO_ROOT"* ]]
  [[ "$output" == *"vim=nvim"* ]]
  [[ "$output" == *"mkd is a shell function"* ]]
  [[ "$output" != *"no such file"* ]]
  [[ "$output" != *"command not found"* ]]
}

@test "path_prepend ignores missing directories and duplicates" {
  run zsh -c "
    source '$REPO_ROOT/zsh/path.zsh'
    PATH=/usr/bin
    path_prepend /nonexistent/dir
    path_prepend /usr/bin
    mkdir -p '$HOME/bin'
    path_prepend '$HOME/bin'
    path_prepend '$HOME/bin'
    echo \$PATH"
  [ "$output" = "$HOME/bin:/usr/bin" ]
}

@test "zprofile only adds directories that exist" {
  run zsh -c "PATH=/usr/bin; source '$REPO_ROOT/zsh/zprofile'; echo \$PATH"
  [[ "$output" != *"Toolbox/scripts"* ]] || [ -d "$HOME/Library/Application Support/JetBrains/Toolbox/scripts" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bats tests/zsh.bats
```
Expected: failures (`zsh/zshrc` not found).

- [ ] **Step 3: Write `zsh/zshrc`**

```zsh
# ~/.zshrc — interactive shells. Managed by the dotfiles repo (this file is a symlink).

# Powerlevel10k instant prompt. Must stay at the top; anything that prints or
# asks for input has to be above this block.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Root of the dotfiles repo, found by following the ~/.zshrc symlink.
# %x = the file being sourced; :A = resolve symlinks; :h:h = go up two directories.
export DOTFILES="${${(%):-%x}:A:h:h}"

# ---- oh-my-zsh -------------------------------------------------------------
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
ENABLE_CORRECTION="true"
COMPLETION_WAITING_DOTS="true"
export UPDATE_ZSH_DAYS=1
ZSH_DOTENV_PROMPT=false
plugins=(git docker github httpie macos pip pep8 python pylint pyenv celery brew golang zsh-autosuggestions zsh-syntax-highlighting zsh-completions dotenv kubectl)
[[ -f "$ZSH/oh-my-zsh.sh" ]] && source "$ZSH/oh-my-zsh.sh"

# ---- modules ---------------------------------------------------------------
for _module in path exports tools aliases functions; do
  source "$DOTFILES/zsh/$_module.zsh"
done
unset _module

# Commands starting with a space are not saved in history.
setopt HIST_IGNORE_SPACE

# Prompt configuration. Run `p10k configure` to regenerate.
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# Machine-specific overrides, not in the repo. See zsh/local.zsh.example.
[[ -f ~/.config/zsh/local.zsh ]] && source ~/.config/zsh/local.zsh
```

- [ ] **Step 4: Write `zsh/zprofile`**

```zsh
# ~/.zprofile — login shells only. Managed by the dotfiles repo (symlink).

# Homebrew on Apple Silicon: puts /opt/homebrew/{bin,sbin} on PATH and sets HOMEBREW_PREFIX.
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

# add_path_if_dir <dir> — append to PATH only when the directory exists.
add_path_if_dir() { [[ -d "$1" ]] && export PATH="$PATH:$1"; }

add_path_if_dir "$HOME/.docker/bin"
add_path_if_dir "$HOME/Library/Application Support/JetBrains/Toolbox/scripts"
add_path_if_dir "/Applications/Obsidian.app/Contents/MacOS"

# python.org installer for 3.12 (kept from the baseline machine; pyenv shims
# are added later in .zshrc and take precedence).
[[ -d /Library/Frameworks/Python.framework/Versions/3.12/bin ]] &&
  export PATH="/Library/Frameworks/Python.framework/Versions/3.12/bin:$PATH"
```

- [ ] **Step 5: Write `zsh/path.zsh`**

```zsh
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
```

- [ ] **Step 6: Write `zsh/exports.zsh`**

```zsh
# Environment variables that are not tied to one tool.

export PROJECT_HOME="$HOME/Projects"
export TERM="xterm-256color"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Go modules: verify checksums against the public database; no proxy.
export GOSUMDB=sum.golang.org
export GOPROXY=direct

# Kubernetes
export KUBE_CONFIG_PATH="$HOME/.kube/config"

# Ollama: let Obsidian plugins call the local server; listen on all interfaces.
export OLLAMA_ORIGINS="app://obsidian.md*"
export OLLAMA_HOST="0.0.0.0"
```

- [ ] **Step 7: Write `zsh/tools.zsh`**

```zsh
# Tool initialisation. Every block is skipped when its tool is not installed.

_brew_prefix="${HOMEBREW_PREFIX:-/opt/homebrew}"

# ---- pyenv: Python versions and virtualenvs --------------------------------
export PYENV_ROOT="$HOME/.pyenv"
path_prepend "$PYENV_ROOT/bin"
if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init --path)"
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

# ---- GitHub token for the Claude Code github MCP plugin --------------------
# Read from gh's keychain at shell start; nothing is written to disk.
command -v gh >/dev/null 2>&1 && export GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token 2>/dev/null)"

unset _brew_prefix
```

- [ ] **Step 8: Write `zsh/aliases.zsh`**

```zsh
# Config editing
alias zshconfig="code ~/.zshrc"

# Editors: neovim everywhere; `ovim` runs the original vim.
# `command vim` is needed because zsh expands aliases inside alias text.
alias vim="nvim"
alias vi="nvim"
alias vimdiff="nvim -d"
alias ovim="command vim"

# git (gf = git fetch, gl = git pull, from the oh-my-zsh git plugin)
alias gfgl="gf && gl"

# Finder: show or hide hidden files
alias dotfilesShow='defaults write com.apple.finder AppleShowAllFiles TRUE; killall Finder'
alias dotfilesHide='defaults write com.apple.finder AppleShowAllFiles FALSE; killall Finder'

# macOS: clear the DNS cache
alias flush_dns='sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder'

# Infrastructure tools
alias k="kubectl"
alias kx="kubectx"
alias tf="terraform"
alias dc="docker-compose"
alias dk="docker"

# fabric (AI prompt tool) installed as a single binary
[[ -x "$HOME/Applications/fabric" ]] && alias fabric="$HOME/Applications/fabric"
```

- [ ] **Step 9: Write `zsh/functions.zsh`**

```zsh
# mkd <dir> — create a directory and enter it
mkd() { mkdir -p "$@" && cd "$_" || return; }

# gi <templates> — print a .gitignore from gitignore.io, e.g. `gi python,macos`
gi() { curl -L -s "https://www.gitignore.io/api/$*"; }

# git_tag <tag> — create a tag and push it
git_tag() { git tag "$1" && git push origin "$1"; }

# git_force_tag <tag> — recreate an existing tag and force-push it
git_force_tag() { git tag -d "$1"; git tag "$1" && git push origin -f "$1"; }
```

- [ ] **Step 10: Write `zsh/local.zsh.example` and copy `p10k.zsh`**

`zsh/local.zsh.example`:
```zsh
# Copy this file to ~/.config/zsh/local.zsh and edit it.
# That file is NOT tracked in git. Put values here that only make sense on
# one machine (external drives, work-only settings, ...).

# Ollama models on an external drive
# export OLLAMA_MODELS="/Volumes/External"

# OpenAudible library on an external drive
# export OPENAUDIBLE_HOME="/Volumes/External/OpenAudible"
```

```bash
cp ~/.p10k.zsh zsh/p10k.zsh && wc -l zsh/p10k.zsh
```
Expected: `1671 zsh/p10k.zsh`.

- [ ] **Step 11: Run the tests to verify they pass**

```bash
bats tests/zsh.bats
```
Expected: `4 tests, 0 failures`. If the "loads without errors" test prints an error from a plugin, that is a real bug in the module — fix it, do not weaken the assertion.

- [ ] **Step 12: Commit**

```bash
git add zsh tests/zsh.bats
git commit -m "feat(zsh): split shell config into guarded modules"
```

---

### Task 5: git configuration

**Files:**
- Create: `git/gitconfig`, `git/ignore`

- [ ] **Step 1: Copy the files and review them**

```bash
mkdir -p git && cp ~/.gitconfig git/gitconfig && cp ~/.config/git/ignore git/ignore
cat git/gitconfig
```
Expected: `[user]` has `name`, `email`, `signingkey`; the `signingkey` value starts with `ssh-` or `key::` (a **public** SSH key — safe to publish). `gpg.ssh.program` is the 1Password `op-ssh-sign` path. `credential` helpers use `/opt/homebrew/bin/gh`. If any line contains a private key, a token or a password, stop and remove it.

- [ ] **Step 2: Verify git can parse it**

```bash
git config --file git/gitconfig --list | wc -l && cat git/ignore
```
Expected: a positive line count; `git/ignore` shows `**/.claude/settings.local.json`.

- [ ] **Step 3: Commit**

```bash
git add git
git commit -m "feat(git): add gitconfig and global ignore"
```

---

### Task 6: Brewfiles

**Files:**
- Create: `brew/Brewfile`, `brew/Brewfile.extra`
- Test: `tests/brew.bats`

- [ ] **Step 1: Write the failing test**

`tests/brew.bats`:
```bash
load helpers

@test "Brewfile parses and lists the expected items" {
  run brew bundle list --file "$REPO_ROOT/brew/Brewfile" --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"nvm"* ]]
  [[ "$output" == *"visual-studio-code"* ]]
  [[ "$output" != *$'\nnode\n'* ]]
}

@test "Brewfile.extra parses" {
  run brew bundle list --file "$REPO_ROOT/brew/Brewfile.extra" --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"reaper"* ]]
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/brew.bats
```
Expected: 2 failures (file not found).

- [ ] **Step 3: Write `brew/Brewfile`**

```ruby
# Core packages. Install with: brew bundle --file brew/Brewfile
# Hardware/audio apps live in Brewfile.extra.

# ---- taps ------------------------------------------------------------------
tap "anomalyco/tap"
tap "codecrafters-io/tap"
tap "gentleman-programming/tap"
tap "jakehilborn/jakehilborn"

# ---- CLI tools --------------------------------------------------------------
brew "autojump"          # j <dir>: jump to a directory you visited before
brew "bat"               # cat with syntax colours
brew "bats-core"         # test runner for the scripts in this repo
brew "cloudflared"       # Cloudflare tunnel client
brew "cmake"
brew "cookiecutter"      # project templates
brew "ffmpeg"
brew "gh"                # GitHub CLI
brew "git"
brew "glow"              # Markdown in the terminal
brew "gnupg"
brew "golang-migrate"    # database migrations for Go
brew "golangci-lint"
brew "helm"
brew "just"              # command runner
brew "lsusb"
brew "lychee"            # link checker
brew "minikube"
brew "mycli"             # MySQL client with autocomplete
brew "neovim"
brew "nvm"               # Node versions; bootstrap installs the LTS default
brew "pgcli"             # PostgreSQL client with autocomplete
brew "pinentry-mac"      # GPG passphrase dialog
brew "postgresql@15"
brew "protobuf"
brew "pyenv"             # Python versions
brew "pyenv-virtualenv"
brew "shellcheck"        # shell script linter
brew "terraform"
brew "tesseract"         # OCR
brew "uv"                # Python package manager
brew "wget"
brew "worktrunk"         # wt: git worktree manager
brew "ykman"             # YubiKey manager
brew "yt-dlp"

# ---- CLI tools from taps ---------------------------------------------------
brew "anomalyco/tap/opencode"
brew "codecrafters-io/tap/codecrafters"
brew "gentleman-programming/tap/engram"
brew "gentleman-programming/tap/gentle-ai"
brew "gentleman-programming/tap/gga"
brew "jakehilborn/jakehilborn/displayplacer"   # set display layout from the CLI

# ---- fonts -----------------------------------------------------------------
cask "font-jetbrains-mono"
cask "font-jetbrains-mono-nerd-font"           # icons for the p10k prompt

# ---- apps ------------------------------------------------------------------
cask "1password"
cask "1password-cli"
cask "balenaetcher"
cask "betterdisplay"
cask "browserosaurus"
cask "calibre"
cask "chatgpt"
cask "claude"
cask "codex"
cask "copilot-cli"
cask "discord"
cask "docker-desktop"
cask "dropbox"
cask "firefox"
cask "google-chrome"
cask "iterm2"
cask "jetbrains-toolbox"
cask "lm-studio"
cask "logi-options+"
cask "macwhisper"
cask "microsoft-office"
cask "microsoft-teams"
cask "ngrok"
cask "obsidian"
cask "ollama-app"
cask "onedrive"
cask "proton-mail"
cask "proton-mail-bridge"
cask "protonvpn"
cask "raspberry-pi-imager"
cask "raycast"
cask "setapp"
cask "slack"
cask "telegram"
cask "utm"
cask "visual-studio-code"
cask "vlc"
cask "whatsapp"
cask "youtube-music"
cask "zed"
cask "zoom"
```

- [ ] **Step 4: Write `brew/Brewfile.extra`**

```ruby
# Hardware, audio and music apps. Install with: ./bootstrap.sh --extra
# (or: brew bundle --file brew/Brewfile.extra)

cask "caldigit-docking-utility"
cask "elgato-control-center"
cask "elgato-stream-deck"
cask "elgato-wave-link"
cask "ik-product-manager"            # installs AmpliTube / TONEX
cask "ilok-license-manager"
cask "insta360-link-controller"
cask "mediahuman-audio-converter"
cask "openaudible"
cask "openrgb"
cask "paragon-extfs"
cask "qbittorrent"
cask "reaper"
cask "steinberg-download-assistant"  # installs Cubase
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
bats tests/brew.bats
```
Expected: `2 tests, 0 failures`.

- [ ] **Step 6: Check nothing on this machine is missing from the Brewfile by mistake**

```bash
brew bundle check --file brew/Brewfile --verbose 2>&1 | tail -20
```
Expected: mostly "satisfied"; missing items are the intended additions (`nvm`, `bats-core`, `shellcheck`, `ykman`, casks for apps installed outside Homebrew). Nothing unexpected.

- [ ] **Step 7: Commit**

```bash
git add brew tests/brew.bats
git commit -m "feat(brew): add core and extra Brewfiles"
```

---

### Task 7: macOS defaults

**Files:**
- Create: `macos/defaults.sh`
- Test: `tests/macos.bats`

**Interfaces:**
- Consumes: `run_cmd`, `log_info` from `lib/common.sh` (sourced relative to the script's own location)
- Produces: a script runnable standalone (`bash macos/defaults.sh`) or from `step_macos`; honours `DRY_RUN=1`.

- [ ] **Step 1: Write the failing test**

`tests/macos.bats`:
```bash
load helpers

setup() {
  make_sandbox
  stub defaults 'echo "defaults must not run in dry-run" >&2; exit 99'
  stub killall 'echo "killall must not run in dry-run" >&2; exit 99'
}

@test "defaults.sh dry-run prints every write and touches nothing" {
  DRY_RUN=1 run bash "$REPO_ROOT/macos/defaults.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] defaults write com.apple.dock autohide -bool true"* ]]
  [[ "$output" == *"[dry-run] defaults write NSGlobalDomain KeyRepeat -int 2"* ]]
  [[ "$output" == *"[dry-run] defaults write com.apple.finder AppleShowAllFiles -bool true"* ]]
  [[ "$output" == *"[dry-run] killall Dock"* ]]
  [ "$(calls_matching 'defaults')" -eq 0 ]
}

@test "defaults.sh calls defaults write when not in dry-run" {
  stub defaults
  stub killall
  DRY_RUN=0 run bash "$REPO_ROOT/macos/defaults.sh"
  [ "$status" -eq 0 ]
  [ "$(calls_matching 'defaults write com.apple.dock tilesize -int 48')" -eq 1 ]
  [ "$(calls_matching 'killall Finder')" -eq 1 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/macos.bats
```
Expected: 2 failures.

- [ ] **Step 3: Write `macos/defaults.sh`**

```bash
#!/usr/bin/env bash
# macOS preferences, captured from the baseline machine on 2026-09-17.
# Run alone: bash macos/defaults.sh   (DRY_RUN=1 to print only)
# Log out and back in for keyboard and trackpad changes to fully apply.

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "$DOTFILES_ROOT/lib/common.sh"

w() { run_cmd defaults write "$@"; }

log_info "Keyboard and text"
w NSGlobalDomain KeyRepeat -int 2                          # fastest key repeat
w NSGlobalDomain InitialKeyRepeat -int 15                  # short delay before repeat
w NSGlobalDomain ApplePressAndHoldEnabled -bool false      # hold a key = repeat, not accent menu
w NSGlobalDomain AppleKeyboardUIMode -int 0                # Tab moves between text fields only
w NSGlobalDomain NSAutomaticCapitalizationEnabled -bool true
w NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool true
w com.apple.HIToolbox AppleFnUsageType -int 2              # Fn/Globe key press: 2 = Show Emoji & Symbols

log_info "Appearance and language"
w NSGlobalDomain AppleInterfaceStyle -string "Dark"
w NSGlobalDomain AppleLanguages -array "en-US" "en-NL" "nl-NL" "ar-NL"
w NSGlobalDomain AppleLocale -string "en_US@rg=nlzzzz"     # US English, Netherlands region formats

log_info "Trackpad"
w NSGlobalDomain com.apple.swipescrolldirection -bool false # "natural" scrolling off
w com.apple.AppleMultitouchTrackpad Clicking -bool true    # tap to click
w com.apple.AppleMultitouchTrackpad TrackpadRightClick -bool true
w com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool false
w com.apple.AppleMultitouchTrackpad Dragging -bool false
w com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true

log_info "Finder"
w com.apple.finder AppleShowAllFiles -bool true            # show hidden files
w com.apple.finder ShowPathbar -bool true
w com.apple.finder ShowStatusBar -bool true
w com.apple.finder FXPreferredViewStyle -string "icnv"     # icon view
w com.apple.finder NewWindowTarget -string "PfHm"          # new windows open at home
w com.apple.finder NewWindowTargetPath -string "file://$HOME/"
w com.apple.finder ShowExternalHardDrivesOnDesktop -bool false
w com.apple.finder ShowHardDrivesOnDesktop -bool false
w com.apple.finder ShowRemovableMediaOnDesktop -bool false
w com.apple.desktopservices DSDontWriteNetworkStores -bool true  # no .DS_Store on network shares

log_info "Dock"
w com.apple.dock autohide -bool true
w com.apple.dock autohide-delay -float 0
w com.apple.dock autohide-time-modifier -float 0
w com.apple.dock tilesize -int 48
w com.apple.dock orientation -string "bottom"
w com.apple.dock show-recents -bool false
w com.apple.dock showhidden -bool true                     # dim hidden apps
w com.apple.dock wvous-br-corner -int 14                   # bottom-right hot corner: Quick Note
w com.apple.dock wvous-br-modifier -int 0
w com.apple.dock wvous-bl-corner -int 0
w com.apple.dock wvous-tr-corner -int 0
w com.apple.dock wvous-tl-corner -int 0

log_info "Windows and menu bar"
w com.apple.WindowManager GloballyEnabled -bool false      # Stage Manager off
w com.apple.WindowManager EnableTilingByEdgeDrag -bool true
w com.apple.menuextra.clock ShowSeconds -bool true
w com.apple.menuextra.clock ShowDate -int 0
w com.apple.ActivityMonitor ShowCategory -int 100          # show all processes

log_info "Restarting Finder, Dock and the menu bar"
for app in Finder Dock SystemUIServer; do
  run_cmd killall "$app" 2>/dev/null || true
done
```

- [ ] **Step 4: Run the tests and shellcheck**

```bash
bats tests/macos.bats && shellcheck macos/defaults.sh
```
Expected: `2 tests, 0 failures`, shellcheck silent.

- [ ] **Step 5: Confirm the values match this machine**

```bash
for kv in "com.apple.dock tilesize" "NSGlobalDomain KeyRepeat" "com.apple.finder FXPreferredViewStyle" "com.apple.HIToolbox AppleFnUsageType"; do echo "$kv = $(defaults read $kv)"; done
```
Expected: `48`, `2`, `icnv`, `2` — same as the script.

- [ ] **Step 6: Commit**

```bash
git add macos tests/macos.bats
git commit -m "feat(macos): add defaults script captured from baseline machine"
```

---

### Task 8: Zed and Claude Code configs

**Files:**
- Create: `editors/zed/settings.json`
- Create: `claude/settings.json`, `claude/CLAUDE.md`, `claude/statusline-command.sh`, `claude/hooks/*`, `claude/skills/graphify/*`
- Test: `tests/secrets.bats`

- [ ] **Step 1: Write the failing test**

`tests/secrets.bats`:
```bash
load helpers

@test "no secret-looking values anywhere in the repo" {
  cd "$REPO_ROOT"
  # Allowed matches: variable names and documentation, never a value.
  # git grep exits 1 when nothing matches; -I skips binary files;
  # --untracked also scans files not yet committed (ignored files stay excluded).
  run git grep --untracked -nIiE '(github_pat_|ghp_|gho_|sk-[A-Za-z0-9]{20}|AKIA[0-9A-Z]{16}|BEGIN (RSA|OPENSSH) PRIVATE KEY|xox[baprs]-)'
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
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/secrets.bats
```
Expected: the zed and claude tests fail (files missing).

- [ ] **Step 3: Copy Zed settings without the token line**

`sed '/github_personal_access_token/d'` prints the file minus the one line holding the token.

```bash
mkdir -p editors/zed
sed '/github_personal_access_token/d' ~/.config/zed/settings.json > editors/zed/settings.json
echo "original: $(wc -l < ~/.config/zed/settings.json)  repo: $(wc -l < editors/zed/settings.json)"
sed -n '/mcp-server-github/,/^  }/p' editors/zed/settings.json
```
Expected: repo has exactly one line fewer; the `mcp-server-github` block now reads `"settings": {}` — valid JSON, the token is gone.

- [ ] **Step 4: Copy Claude Code files**

```bash
mkdir -p claude
cp ~/.claude/settings.json ~/.claude/CLAUDE.md ~/.claude/statusline-command.sh claude/
cp -R ~/.claude/hooks claude/hooks
cp -R ~/.claude/skills claude/skills
find claude -type f | sort
ls -l claude/hooks
```
Expected: `settings.json`, `CLAUDE.md`, `statusline-command.sh`, `hooks/{cbm-code-discovery-gate,cbm-session-reminder,worktree-create.sh}` (all executable), `skills/graphify/{SKILL.md,.graphify_version}`.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
bats tests/secrets.bats
```
Expected: `3 tests, 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add editors claude tests/secrets.bats
git commit -m "feat: add zed and claude code configs without secrets"
```

---

### Task 9: iTerm2 preferences export

**Files:**
- Create: `iterm2/com.googlecode.iterm2.plist`

- [ ] **Step 1: Export the current preferences as readable XML**

`defaults export` writes the preference domain to a file; `plutil -convert xml1` turns it into text so git diffs are readable; `plutil -lint` checks it parses.

```bash
mkdir -p iterm2
defaults export com.googlecode.iterm2 iterm2/com.googlecode.iterm2.plist
plutil -convert xml1 iterm2/com.googlecode.iterm2.plist
plutil -lint iterm2/com.googlecode.iterm2.plist
head -5 iterm2/com.googlecode.iterm2.plist
```
Expected: `OK` from lint; the file starts with `<?xml`.

- [ ] **Step 2: Check for anything private**

```bash
grep -niE 'token|password|secret|api[_-]?key' iterm2/com.googlecode.iterm2.plist || echo "clean"
grep -c '<key>Command</key>' iterm2/com.googlecode.iterm2.plist || true
```
Expected: `clean`. If a profile has a login `Command` with a secret in it, delete that `<key>`/`<string>` pair by hand and re-run lint.

- [ ] **Step 3: Run the secrets test and commit**

```bash
bats tests/secrets.bats
git add iterm2
git commit -m "feat(iterm2): export preferences plist"
```

---

### Task 10: Link manifest

**Files:**
- Create: `links.txt`
- Test: `tests/manifest.bats`

- [ ] **Step 1: Write the failing test**

`tests/manifest.bats`:
```bash
load helpers

@test "every manifest source exists in the repo" {
  while read -r src dst; do
    case "$src" in ''|'#'*) continue ;; esac
    [ -e "$REPO_ROOT/$src" ] || { echo "missing: $src"; return 1; }
  done < "$REPO_ROOT/links.txt"
}

@test "every manifest target is under the home directory" {
  while read -r src dst; do
    case "$src" in ''|'#'*) continue ;; esac
    [[ "$dst" == "~/"* ]] || { echo "not under ~: $dst"; return 1; }
  done < "$REPO_ROOT/links.txt"
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/manifest.bats
```
Expected: 2 failures (`links.txt` missing).

- [ ] **Step 3: Write `links.txt`**

```
# <path in repo>              <symlink to create>
zsh/zshrc                     ~/.zshrc
zsh/zprofile                  ~/.zprofile
zsh/p10k.zsh                  ~/.p10k.zsh
git/gitconfig                 ~/.gitconfig
git/ignore                    ~/.config/git/ignore
editors/zed/settings.json     ~/.config/zed/settings.json
claude/settings.json          ~/.claude/settings.json
claude/CLAUDE.md              ~/.claude/CLAUDE.md
claude/statusline-command.sh  ~/.claude/statusline-command.sh
claude/hooks                  ~/.claude/hooks
claude/skills                 ~/.claude/skills
```

- [ ] **Step 4: Run the test to verify it passes, then commit**

```bash
bats tests/manifest.bats
git add links.txt tests/manifest.bats
git commit -m "feat: add symlink manifest"
```

---

### Task 11: Steps — Xcode CLT, Homebrew, brew bundle

**Files:**
- Create: `lib/steps.sh`
- Test: `tests/steps-brew.bats`

**Interfaces:**
- Consumes: `run_cmd`, `log_*`, `clone_if_missing` (common.sh); `DOTFILES_ROOT` (set by bootstrap.sh)
- Produces: `step_xcode`, `step_homebrew`, `step_brew_bundle`; variables `BREW_BIN` (default `/opt/homebrew/bin/brew`), `INSTALL_EXTRA` (default `0`)

- [ ] **Step 1: Write the failing tests**

`tests/steps-brew.bats`:
```bash
load helpers

setup() {
  make_sandbox
  export DOTFILES_ROOT="$REPO_ROOT"
  . "$REPO_ROOT/lib/common.sh"
  . "$REPO_ROOT/lib/link.sh"
  . "$REPO_ROOT/lib/steps.sh"
}

@test "step_xcode skips when the tools are installed" {
  stub xcode-select 'exit 0'
  run step_xcode
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip"* ]]
  [ "$(calls_matching 'xcode-select --install')" -eq 0 ]
}

@test "step_xcode dry-run prints the install command when tools are missing" {
  stub xcode-select 'case "$1" in -p) exit 2;; esac'
  DRY_RUN=1 run step_xcode
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] xcode-select --install"* ]]
}

@test "step_homebrew skips when brew exists" {
  stub brew 'case "$1" in shellenv) echo "export HOMEBREW_TEST=1";; esac'
  BREW_BIN="$STUB_BIN/brew" run step_homebrew
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip"* ]]
}

@test "step_homebrew dry-run prints the installer when brew is missing" {
  BREW_BIN="$BATS_TEST_TMPDIR/nope/brew" DRY_RUN=1 run step_homebrew
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] install Homebrew"* ]]
}

@test "step_brew_bundle installs the core Brewfile only by default" {
  stub brew
  step_brew_bundle
  [ "$(calls_matching "brew bundle --file $REPO_ROOT/brew/Brewfile$")" -eq 1 ]
  [ "$(calls_matching 'Brewfile.extra')" -eq 0 ]
}

@test "step_brew_bundle also installs Brewfile.extra when INSTALL_EXTRA=1" {
  stub brew
  INSTALL_EXTRA=1 step_brew_bundle
  [ "$(calls_matching 'Brewfile.extra')" -eq 1 ]
}

@test "step_brew_bundle returns 1 when brew bundle fails" {
  stub brew 'exit 1'
  run step_brew_bundle
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bats tests/steps-brew.bats
```
Expected: 7 failures (`lib/steps.sh` missing).

- [ ] **Step 3: Write the first part of `lib/steps.sh`**

```bash
#!/usr/bin/env bash
# Bootstrap steps, one function each. Requires lib/common.sh and lib/link.sh
# to be sourced first and DOTFILES_ROOT to point at the repository.
# Every function returns non-zero on failure and never exits the shell.

BREW_BIN="${BREW_BIN:-/opt/homebrew/bin/brew}"
INSTALL_EXTRA="${INSTALL_EXTRA:-0}"
HOMEBREW_INSTALLER="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

# ---- 1. Xcode Command Line Tools (compilers and git needed by Homebrew) -----
step_xcode() {
  if xcode-select -p >/dev/null 2>&1; then
    log_skip "Xcode Command Line Tools installed"
    return 0
  fi
  run_cmd xcode-select --install || return 1
  [ "$DRY_RUN" = "1" ] && return 0
  log_info "Finish the Command Line Tools dialog; waiting for it..."
  until xcode-select -p >/dev/null 2>&1; do sleep 5; done
}

# ---- 2. Homebrew -------------------------------------------------------------
step_homebrew() {
  if [ -x "$BREW_BIN" ]; then
    log_skip "Homebrew installed at $BREW_BIN"
  elif [ "$DRY_RUN" = "1" ]; then
    printf '  [dry-run] install Homebrew from %s\n' "$HOMEBREW_INSTALLER"
    return 0
  else
    /bin/bash -c "$(curl -fsSL "$HOMEBREW_INSTALLER")" || return 1
  fi
  eval "$("$BREW_BIN" shellenv)"
}

# ---- 3. Packages and apps ----------------------------------------------------
step_brew_bundle() {
  local status=0
  run_cmd brew bundle --file "$DOTFILES_ROOT/brew/Brewfile" || status=1
  if [ "$INSTALL_EXTRA" = "1" ]; then
    run_cmd brew bundle --file "$DOTFILES_ROOT/brew/Brewfile.extra" || status=1
  fi
  return "$status"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bats tests/steps-brew.bats && shellcheck lib/steps.sh
```
Expected: `7 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add lib/steps.sh tests/steps-brew.bats
git commit -m "feat(steps): add xcode, homebrew and brew bundle steps"
```

---

### Task 12: Steps — oh-my-zsh, version managers, links, iTerm2, macOS

**Files:**
- Modify: `lib/steps.sh` (append)
- Test: `tests/steps-config.bats`

**Interfaces:**
- Consumes: `clone_if_missing`, `link_manifest`, `run_cmd`, `log_*`, `DOTFILES_ROOT`, `DRY_RUN`
- Produces: `step_omz`, `step_version_managers`, `step_links`, `step_iterm2`, `step_macos`

- [ ] **Step 1: Write the failing tests**

`tests/steps-config.bats`:
```bash
load helpers

setup() {
  make_sandbox
  export DOTFILES_ROOT="$REPO_ROOT"
  export BACKUP_DIR="$HOME/.dotfiles-backup/test-run"
  . "$REPO_ROOT/lib/common.sh"
  . "$REPO_ROOT/lib/link.sh"
  . "$REPO_ROOT/lib/steps.sh"
  # git clone stub: create the target directory (last argument)
  stub git 'for a in "$@"; do last="$a"; done; mkdir -p "$last"'
}

@test "step_omz clones oh-my-zsh, four plugins and the theme" {
  step_omz
  [ -d "$HOME/.oh-my-zsh" ]
  for p in zsh-autosuggestions zsh-syntax-highlighting zsh-completions autoupdate; do
    [ -d "$HOME/.oh-my-zsh/custom/plugins/$p" ]
  done
  [ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]
  [ "$(calls_matching 'git clone')" -eq 6 ]
}

@test "step_omz is idempotent" {
  step_omz
  : > "$CALL_LOG"
  step_omz
  [ "$(calls_matching 'git clone')" -eq 0 ]
}

@test "step_version_managers clones goenv and installs the default Node" {
  local prefix="$BATS_TEST_TMPDIR/nvm-prefix"
  mkdir -p "$prefix"
  # fake nvm.sh: defines an nvm function that logs its calls
  printf 'nvm() { printf "nvm %%s\\n" "$*" >> "%s"; }\n' "$CALL_LOG" > "$prefix/nvm.sh"
  stub brew "case \"\$*\" in '--prefix nvm') echo '$prefix';; esac"
  step_version_managers
  [ -d "$HOME/.goenv" ]
  [ -d "$HOME/.nvm" ]
  [ "$(calls_matching 'nvm install --lts')" -eq 1 ]
  [ "$(calls_matching "nvm alias default lts/\*")" -eq 1 ]
}

@test "step_version_managers skips Node install when a default alias exists" {
  local prefix="$BATS_TEST_TMPDIR/nvm-prefix"
  mkdir -p "$prefix" "$HOME/.nvm/alias"
  echo "lts/*" > "$HOME/.nvm/alias/default"
  printf 'nvm() { printf "nvm %%s\\n" "$*" >> "%s"; }\n' "$CALL_LOG" > "$prefix/nvm.sh"
  stub brew "case \"\$*\" in '--prefix nvm') echo '$prefix';; esac"
  run step_version_managers
  [ "$status" -eq 0 ]
  [ "$(calls_matching 'nvm install')" -eq 0 ]
}

@test "step_version_managers warns but succeeds when nvm is not installed" {
  stub brew 'exit 1'
  run step_version_managers
  [ "$status" -eq 0 ]
  [[ "$output" == *"nvm not installed"* ]]
}

@test "step_links links the real manifest into the sandbox home" {
  step_links
  [ "$(readlink "$HOME/.zshrc")" = "$REPO_ROOT/zsh/zshrc" ]
  [ "$(readlink "$HOME/.claude/skills")" = "$REPO_ROOT/claude/skills" ]
  [ "$(readlink "$HOME/.config/git/ignore")" = "$REPO_ROOT/git/ignore" ]
}

@test "step_iterm2 writes both preference keys" {
  stub defaults 'case "$1" in read) exit 1;; esac'
  step_iterm2
  [ "$(calls_matching "defaults write com.googlecode.iterm2 PrefsCustomFolder -string $REPO_ROOT/iterm2")" -eq 1 ]
  [ "$(calls_matching 'defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true')" -eq 1 ]
}

@test "step_iterm2 skips when already configured" {
  stub defaults "case \"\$*\" in *PrefsCustomFolder) echo '$REPO_ROOT/iterm2';; *LoadPrefsFromCustomFolder) echo 1;; esac"
  run step_iterm2
  [[ "$output" == *"skip"* ]]
  [ "$(calls_matching 'defaults write')" -eq 0 ]
}

@test "step_macos runs defaults.sh and passes DRY_RUN through" {
  stub defaults 'exit 99'
  stub killall 'exit 99'
  DRY_RUN=1 run step_macos
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] defaults write com.apple.dock autohide -bool true"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bats tests/steps-config.bats
```
Expected: 9 failures (`step_omz: command not found` etc.).

- [ ] **Step 3: Append to `lib/steps.sh`**

```bash

# ---- 4. oh-my-zsh, custom plugins and the powerlevel10k theme ---------------
# Cloned directly (not via the oh-my-zsh installer) so ~/.zshrc is never touched.
step_omz() {
  local custom="$HOME/.oh-my-zsh/custom" status=0
  clone_if_missing https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" || status=1
  clone_if_missing https://github.com/zsh-users/zsh-autosuggestions.git "$custom/plugins/zsh-autosuggestions" || status=1
  clone_if_missing https://github.com/zsh-users/zsh-syntax-highlighting.git "$custom/plugins/zsh-syntax-highlighting" || status=1
  clone_if_missing https://github.com/zsh-users/zsh-completions.git "$custom/plugins/zsh-completions" || status=1
  clone_if_missing https://github.com/TamCore/autoupdate-oh-my-zsh-plugins.git "$custom/plugins/autoupdate" || status=1
  clone_if_missing https://github.com/romkatv/powerlevel10k.git "$custom/themes/powerlevel10k" || status=1
  return "$status"
}

# ---- 5. Version managers: goenv (git clone) and nvm default Node ------------
# pyenv and nvm themselves come from the Brewfile. One LTS Node is installed so
# that tools expecting `node` on PATH work right after bootstrap.
step_version_managers() {
  local status=0 nvm_prefix nvm_sh
  clone_if_missing https://github.com/go-nv/goenv.git "$HOME/.goenv" || status=1
  run_cmd mkdir -p "$HOME/.nvm"
  nvm_prefix="$(brew --prefix nvm 2>/dev/null)"
  nvm_sh="$nvm_prefix/nvm.sh"
  if [ -z "$nvm_prefix" ] || [ ! -s "$nvm_sh" ]; then
    log_warn "nvm not installed; skipping default Node"
    return "$status"
  fi
  if [ -e "$HOME/.nvm/alias/default" ]; then
    log_skip "nvm default Node already set"
    return "$status"
  fi
  run_cmd bash -c "export NVM_DIR=\"$HOME/.nvm\"; . \"$nvm_sh\"; nvm install --lts && nvm alias default 'lts/*'" || status=1
  return "$status"
}

# ---- 6. Symlinks ---------------------------------------------------------------
step_links() {
  link_manifest "$DOTFILES_ROOT/links.txt" "$DOTFILES_ROOT"
}

# ---- 7. iTerm2: load preferences from the repo -------------------------------
step_iterm2() {
  local folder="$DOTFILES_ROOT/iterm2"
  if [ "$(defaults read com.googlecode.iterm2 PrefsCustomFolder 2>/dev/null)" = "$folder" ] &&
     [ "$(defaults read com.googlecode.iterm2 LoadPrefsFromCustomFolder 2>/dev/null)" = "1" ]; then
    log_skip "iTerm2 already loads preferences from $folder"
    return 0
  fi
  run_cmd defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$folder" || return 1
  run_cmd defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
}

# ---- 8. macOS defaults ----------------------------------------------------------
step_macos() {
  DRY_RUN="$DRY_RUN" bash "$DOTFILES_ROOT/macos/defaults.sh"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bats tests/steps-config.bats && shellcheck lib/steps.sh
```
Expected: `9 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add lib/steps.sh tests/steps-config.bats
git commit -m "feat(steps): add omz, version manager, link, iterm2 and macos steps"
```

---

### Task 13: `bootstrap.sh` entry point

**Files:**
- Create: `bootstrap.sh`
- Test: `tests/bootstrap.bats`

**Interfaces:**
- Consumes: everything in `lib/`
- Produces: `./bootstrap.sh [--dry-run] [--extra] [--no-brew] [--no-macos] [--help]`; exit 0 on success, 1 if any step failed, 2 on bad flags.

- [ ] **Step 1: Write the failing tests**

`tests/bootstrap.bats`:
```bash
load helpers

setup() {
  make_sandbox
  # Fake every external command the steps call.
  stub xcode-select 'exit 0'
  stub brew 'case "$*" in "--prefix nvm") exit 1;; shellenv) echo ":";; esac'
  stub git 'for a in "$@"; do last="$a"; done; mkdir -p "$last"'
  stub defaults 'case "$1" in read) exit 1;; esac'
  stub killall
  export BREW_BIN="$STUB_BIN/brew"
}

@test "--help prints usage and exits 0" {
  run "$REPO_ROOT/bootstrap.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--dry-run"* ]]
}

@test "unknown flag exits 2" {
  run "$REPO_ROOT/bootstrap.sh" --bogus
  [ "$status" -eq 2 ]
}

@test "--dry-run changes nothing in the sandbox home" {
  run "$REPO_ROOT/bootstrap.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [ ! -e "$HOME/.zshrc" ]
  [ ! -d "$HOME/.oh-my-zsh" ]
  [ ! -d "$HOME/.dotfiles-backup" ]
  [ "$(calls_matching 'defaults write')" -eq 0 ]
}

@test "full run links files, clones repos and is idempotent" {
  echo "old zshrc" > "$HOME/.zshrc"
  run "$REPO_ROOT/bootstrap.sh"
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.zshrc")" = "$REPO_ROOT/zsh/zshrc" ]
  [ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]
  [ -d "$HOME/.goenv" ]
  [ "$(calls_matching "brew bundle --file $REPO_ROOT/brew/Brewfile$")" -eq 1 ]
  [ "$(calls_matching 'Brewfile.extra')" -eq 0 ]
  [ "$(calls_matching 'defaults write com.apple.dock autohide')" -eq 1 ]
  # the old file was backed up, not deleted
  [ "$(cat "$HOME"/.dotfiles-backup/*/.zshrc)" = "old zshrc" ]

  local backups_before; backups_before="$(ls "$HOME/.dotfiles-backup" | wc -l)"
  : > "$CALL_LOG"
  run "$REPO_ROOT/bootstrap.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already linked"* ]]
  [ "$(calls_matching 'git clone')" -eq 0 ]
  [ "$(ls "$HOME/.dotfiles-backup" | wc -l)" -eq "$backups_before" ]
}

@test "--extra installs Brewfile.extra and --no-macos skips defaults" {
  run "$REPO_ROOT/bootstrap.sh" --extra --no-macos
  [ "$status" -eq 0 ]
  [ "$(calls_matching 'Brewfile.extra')" -eq 1 ]
  [ "$(calls_matching 'defaults write com.apple')" -eq 0 ]
}

@test "--no-brew skips homebrew steps" {
  run "$REPO_ROOT/bootstrap.sh" --no-brew --no-macos
  [ "$status" -eq 0 ]
  [ "$(calls_matching 'brew bundle')" -eq 0 ]
}

@test "a failing step is reported and the exit code is 1" {
  stub brew 'case "$*" in bundle*) exit 1;; "--prefix nvm") exit 1;; shellenv) echo ":";; esac'
  run "$REPO_ROOT/bootstrap.sh" --no-macos
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed steps:"* ]]
  [[ "$output" == *"Homebrew packages"* ]]
  # later steps still ran
  [ -L "$HOME/.zshrc" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bats tests/bootstrap.bats
```
Expected: 7 failures (`bootstrap.sh` not found).

- [ ] **Step 3: Write `bootstrap.sh`**

```bash
#!/usr/bin/env bash
# Set up a macOS machine from this repository. Safe to run more than once.
#
#   ./bootstrap.sh [--dry-run] [--extra] [--no-brew] [--no-macos] [--help]
#
# Steps: Xcode CLT -> Homebrew -> brew bundle -> oh-my-zsh -> goenv/nvm ->
#        symlinks -> iTerm2 prefs -> macOS defaults. A failing step is reported
#        at the end; the others still run.

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_ROOT

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [options]

  --dry-run   Print what would happen; change nothing.
  --extra     Also install brew/Brewfile.extra (hardware and audio apps).
  --no-brew   Skip the Homebrew install and `brew bundle`.
  --no-macos  Skip macos/defaults.sh.
  --help      Show this help.
EOF
}

DRY_RUN=0
INSTALL_EXTRA=0
SKIP_BREW=0
SKIP_MACOS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)  DRY_RUN=1 ;;
    --extra)    INSTALL_EXTRA=1 ;;
    --no-brew)  SKIP_BREW=1 ;;
    --no-macos) SKIP_MACOS=1 ;;
    --help|-h)  usage; exit 0 ;;
    *) printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
export DRY_RUN INSTALL_EXTRA

if [ "$(id -u)" = "0" ]; then
  printf 'Do not run bootstrap.sh as root.\n' >&2
  exit 1
fi

# shellcheck source=lib/common.sh
. "$DOTFILES_ROOT/lib/common.sh"
# shellcheck source=lib/link.sh
. "$DOTFILES_ROOT/lib/link.sh"
# shellcheck source=lib/steps.sh
. "$DOTFILES_ROOT/lib/steps.sh"

[ "$DRY_RUN" = "1" ] && log_info "Dry run: nothing will be changed"

run_step "Xcode Command Line Tools" step_xcode
if [ "$SKIP_BREW" = "1" ]; then
  log_skip "Homebrew (--no-brew)"
else
  run_step "Homebrew" step_homebrew
  run_step "Homebrew packages" step_brew_bundle
fi
run_step "oh-my-zsh, plugins and theme" step_omz
run_step "Version managers (goenv, nvm)" step_version_managers
run_step "Symlinks" step_links
run_step "iTerm2 preferences" step_iterm2
if [ "$SKIP_MACOS" = "1" ]; then
  log_skip "macOS defaults (--no-macos)"
else
  run_step "macOS defaults" step_macos
fi

printf '\n'
if [ "${#FAILED_STEPS[@]}" -eq 0 ]; then
  log_ok "All steps finished. Open a new terminal window."
  exit 0
fi
log_err "Failed steps:"
for step in "${FAILED_STEPS[@]}"; do
  printf '  - %s\n' "$step"
done
exit 1
```

```bash
chmod +x bootstrap.sh
```

- [ ] **Step 4: Run all tests and lint**

```bash
bats tests/ && shellcheck bootstrap.sh lib/*.sh macos/defaults.sh
```
Expected: all tests pass (helpers 2 + common 8 + link 9 + zsh 4 + brew 2 + macos 2 + secrets 3 + manifest 2 + steps-brew 7 + steps-config 9 + bootstrap 7 = 55), shellcheck silent.

- [ ] **Step 5: Commit**

```bash
git add bootstrap.sh tests/bootstrap.bats
git commit -m "feat: add bootstrap entry point with flags and step summary"
```

---

### Task 14: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write `README.md`**

```markdown
# dotfiles

My macOS setup: shell, tools, apps, preferences and app configs. One command
takes a blank Mac to this setup.

## Install

```bash
git clone https://github.com/EmadMokhtar/dotfiles.git ~/Projects/dotfiles
cd ~/Projects/dotfiles
./bootstrap.sh
```

Then open a new terminal window. Sign in to `gh` (`gh auth login`), 1Password
and the App Store yourself; the script does not handle logins.

### Flags

| Flag | Effect |
|---|---|
| `--dry-run` | Print every action; change nothing. Run this first. |
| `--extra` | Also install `brew/Brewfile.extra` (Elgato, Steinberg, IK Multimedia, REAPER, ...). |
| `--no-brew` | Skip Homebrew and `brew bundle` (fast re-link of configs). |
| `--no-macos` | Skip `macos/defaults.sh`. |

The script is safe to run again at any time: existing files are moved to
`~/.dotfiles-backup/<timestamp>/`, never deleted, and already-done steps are skipped.

## What is where

| Folder | Contents |
|---|---|
| `zsh/` | `.zshrc`, `.zprofile`, `.p10k.zsh` and the modules they load |
| `git/` | `.gitconfig`, global ignore |
| `brew/` | `Brewfile` (core), `Brewfile.extra` (hardware/audio) |
| `macos/` | `defaults.sh` — system preferences |
| `editors/zed/` | Zed `settings.json` |
| `claude/` | Claude Code settings, `CLAUDE.md`, hooks, skills, status line |
| `iterm2/` | iTerm2 preferences (iTerm2 reads and writes this file directly) |
| `links.txt` | Which repo file is symlinked where |

## Machine-specific values

Copy `zsh/local.zsh.example` to `~/.config/zsh/local.zsh` and edit. It is
sourced last and never committed.

## Installed by hand (no Homebrew cask)

Kerlig, TinkerTool, XP-Pen driver, Neural DSP, Hermes Agent, Zima, CubeSuite,
Cubase (via Steinberg Download Assistant), AmpliTube/TONEX (via IK Product
Manager). App Store: Keynote, Pages, Numbers, GarageBand, Noir, Wipr, PiPer,
SimpleLogin.

## Development

```bash
bats tests/                                        # all tests
shellcheck bootstrap.sh lib/*.sh macos/defaults.sh # lint
```

Tests run in a temporary `HOME` with fake `brew`, `git`, `defaults` and
`killall`, so they never touch the real machine.

## Testing on a fresh Mac (optional)

1. In UTM, create a macOS VM (UTM downloads the installer) and finish the
   macOS setup assistant.
2. In the VM's Terminal: `xcode-select --install`, then clone this repo and
   run `./bootstrap.sh --dry-run`, then `./bootstrap.sh`.
3. Open a new terminal: the prompt, `node`, `pyenv` and `git config user.email`
   should all work. Casks that need a login (Setapp, Microsoft Office) may
   fail in a VM; that is expected.

## Known limits

- Apps that rewrite their config file by "write temp file, rename" replace the
  symlink with a plain file. Re-run `./bootstrap.sh --no-brew --no-macos` to
  re-link; the app's copy lands in `~/.dotfiles-backup/` for you to diff.
- `macos/defaults.sh` needs a log out / log in for keyboard and trackpad keys.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with install, flags and layout"
```

---

### Task 15: Real run on this machine and regression check

This task changes the live machine. Read every expected line before moving on.

**Files:** none new.

- [ ] **Step 1: Dry run and read the output**

```bash
./bootstrap.sh --dry-run 2>&1 | tee /tmp/dotfiles-dry-run.log | head -80
```
Expected: `skip` for Xcode CLT and Homebrew; `[dry-run] brew bundle ...`; `skip` for the 6 oh-my-zsh clones and goenv (all exist); `[dry-run] mkdir/mv/ln` for each of the 11 manifest entries; `[dry-run] defaults write ...` lines; exit 0. Nothing in `~` changed: `ls -l ~/.zshrc` is still a regular file.

- [ ] **Step 2: Real run**

```bash
./bootstrap.sh 2>&1 | tee /tmp/dotfiles-run.log | tail -40
```
Expected: `brew bundle` installs `nvm`, `ykman`, `shellcheck` and the casks for apps that were installed outside Homebrew. This takes a long time and may ask for your password. `brew bundle` passes `--adopt` to every cask, so an app already in `/Applications` is adopted (taken over by Homebrew without re-downloading) when its version matches the cask. A cask whose installed version differs fails with "does not match"; `pkg`-based casks (`microsoft-office`) re-run their installer. `nvm install --lts` runs. 11 files linked, originals in `~/.dotfiles-backup/<timestamp>/`. If any cask failed the last lines are `Failed steps:` / `Homebrew packages` and the exit code is 1 — that is the designed behaviour, continue to Step 2b.

- [ ] **Step 2b: Resolve adopted-version mismatches (only if Step 2 reported cask failures)**

For each cask named in the failure output, `brew install --cask --force <name>` replaces the app in `/Applications` with the cask's version (the app's own data and preferences live in `~/Library` and are untouched):

```bash
grep -E "does not match|already exists" /tmp/dotfiles-run.log
brew install --cask --force <name1> <name2> ...
brew bundle check --file brew/Brewfile
```
Expected: `The Brewfile's dependencies are satisfied.` If an app is one you do not want replaced, remove it from the Brewfile instead and note it under "Installed by hand" in the README.

- [ ] **Step 3: Verify links and backup**

```bash
ls -l ~/.zshrc ~/.zprofile ~/.p10k.zsh ~/.gitconfig ~/.config/git/ignore ~/.config/zed/settings.json ~/.claude/settings.json ~/.claude/CLAUDE.md ~/.claude/statusline-command.sh ~/.claude/hooks ~/.claude/skills | awk '{print $9, $10, $11}'
ls ~/.dotfiles-backup/
```
Expected: every path is `-> /Users/emadmokhtar/Projects/dotfiles/...`; one timestamped backup directory plus `baseline/`.

- [ ] **Step 4: Shell regression diff against the Task 1 baseline**

```bash
zsh -lic 'alias' | sort | diff ~/.dotfiles-backup/baseline/aliases.txt - ; echo "alias diff exit: $?"
zsh -lic 'print -l ${(k)functions}' | sort | diff ~/.dotfiles-backup/baseline/functions.txt - ; echo "functions diff exit: $?"
zsh -lic 'env' | cut -d= -f1 | sort | diff ~/.dotfiles-backup/baseline/env-names.txt - ; echo "env diff exit: $?"
zsh -lic 'print -l ${(s.:.)PATH}' | diff ~/.dotfiles-backup/baseline/path.txt - ; echo "path diff exit: $?"
```
Expected aliases removed (`<` lines): `keyboard_setup`, `standup_list`, `portainer_run`, `zashconfig-nano`, `ohmyzsh`; changed: `flush_dns`, `ovim`. Functions added: `path_prepend`, `path_append`, `add_path_if_dir`, and the `nvm`/`nvm_*` functions that nvm.sh defines (nvm is new on this machine); nothing removed. Env: `DEFAULT_VENV_PY`, `OLLAMA_MODELS`, `OPENAUDIBLE_HOME` gone; `DOTFILES`, `NVM_DIR`, `NVM_BIN`, `NVM_INC`, `NVM_CD_FLAGS`, `HOMEBREW_PREFIX/CELLAR/REPOSITORY` added. PATH: `/usr/local/*` and windsurf entries gone; `~/.nvm/versions/node/<version>/bin` added; order otherwise the same. Anything else is a bug — fix the module, re-run this step.

- [ ] **Step 5: Prompt and tools work**

Open a new iTerm2 window (so it loads prefs from the repo) and run:
```bash
echo "$DOTFILES"; node --version; pyenv --version; goenv --version; j --version 2>/dev/null | head -1; git config user.email
```
Expected: repo path; `v22.x` or newer LTS (or whatever `nvm alias default` points to); pyenv/goenv versions; git email `me@emadmokhtar.com`. The p10k prompt renders with icons.

- [ ] **Step 6: Second run is a no-op**

```bash
./bootstrap.sh --no-brew 2>&1 | grep -cE 'already linked|exists|already' ; ls ~/.dotfiles-backup/ | wc -l
```
Expected: 18 or more "already" lines (11 links + 6 clones + goenv); the backup directory count is unchanged from Step 3.

- [ ] **Step 7: Restore machine-specific values**

```bash
mkdir -p ~/.config/zsh && cp zsh/local.zsh.example ~/.config/zsh/local.zsh
sed -i '' 's/^# export OLLAMA_MODELS/export OLLAMA_MODELS/; s/^# export OPENAUDIBLE_HOME/export OPENAUDIBLE_HOME/' ~/.config/zsh/local.zsh
zsh -lic 'echo $OLLAMA_MODELS'
```
Expected: `/Volumes/External`.

- [ ] **Step 8: Final test pass, secrets scan, commit**

```bash
bats tests/ && shellcheck bootstrap.sh lib/*.sh macos/defaults.sh
git status --short
```
Expected: all tests pass; `git status` shows only changes iTerm2 may have written to `iterm2/com.googlecode.iterm2.plist` (commit those with `chore(iterm2): sync preferences`) or nothing.

```bash
git add -A && git commit -m "chore: sync configs after first bootstrap run" || echo "nothing to commit"
```

- [ ] **Step 9: Create the GitHub repository (asks you first)**

Ask the user before running: this publishes the repo. Then:
```bash
gh repo create EmadMokhtar/dotfiles --public --source . --remote origin --push
```
Expected: repo created and `main` pushed.
