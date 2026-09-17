# Dotfiles bootstrap — design

Date: 2026-09-17
Status: approved for implementation
Baseline machine: Apple Silicon Mac, macOS (Darwin 25.6), zsh + oh-my-zsh + powerlevel10k

## 1. Goal

One public git repository that can take a blank macOS machine to this machine's
setup with a single command:

```bash
git clone https://github.com/EmadMokhtar/dotfiles ~/Projects/dotfiles
cd ~/Projects/dotfiles && ./bootstrap.sh
```

It manages four layers:

1. Shell, git and editor configuration files (symlinked into `~`).
2. Packages and apps via Homebrew (`Brewfile`, optional `Brewfile.extra`).
3. macOS system preferences via `defaults write`.
4. App-specific configuration (Zed, Claude Code, iTerm2).

Non-goals: secrets management, Linux support, App Store apps, hardware driver
installers that have no Homebrew cask.

## 2. Decisions

| Question | Decision |
|---|---|
| Linking tool | Plain `bash` script + symlinks. No stow/chezmoi. |
| Repo layout | Topic folders + explicit `links.txt` manifest. |
| Shell config | Cleaned and split into modules (see §5). |
| GUI apps | Two tiers: `Brewfile` (core) and `Brewfile.extra` (hardware/audio). |
| Visibility | Public. No secrets, no host aliases, no history files. |
| macOS prefs | Captured from this machine's current values (see §7). |

## 3. Repository layout

```
dotfiles/
├── bootstrap.sh              entry point; runs steps in order; idempotent
├── links.txt                 manifest: <repo path> <home path>, one per line
├── lib/common.sh             helpers: log, run (honours --dry-run), link_file
├── brew/
│   ├── Brewfile              taps, formulae, core casks, fonts
│   └── Brewfile.extra        hardware / audio / music casks
├── zsh/
│   ├── zshrc                 → ~/.zshrc
│   ├── zprofile              → ~/.zprofile
│   ├── p10k.zsh              → ~/.p10k.zsh (unchanged copy)
│   ├── path.zsh              PATH entries, each guarded by a directory check
│   ├── exports.zsh           environment variables
│   ├── tools.zsh             pyenv, goenv, autojump, wt, completions, gh token
│   ├── aliases.zsh
│   ├── functions.zsh
│   └── local.zsh.example     template for machine-specific values
├── git/
│   ├── gitconfig             → ~/.gitconfig
│   └── ignore                → ~/.config/git/ignore
├── editors/zed/
│   ├── settings.json         → ~/.config/zed/settings.json (token removed)
│   ├── themes/               → ~/.config/zed/themes
│   └── prompts/              → ~/.config/zed/prompts
├── claude/
│   ├── settings.json         → ~/.claude/settings.json
│   ├── CLAUDE.md             → ~/.claude/CLAUDE.md
│   ├── statusline-command.sh → ~/.claude/statusline-command.sh
│   ├── hooks/                → ~/.claude/hooks
│   └── skills/               → ~/.claude/skills
├── iterm2/
│   └── com.googlecode.iterm2.plist   loaded via PrefsCustomFolder
├── macos/defaults.sh         `defaults write` lines + killall
├── docs/superpowers/specs/   this document
└── README.md                 usage, flags, manual-install list
```

`~/.config/zsh/local.zsh` is **not** in the repo. `zshrc` sources it if it
exists. It holds values that only make sense on one machine (see §5.3).

## 4. Bootstrap flow

`bootstrap.sh` is written for the `bash` that ships with macOS (3.2). It does
not use `set -e`; each step logs its result and the script continues, so one
failing brew cask does not stop the symlink step. It exits non-zero at the end
if any step failed.

Flags:

| Flag | Effect |
|---|---|
| `--dry-run` | Print every command that would run; change nothing. |
| `--extra` | Also install `brew/Brewfile.extra`. |
| `--no-macos` | Skip `macos/defaults.sh`. |
| `--no-brew` | Skip Homebrew install and `brew bundle` (useful for config-only re-runs). |

Steps, in order. Every step is idempotent (running it a second time changes
nothing):

1. **Xcode Command Line Tools** — `xcode-select -p` succeeds → skip; else
   `xcode-select --install` and wait for the user to finish the GUI dialog.
