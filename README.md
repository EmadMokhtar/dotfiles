# dotfiles

My macOS setup: shell, tools, apps, preferences and app configs. One command
takes a blank Mac to this setup.

Apple Silicon only (`/opt/homebrew`).

## Install

```bash
git clone https://github.com/EmadMokhtar/dotfiles.git ~/Projects/dotfiles
cd ~/Projects/dotfiles
./bootstrap.sh
```

Run it from Terminal, not from a script or an automation: several casks
(Docker Desktop, Microsoft Office, Zoom, …) install with `sudo` and must be
able to ask for your password. Without a terminal, the "Homebrew packages"
step (`brew bundle`) is reported as failed (exit 1) and skipped — Homebrew
itself, installed by the earlier "Homebrew" step, is unaffected and stays
installed.

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
`~/.dotfiles-backup/<timestamp>/`, never deleted, and already-done steps are
skipped. `brew bundle` also upgrades any outdated package on every run, so
re-running keeps everything in the Brewfile current.

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
| `bin/` | `secret` — gives secrets to a program or app when it starts |
| `secrets/` | `secrets.map.example` — template for the secrets map (the real map is not in git) |
| `lib/` | Bootstrap helpers (`common.sh`, `link.sh`, `steps.sh`) sourced by `bootstrap.sh` |
| `tests/` | bats tests for the bootstrap scripts |
| `docs/` | Design spec and plan this bootstrap was built from |
| `links.txt` | Which repo file is symlinked where |

## Machine-specific values

Copy `zsh/local.zsh.example` to `~/.config/zsh/local.zsh` and edit. It is
sourced last and never committed.

## Claude Code settings

`~/.claude/settings.json` is a normal file, not a symlink. Tools such as the
StreamDeck plugin and iTerm2 add their own hooks to it by writing a new file
over it, which would replace a symlink. `claude/settings.json` holds only the
portable settings, and bootstrap merges them into the live file:

- Keys that only the live file has stay, for example a tool's hooks.
- For a value that both files set, the repo wins. Bootstrap prints which keys
  it changed, and saves the old file in `~/.dotfiles-backup/<time>/`.
- A hook with the same matcher and command is replaced, not added twice.
  `~/x` and `/Users/me/x` count as the same command.

The rules are in `lib/claude-settings-merge.jq`. A change made only in the
live file does not go back to the repo. Copy it into `claude/settings.json`
by hand if every machine should have it.

## Secrets

`bin/secret` gives secrets to a program only when you start it. Nothing is
exported at shell start and no value is stored in this repo. macOS only for now.

Each secret has a name and one source. They are listed in
`~/.config/secrets/secrets.map`, which is not tracked in git. Bootstrap creates
it from `secrets/secrets.map.example` and never overwrites it.

| Source | Meaning |
|---|---|
| `keychain` | You type the value once with `secret set NAME`. It is kept in the login keychain. |
| `op://Vault/Item/field` | Read from 1Password with `op read`. |
| `cmd:<command>` | The output of a command, for example `cmd:gh auth token`. |

```bash
secret set OPENAI_API_KEY                      # type the value twice (hidden); kept in the keychain
secret run OPENAI_API_KEY -- some-tool --flag  # run one program with the secret
secret open Zed                                # start a macOS app with its secrets
secret list                                    # names and sources, never values
```

An app gets the secrets on its `app` lines in the map. Use commas for several,
or repeat the line:

```
app Zed    OPENAI_API_KEY,ANTHROPIC_API_KEY
app Zed    OLLAMA_API_KEY
```

The Claude desktop app is on an `app Claude` line. Quit it, then start it from
a terminal with `secret open Claude`. Its Code sessions sign in with the app's
own account and drop `CLAUDE_CODE_OAUTH_TOKEN`, so it needs only the GitHub
token. The app also copies the exported variables of your login shell, so never
export a secret in `zshrc`.

Rules and limits:

- `secret set` takes values up to 1500 bytes. For a longer one, use an
  `op://` source. A value is never passed on a command line.
- If a secret cannot be read, nothing starts. `--optional` turns this into a
  warning and the program starts without that secret. `claude` uses it.
- `secret open` stops if the app is already running. Quit it first: a running app
  keeps the environment it started with.
- An app started from the Dock, Spotlight or Login Items gets no secrets. Start
  it with `secret open`.
- The map can run commands (`cmd:` lines), so `secret` refuses to read it when
  another user owns it or can write it. Keep it at mode 600.
- This reduces accidental exposure. It does not protect against other
  programs running as you: they can call `security` too.

## Installed by hand (no Homebrew cask)

Kerlig, TinkerTool, XP-Pen driver, Neural DSP, Hermes Agent, Zima, CubeSuite,
Cubase (via Steinberg Download Assistant), AmpliTube/TONEX (via IK Product
Manager), Blackmagic Disk Speed Test. App Store: Keynote, Pages, Numbers,
GarageBand, Noir, Wipr, PiPer, SimpleLogin.

## Development

```bash
bats tests/                                                   # all tests
shellcheck bootstrap.sh lib/*.sh macos/defaults.sh bin/secret # lint
```

Tests run in a temporary `HOME` with fake `brew`, `git`, `defaults`,
`killall`, `op` and `security`, so they never touch the real machine.

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
- Homebrew 6 installs casks concurrently; the bootstrap sets
  `HOMEBREW_DOWNLOAD_CONCURRENCY=1` to avoid `hdiutil: Resource busy`
  failures. If a cask still fails, run `brew install --cask --adopt <name>`
  for it.
- iTerm2 rewrites `iterm2/com.googlecode.iterm2.plist` on quit. Review its
  diff before committing — it can carry machine-specific state you did not
  mean to check in.
