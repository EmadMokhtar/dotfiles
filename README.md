# dotfiles

My macOS setup: shell, tools, apps, preferences and app configs. One command
takes a blank Mac to this setup.

## Install

```bash
git clone https://github.com/EmadMokhtar/dotfiles.git ~/Projects/dotfiles
cd ~/Projects/dotfiles
./bootstrap.sh
```

Run it from Terminal, not from a script or an automation: several casks
(Docker Desktop, Microsoft Office, Zoom, …) install with `sudo` and must be
able to ask for your password. Without a terminal the Homebrew step is
skipped.

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
- Homebrew 6 installs casks concurrently; the bootstrap sets
  `HOMEBREW_DOWNLOAD_CONCURRENCY=1` to avoid `hdiutil: Resource busy`
  failures. If a cask still fails, run `brew install --cask --adopt <name>`
  for it.