2. **Homebrew** — `/opt/homebrew/bin/brew` exists → skip; else run the official
   install script. Then `eval "$(/opt/homebrew/bin/brew shellenv)"` for the rest
   of the run.
3. **`brew bundle`** — `brew bundle --file brew/Brewfile`; with `--extra` also
   `brew bundle --file brew/Brewfile.extra`. Homebrew itself skips installed
   items.
4. **oh-my-zsh and add-ons** — `git clone` (depth 1) each if its directory is
   missing:
   - `ohmyzsh/ohmyzsh` → `~/.oh-my-zsh` (cloned directly, not via the installer,
     so it never touches `~/.zshrc`)
   - `zsh-users/zsh-autosuggestions`, `zsh-users/zsh-syntax-highlighting`,
     `zsh-users/zsh-completions`, `TamCore/autoupdate-oh-my-zsh-plugins` →
     `~/.oh-my-zsh/custom/plugins/<name>`
   - `romkatv/powerlevel10k` → `~/.oh-my-zsh/custom/themes/powerlevel10k`
5. **goenv** — `git clone go-nv/goenv` → `~/.goenv` if missing. pyenv comes
   from Homebrew, including `pyenv-virtualenv`.
6. **Symlinks** — for each line in `links.txt`: create the parent directory of
   the target; if the target exists and is not already the wanted symlink,
   move it to `~/.dotfiles-backup/<YYYYMMDD-HHMMSS>/<same relative path>`;
   then `ln -s`. Directory targets (e.g. `claude/skills`) are linked as one
   symlink, not file by file.
7. **iTerm2 preferences** — `defaults write com.googlecode.iterm2
   PrefsCustomFolder "<repo>/iterm2"` and `LoadPrefsFromCustomFolder 1`.
8. **macOS defaults** — run `macos/defaults.sh` unless `--no-macos`.
9. **Summary** — list steps done / skipped / failed, and remind the user to
   open a new terminal.

Not done on purpose: `chsh` (macOS already defaults to zsh); signing in to
`gh`, 1Password, App Store; installing Python/Go versions (pyenv/goenv are
installed, versions are a per-project choice).

`links.txt` format: two whitespace-separated columns, `#` comments allowed,
`~` expanded for the target.

```
zsh/zshrc                 ~/.zshrc
zsh/zprofile              ~/.zprofile
zsh/p10k.zsh              ~/.p10k.zsh
git/gitconfig             ~/.gitconfig
git/ignore                ~/.config/git/ignore
editors/zed/settings.json ~/.config/zed/settings.json
editors/zed/themes        ~/.config/zed/themes
editors/zed/prompts       ~/.config/zed/prompts
claude/settings.json      ~/.claude/settings.json
claude/CLAUDE.md          ~/.claude/CLAUDE.md
claude/statusline-command.sh ~/.claude/statusline-command.sh
claude/hooks              ~/.claude/hooks
claude/skills             ~/.claude/skills
```

## 5. Shell configuration

### 5.1 Load order

`~/.zprofile` (login shells only):
1. `eval "$(/opt/homebrew/bin/brew shellenv)"` if brew exists.
2. Login-only PATH additions that today live in `.zprofile`: Docker
   `~/.docker/bin`, JetBrains Toolbox scripts, python.org 3.12 framework,
   Obsidian CLI — each guarded by `[ -d ... ]`.

`~/.zshrc` (every interactive shell), in this order:
1. powerlevel10k instant-prompt block (must stay first).
2. oh-my-zsh settings: `ZSH`, `ZSH_THEME=powerlevel10k/powerlevel10k`,
   `ENABLE_CORRECTION`, `COMPLETION_WAITING_DOTS`, `UPDATE_ZSH_DAYS=1`,
   `ZSH_DOTENV_PROMPT=false`, the unchanged `plugins=(...)` list.
3. `source $ZSH/oh-my-zsh.sh`.
4. `source` each module from `$DOTFILES/zsh/`: `path.zsh`, `exports.zsh`,
   `tools.zsh`, `aliases.zsh`, `functions.zsh`. `DOTFILES` is resolved from
   the symlink target of `~/.zshrc` so the repo can live anywhere.
