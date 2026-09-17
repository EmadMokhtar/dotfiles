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
