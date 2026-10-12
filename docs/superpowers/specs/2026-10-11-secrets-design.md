# Secrets management — design

Date: 2026-10-11
Status: draft, waiting for review
Builds on: [2026-09-17-dotfiles-bootstrap-design.md](2026-09-17-dotfiles-bootstrap-design.md)
(that spec listed "secrets management" as a non-goal; this spec adds it)

## 1. Goal

A way to give secrets (API keys, tokens) to a program **only when you start that
program**, without exporting them into every shell and without putting any value
in the public repository.

Each secret has one source:

- typed by hand and stored in the macOS login keychain, or
- read from your 1Password vault, or
- produced by a command (for example `gh auth token`).

It works for command-line programs (`secret run`) and for macOS GUI apps
(`secret open`).

Non-goals:

- Protection from malware that runs as your user (see §9).
- Linux in this phase. macOS comes first; Linux is the next phase (see §6,
  "Platform layer and Linux").
- Setting variables for every shell or for the whole GUI session (see §10).

## 2. Decisions

| Question | Decision |
|---|---|
| Delivery | On demand, per command or per app. Nothing is exported at shell start. |
| Manual values | macOS login keychain, written with `security`. No plaintext file. |
| 1Password | `op read` on a secret reference (`op://Vault/Item/field`). |
| Where names and references live | Untracked file `~/.config/secrets/secrets.map`. A tracked `secrets/secrets.map.example` is the template. |
| Tool | One bash script, `bin/secret`, linked to `~/.local/bin/secret`. |
| GUI apps | `secret open <App>`, which starts the app with its secrets. No `launchctl setenv` session mode. |
| Missing secret | Fail closed: the command or app does not start. `--optional` turns this into a warning. |
| Existing code | The `claude()` wrapper in `zsh/tools.zsh` is migrated to `secret run`. |
| Platforms | macOS now, Linux next. OS-specific code sits in a few functions, so Linux adds a backend and not a rewrite (§6). |

## 3. Files

```
dotfiles/
├── bin/secret                       the tool (bash)
├── secrets/secrets.map.example      template, copied by bootstrap if no map exists
├── links.txt                        + bin/secret  ~/.local/bin/secret
├── lib/steps.sh                     + step_secrets_map
├── bootstrap.sh                     + run_step "Secrets map" step_secrets_map
├── zsh/tools.zsh                    claude() calls `secret run`
├── tests/secret.bats                new
├── tests/steps-config.bats          + step_secrets_map cases
├── tests/zsh.bats                   + claude() wrapper case
└── README.md                        + "Secrets" section
```

Outside the repo (never committed):

```
~/.config/secrets/            mode 700
~/.config/secrets/secrets.map mode 600
```

`~/.local/bin` is already on `PATH` (`zsh/path.zsh`).

## 4. The map file

One entry per line. Blank lines and lines starting with `#` are ignored.

```
# <NAME>                         <source>
OPENAI_API_KEY                   op://Personal/OpenAI/credential
GITLAB_TOKEN                     keychain
GITHUB_PERSONAL_ACCESS_TOKEN     cmd:gh auth token

# app <App name>                 <NAME>[,<NAME>...]
app Claude                       GITHUB_PERSONAL_ACCESS_TOKEN
app Zed                          OPENAI_API_KEY,GITLAB_TOKEN
```

### Secret lines

- `NAME` matches `[A-Za-z_][A-Za-z0-9_]*`. It is the environment variable name.
  The name `app` is reserved.
- `source` is the rest of the line after the whitespace that follows `NAME`:
  - `keychain` — read from the login keychain (service `dotfiles-secrets`,
    account `NAME`).
  - `op://...` — a 1Password secret reference. Read with `op read`.
  - `cmd:<command>` — run `<command>` with `bash -c`. Standard output, without
    the final newline, is the value.
- A `NAME` that appears twice is an error that names both line numbers.

### App lines

- Format: `app`, then the app name, then the list of secret names.
- The list is the **last** whitespace-separated field. The app name is
  everything between `app` and that field, so names with spaces work
  (`app Visual Studio Code  OPENAI_API_KEY`).