5. `setopt HIST_IGNORE_SPACE`.
6. `[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh`.
7. `[[ -f ~/.config/zsh/local.zsh ]] && source ~/.config/zsh/local.zsh`.

### 5.2 Module contents

**path.zsh** — every entry wrapped in a helper `path_prepend`/`path_append`
that checks the directory exists and is not already in `$PATH`:
`~/.local/bin`, `$(brew --prefix)/opt/postgresql@15/bin`, `~/.lmstudio/bin`.

**exports.zsh** — `PROJECT_HOME=$HOME/Projects`, `TERM=xterm-256color`,
`LANG`/`LC_ALL=en_US.UTF-8`, `GOSUMDB=sum.golang.org`, `GOPROXY=direct`,
`KUBE_CONFIG_PATH=~/.kube/config`, `OLLAMA_ORIGINS="app://obsidian.md*"`,
`OLLAMA_HOST=0.0.0.0`.

**tools.zsh** — each block guarded by `command -v` or a directory check:
- pyenv: `PYENV_ROOT`, PATH, `pyenv init --path`, `pyenv init -`,
  `pyenv virtualenv-init -`.
- goenv: `GOENV_ROOT`, PATH, `goenv init -`, then `$GOROOT/bin` and
  `$GOPATH/bin` on PATH.
- autojump: `source "$(brew --prefix)/etc/profile.d/autojump.sh"`.
- terraform completion (`bashcompinit` + `complete -C`).
- Docker CLI completions (`fpath` + `compinit`).
- worktrunk: `eval "$(command wt config shell init zsh)"`.
- `GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token 2>/dev/null)"` — kept; the
  token is read from gh's keychain at shell start, never stored.

**aliases.zsh** — kept: `zshconfig`, `vimdiff`, `vim`, `vi`, `ovim`, `gfgl`,
`dotfilesShow`, `dotfilesHide`, `k`, `kx`, `tf`, `dc`, `dk`, `fabric`
(guarded by file check). Fixed: `flush_dns` now runs
`sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder`.

**functions.zsh** — `mkd`, `gi`, `git_tag`, `git_force_tag`, unchanged.

### 5.3 Removed from today's `.zshrc` / `.zprofile`

| Item | Reason |
|---|---|
| `keyboard_setup` alias | Linux-only (`numlockx`, `/sys/module/hid_apple`). |
| `standup_list` alias | Uses pyenv 3.8.8 (not installed) and `~/Playground/...` (not present). |
| `portainer_run` alias | Contains a stray `k` argument; the command fails. |
| `zashconfig-nano`, `ohmyzsh` aliases | Typo alias; `nano` on a directory does nothing useful. |
| `DEFAULT_VENV_PY=3.9.10` | Referenced nowhere; version not installed. |
| `BULLETTRAIN_PROMPT_ORDER` | Bullet Train theme is not used. |
| `/usr/local/opt/gettext/bin`, `/usr/local/sbin` | Intel-Mac Homebrew paths; do not exist here. |
| `/usr/local/etc/profile.d/autojump.sh` | Intel path; replaced by `$(brew --prefix)`. |
| `~/.codeium/windsurf/bin` | Directory no longer exists. |
| All oh-my-zsh template comment blocks | Noise. |
| `OLLAMA_MODELS=/Volumes/External` | Machine-specific → `local.zsh.example`. |
| `OPENAUDIBLE_HOME=/Volumes/External/OpenAudible` | Machine-specific → `local.zsh.example`. |

## 6. Homebrew

### 6.1 `brew/Brewfile`

Taps — only the 4 that provide something installed today. The other 6 current
taps (`1password/tap`, `ngrok/ngrok`, `th-ch/youtube-music`, `grishka/grishka`,
`jlhonora/lsusb`, `homebrew/cask-fonts`) are dropped: their packages now come
from the main `homebrew/cask` / `homebrew/core` taps.

```
anomalyco/tap  codecrafters-io/tap  gentleman-programming/tap  jakehilborn/jakehilborn
```

Formulae — the current `brew leaves` minus pure libraries (`aom`, `jpeg-xl`,
`libass`, `librist`, `libsolv`, `portaudio`, `sdl12-compat`, `zlib` — they
return as dependencies), plus `pyenv`, `pyenv-virtualenv`, `shellcheck` and
`ykman`:

```
autojump bat cloudflared cmake cookiecutter ffmpeg gh git glow gnupg
golang-migrate golangci-lint helm just lsusb lychee minikube mycli neovim node
pgcli pinentry-mac postgresql@15 protobuf pyenv pyenv-virtualenv shellcheck
terraform tesseract uv wget worktrunk ykman yt-dlp
```

Tap formulae (full names so `brew bundle` knows the source):

```
anomalyco/tap/opencode  codecrafters-io/tap/codecrafters
gentleman-programming/tap/engram  gentleman-programming/tap/gentle-ai
gentleman-programming/tap/gga  jakehilborn/jakehilborn/displayplacer
```

Core casks (verified to exist in the index on 2026-09-17):

```
1password 1password-cli balenaetcher betterdisplay browserosaurus calibre
chatgpt claude codex copilot-cli discord docker-desktop dropbox firefox
google-chrome iterm2 jetbrains-toolbox lm-studio logi-options+ macwhisper
microsoft-office microsoft-teams ngrok obsidian ollama-app onedrive proton-mail
proton-mail-bridge protonvpn raspberry-pi-imager raycast setapp slack telegram
utm visual-studio-code vlc whatsapp youtube-music zed zoom
font-jetbrains-mono font-jetbrains-mono-nerd-font
```

### 6.2 `brew/Brewfile.extra`

```
caldigit-docking-utility elgato-control-center elgato-stream-deck
elgato-wave-link ik-product-manager ilok-license-manager
insta360-link-controller mediahuman-audio-converter openaudible openrgb
paragon-extfs qbittorrent reaper steinberg-download-assistant
```

### 6.3 Not managed (README "manual installs")

No cask exists: Kerlig, TinkerTool, XP-Pen driver, Neural DSP, Hermes Agent,
Zima, CubeSuite, Cubase, AmpliTube/TONEX (installed by IK Product Manager).
App Store: Keynote, Pages, Numbers, GarageBand, Noir, Wipr, PiPer, SimpleLogin,
Blackmagic Disk Speed Test.

## 7. macOS defaults (`macos/defaults.sh`)

Values captured from this machine on 2026-09-17. Only keys that are explicitly
set today are written. Grouped by domain; comments explain each line.

| Domain | Key | Value |
|---|---|---|
| NSGlobalDomain | AppleKeyboardUIMode | 0 |
| NSGlobalDomain | KeyRepeat | 2 |
| NSGlobalDomain | InitialKeyRepeat | 15 |
| NSGlobalDomain | ApplePressAndHoldEnabled | false |
| NSGlobalDomain | NSAutomaticCapitalizationEnabled | true |
| NSGlobalDomain | NSAutomaticPeriodSubstitutionEnabled | true |
| NSGlobalDomain | AppleInterfaceStyle | Dark |
| NSGlobalDomain | com.apple.swipescrolldirection | false |
| NSGlobalDomain | AppleLanguages | (en-US, en-NL, nl-NL, ar-NL) |
| NSGlobalDomain | AppleLocale | en_US@rg=nlzzzz |
| com.apple.finder | AppleShowAllFiles | true |
| com.apple.finder | ShowPathbar | true |
| com.apple.finder | ShowStatusBar | true |
| com.apple.finder | FXPreferredViewStyle | icnv |
| com.apple.finder | NewWindowTarget | PfHm |
| com.apple.finder | NewWindowTargetPath | file://$HOME/ |
| com.apple.finder | ShowExternalHardDrivesOnDesktop | false |
| com.apple.finder | ShowHardDrivesOnDesktop | false |
| com.apple.finder | ShowRemovableMediaOnDesktop | false |
| com.apple.dock | autohide | true |
| com.apple.dock | tilesize | 48 |
| com.apple.dock | orientation | bottom |
| com.apple.dock | show-recents | false |
| com.apple.dock | autohide-delay | 0 |
| com.apple.dock | autohide-time-modifier | 0 |
| com.apple.dock | showhidden | true |
| com.apple.dock | wvous-br-corner | 14 (Quick Note) |
| com.apple.dock | wvous-bl/tr/tl-corner | 0 |
| com.apple.AppleMultitouchTrackpad | Clicking | true |
| com.apple.AppleMultitouchTrackpad | TrackpadRightClick | true |
| com.apple.AppleMultitouchTrackpad | TrackpadThreeFingerDrag | false |
| com.apple.AppleMultitouchTrackpad | Dragging | false |
| com.apple.driver.AppleBluetoothMultitouch.trackpad | Clicking | true |
| com.apple.desktopservices | DSDontWriteNetworkStores | true |
| com.apple.menuextra.clock | ShowSeconds | true |
| com.apple.menuextra.clock | ShowDate | 0 |
| com.apple.HIToolbox | AppleFnUsageType | 2 |
| com.apple.WindowManager | GloballyEnabled | false (Stage Manager off) |
| com.apple.WindowManager | EnableTilingByEdgeDrag | true |
| com.apple.ActivityMonitor | ShowCategory | 100 |