- A line needs at least an app name and a list, so `app Zed` alone is an error.
- The list is comma-separated, with no spaces. Every name in it must have a
  secret line, otherwise the map is invalid.
- The same app may appear on several lines. The lists are merged in file order.

### Map safety

The map can contain `cmd:` lines, so a writable map is a code-execution risk.
`secret` refuses to read the map, and says why, when the file:

- is not owned by the current user, or
- has any group or other write bit set (mode & 022).

A map that is a symlink is checked through the link: the owner and mode of the
file that is really read count, not those of the link.

## 5. Commands

All commands exit with:

- `0` on success (for `run`, the exit code is the program's own, because of `exec`),
- `1` when a secret or app cannot be resolved,
- `2` for a usage error.

### `secret set NAME`

1. If `NAME` is in the map with a source other than `keychain`, stop with an
   error. (This prevents hiding a 1Password reference behind a stored value.)
2. Ask for the value twice, with hidden input. The prompts show only on a
   terminal; piped input must contain the value twice. Stop if the value is empty
   or the two values differ. Then send the value, as hex, on the standard input of
   `security -i`, as one command:
   `add-generic-password -U -a NAME -s dotfiles-secrets -X <hex>`.
   The value is never in a command line. The script reads the value itself
   because the prompt of `security ... -w` cuts a value at 128 characters, and
   real keys are longer. A value can have at most 1500 bytes, because
   `security -i` reads lines of at most 4096 bytes; a longer value is refused
   with a message that points to an `op://` source.
3. If `NAME` is not in the map, append `NAME  keychain`. Create the directory
   (mode 700) and the file (mode 600) first if needed.

### `secret run [--optional] NAME... -- command [args...]`

1. Parse the names before `--`. Require at least one name and a command.
2. Resolve each name with its source (§6).
3. Export the values in the script's own process, then `exec command`. `exec`
   replaces the script, so no extra process stays in between.

If a name is not in the map, or its source fails or returns an empty value:

- default: print an error naming the secret and the reason, exit `1`, run nothing;
- `--optional`: print a warning, leave that variable unset, resolve the others,
  and run the command.

The map itself can also be unusable: missing, owned by someone else, writable by
other users, or with a syntax error. With `--optional`, `run` prints a warning
and starts the command without any secrets. Without it, `run` stops with exit
code `1`. This is for wrappers such as `claude()`, which must start even when the
map is broken. `open` and `set` always stop.

### `secret open [--optional] <App name>`

1. Collect the app's secret names from the map. Unknown app: error, exit `1`.
2. Find the bundle: `/Applications/<App>.app`, then `~/Applications/<App>.app`.
3. Read the executable name with `plutil -extract CFBundleExecutable raw` on
   `Contents/Info.plist`.
4. If any process runs from inside the bundle (`pgrep -f` on the bundle path),
   stop: "`<App>` is running. Quit it first; a running app keeps its old
   environment." Exit `1`.
5. Resolve the secrets as in `run`, then start `Contents/MacOS/<executable>` in a
   subshell with the values exported, detached with `nohup` and `&`, output sent
   to `/dev/null`.

Launch verification (done once during implementation, with Zed and Claude):
the app starts, its processes have the variables, and it keeps running after the
terminal closes. If direct start fails this check, fall back to
`open -n --env NAME=VALUE ...`. That form puts the values in the argument list of
the short-lived `open` process, visible to `ps`; the README must say so.

Apps started from the Dock, Spotlight or Login Items do not get secrets.
This is a known limit of the on-demand model.

### `secret list`

Prints each secret name with its source type (`1password`, `keychain`,
`command`) and each app with its secret names. It does not resolve anything and
never prints a value or a reference.

## 6. Resolving a value

| Source | Command | Notes |
|---|---|---|
| `keychain` | `security find-generic-password -a NAME -s dotfiles-secrets -w` | Item created by `secret set`. |
| `op://...` | `op read --no-newline <reference>` | Needs 1Password unlocked or signed in. |
| `cmd:...` | `bash -c '<command>'` | Must exit `0`. |

An empty value counts as a failure for every source. Standard error of the
source command is passed through, because it explains the failure ("not signed
in", "item not found").

### Platform layer and Linux

`bin/secret` is written for bash 3.2, the version macOS ships: no associative
arrays and no `mapfile`.

Everything that depends on the operating system is in five functions. A
`case "$(uname -s)"` picks the implementation:

| Function | macOS (this phase) | Linux (next phase) |
|---|---|---|
| `os_store_get NAME` | `security find-generic-password … -w` | `secret-tool lookup service dotfiles-secrets account NAME` |
| `os_store_set NAME` | the value on standard input, as hex, to `security -i` (`add-generic-password -U … -X`) | `secret-tool store` with the value on standard input |
| `os_file_owner_mode PATH` | `stat -f '%u %Lp'` | `stat -c '%u %a'` |
| `os_app_executable APP` | `.app` bundle and `plutil` | the `Exec=` line of a `.desktop` file in `~/.local/share/applications` or `/usr/share/applications` |
| `os_app_running APP` | `pgrep -f` on the bundle path | `pgrep -f` on the executable path |

`secret-tool` is the libsecret command-line client. libsecret talks to the Secret
Service API (the desktop keyring, for example GNOME Keyring or KWallet).

The rest is the same on both systems: map parsing, `op read`, `cmd:`, `run`,
`list`, and the rules in §7.

In this phase, any OS other than Darwin stops with `unsupported OS: <name>
(macOS only for now)` and exit code `1`.

Linux notes for the next phase:

- A headless machine has no desktop keyring. There the `keychain` source will not
  work, but `op://` and `cmd:` will. The Linux phase decides how to handle this.
- The rest of the repo (`bootstrap.sh`, Homebrew, `defaults`) is still macOS-only.
  Making `bin/secret` work on Linux does not make bootstrap work on Linux. That is
  a separate project.

## 7. Value handling rules

- A value lives only in a shell variable inside the process that runs the
  command (for `open`, a subshell that starts the app). It is never written to a
  file, a log, or an error message.
- A value is never an argument of another command (so `ps` cannot show it),
  with the one documented fallback in §5.
- `set -x` is never enabled in `bin/secret`.
- Error messages contain names and reasons, never values or 1Password references.

## 8. Migration and bootstrap

### `claude()` wrapper

In `zsh/tools.zsh`, the block that reads `gh auth token` becomes:

```zsh
# ---- Claude Code: secrets from `secret` -------------------------------------
# The GitHub MCP plugin reads ${GITHUB_PERSONAL_ACCESS_TOKEN}. `secret` reads it
# (see ~/.config/secrets/secrets.map) and gives it to this one process only.
# --optional: start claude even when the token cannot be read.
if command -v secret >/dev/null 2>&1; then
  claude() { secret run --optional GITHUB_PERSONAL_ACCESS_TOKEN -- claude "$@"; }
fi
```

`secret` runs the real `claude` binary. A zsh function is not visible to a bash
script, so there is no recursion. If `secret` is not installed, no function is
defined and `claude` runs unchanged.

Behavior change: when the token cannot be read, the old wrapper stayed silent
and the new one prints a warning on every start. This is intended.

### Bootstrap step

`step_secrets_map` runs after "Symlinks". If `~/.config/secrets/secrets.map` does
not exist, it creates the directory (mode 700) and copies
`secrets/secrets.map.example` to it (mode 600). It never overwrites an existing
map. It honors `--dry-run`.

### Template: `secrets/secrets.map.example`

```
# Copy of this file is created at ~/.config/secrets/secrets.map by bootstrap.
# The copy is NOT tracked in git. Edit the copy, not this file.
#
# <NAME>   <source>
#   keychain          value typed with `secret set NAME`, stored in the login keychain
#   op://V/I/F        1Password reference (vault / item / field)
#   cmd:<command>     value is the output of the command
#
# app <App name>   <NAME>[,<NAME>...]
#   `secret open "<App name>"` starts the app with these secrets.

GITHUB_PERSONAL_ACCESS_TOKEN   cmd:gh auth token
app Claude                     GITHUB_PERSONAL_ACCESS_TOKEN

# Examples (fake names):
# EXAMPLE_API_KEY              op://Personal/Example/credential
# EXAMPLE_TOKEN                keychain
# app Example App              EXAMPLE_API_KEY,EXAMPLE_TOKEN
```

The template has no vault names and no values, so the existing scan in
`tests/secrets.bats` still passes.

## 9. Security model

Protects against:

- secrets in the environment of every shell and every child process;
- secrets in the public repository, in dotfiles, or in shell history
  (history shows names only);
- a value on a command line.

Does **not** protect against malware or another process running as your user.
Such a process can call `security find-generic-password`, and `security` is on the
keychain item's access list because it created the item. It can also read the
environment of a running app. This design reduces accidental exposure; it is not
a sandbox.

## 10. Out of scope (possible later)

- `secret session on/off` (`launchctl setenv`): gives all GUI apps a secret,
  including Dock launches, with wide exposure.
- Named groups of secrets (`group aws = A,B,C`).
- `secret rm`, and shell completion for names.
- Fixing apps started outside `secret open`. A Raycast script command that calls
  `secret open` is a way to start apps without a terminal.

## 11. Testing

Tests use the existing `make_sandbox` and `stub` helpers. `op`, `security`, `gh`,
`pgrep` and an app bundle (a folder with `Info.plist` and a script) are fakes.
Test values are fake strings.

`tests/secret.bats`:

- Map: comments and blank lines; app names with spaces; merged app lines;
  duplicate `NAME`; invalid `NAME`; reserved name `app`; app list with an
  unknown name; refusal when the map is group-writable or foreign-owned.
- `set`: sends the value as hex on the standard input of `security -i`, never in
  arguments, and a long value with spaces and quotes arrives intact; refuses an
  empty, differing or too long (over 1500 bytes) value; appends to the map;
  creates directory (700) and file (600); refuses a name that has a non-keychain
  source.
- A map that is a symlink to a group-writable file is refused; one to a private
  file is accepted.
- `run`: injects values from all three source types; unknown name fails; one
  failing source aborts and the command does not run; empty value fails;
  `--optional` warns and still runs; exit code of the command is passed through;
  `--` and a command are required.
- No value appears in `CALL_LOG` arguments, in error output, or in `list` output.
- `open`: starts the fake app with the right variables; unknown app; bundle not
  found; app already running (`pgrep` stub) refuses.
- `list`: names and types only.
- Unsupported OS: with a `uname` stub that prints `Linux`, every command stops
  with the "macOS only for now" error and exit code `1`.
- `bin/secret` passes `shellcheck`, and runs under bash 3.2 (`/bin/bash` on macOS).

`tests/steps-config.bats`: `step_secrets_map` seeds a missing map with modes 700
and 600; does not overwrite an existing map; makes no change under `--dry-run`.

`tests/zsh.bats`: with `secret` on `PATH`, `claude` is a function that runs
`secret run --optional GITHUB_PERSONAL_ACCESS_TOKEN -- claude`; without `secret`,
it is not.

`tests/secrets.bats` (existing): must still pass.

Manual acceptance (once, after implementation):

1. `secret set` stores a value; `secret run NAME -- sh -c 'echo "${NAME:+set}"'`
   prints `set`; the value does not appear in `ps` or shell history.
2. An `op://` entry resolves with 1Password unlocked, and fails with a clear
   message when `op` is signed out.
3. `secret open Claude` (with Claude quit) gives the Claude desktop app a
   working GitHub MCP connection.

## Glossary

- **Secret reference**: a text pointer to a 1Password field, like
  `op://Vault/Item/field`. It holds no secret.
- **Keychain**: the macOS encrypted store for passwords. The *login keychain*
  unlocks when you log in.
- **`exec`**: replaces the current process with a new program, so no extra
  process stays in between.
- **Subshell**: a child shell. Variables exported inside it do not affect the
  parent shell.
- **Fail closed**: when something goes wrong, refuse to continue instead of
  continuing with less protection.
- **`argv`**: the list of arguments given to a program. Other processes of the
  same user can read it with `ps`.
- **launchd**: the macOS process that starts all other processes, including GUI
  apps. It does not read your shell startup files.
- **libsecret / Secret Service**: the Linux standard for storing secrets in the
  desktop keyring. `secret-tool` is its command-line client.
- **`.desktop` file**: a Linux text file that describes how to start a GUI app.
  It is the Linux counterpart of a macOS `.app` bundle.