The script ends with `killall Finder Dock SystemUIServer cfprefsd` so the
changes take effect. Keys that need Full Disk Access (Safari) are not included.

## 8. App configuration and exclusions

| App | In repo | Note |
|---|---|---|
| git | `gitconfig`, `ignore` | `gpg.ssh.program` keeps the absolute 1Password app path; `commit.gpgsign=false` as today. |
| Zed | `settings.json`, `themes/`, `prompts/` | `github_personal_access_token` line **removed**. `conversations/`, `settings_backup.json` excluded. |
| Claude Code | `settings.json`, `CLAUDE.md`, `statusline-command.sh`, `hooks/`, `skills/` | Everything else in `~/.claude` (sessions, cache, history, plugin cache, telemetry) excluded. |
| iTerm2 | `com.googlecode.iterm2.plist` | Exported once from current prefs (`defaults export`). iTerm2 then reads/writes the repo copy. |
| oh-my-zsh | nothing | Cloned by bootstrap; `custom/` content comes from the clones above. |

Excluded entirely: `~/.ssh/`, `~/.zsh_history`, `~/.config/gh` (OAuth token),
`~/.config/raycast` (55 MB binary state; Raycast has its own sync),
`~/.config/aws`, `~/.config/op`, `~/.config/1Password`, `~/.config/opencode`,
`~/.config/github-copilot`, `~/.config/pgcli`.

Security note recorded during design: `~/.config/zed/settings.json` currently
contains a plaintext GitHub personal access token. It must never be committed.
Recommendation to the owner: revoke it on GitHub.

`.gitignore` in the repo: `zsh/local.zsh`, `*.local`, `.DS_Store`,
`iterm2/*.plist.bak`.

## 9. Error handling

- Every step runs inside a function that returns non-zero on failure;
  `bootstrap.sh` records the failure, prints it in red, and continues.
- `link_file` refuses to overwrite a target that is a symlink pointing
  somewhere else without backing it up first, and never deletes anything.
- `brew bundle` failures for a single cask (e.g. a download that needs a
  login) do not abort the run; Homebrew prints the failing item and the
  summary shows "brew: 1 item failed".
- `--dry-run` routes every side-effecting command through `run()` which
  prints instead of executing.
- The script refuses to run as root.

## 10. Testing

1. `shellcheck` on every `.sh` file (added to the Brewfile as `shellcheck`).
2. `./bootstrap.sh --dry-run` on this machine — output reviewed by hand.
3. `./bootstrap.sh` on this machine:
   - originals land in `~/.dotfiles-backup/<timestamp>/`;
   - `ls -l ~/.zshrc ~/.gitconfig ~/.config/zed/settings.json` show symlinks
     into the repo;
   - `brew bundle check --file brew/Brewfile` reports satisfied;
   - a second run prints only "skip"/"already" lines and creates no new
     backup directory.
4. Shell regression: capture `alias`, `functions`, and `echo $PATH` from a
   login shell before the change and after; the diff must contain only the
   removals listed in §5.3.
5. Prompt renders (`p10k` instant prompt, git status segment) in a new iTerm2
   window.
6. Optional full run in a fresh macOS VM (UTM): documented in README; not part
   of the initial implementation.
