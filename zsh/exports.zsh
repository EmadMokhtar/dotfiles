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

# Ollama: let Obsidian plugins call the local server. It listens on
# localhost only; set OLLAMA_HOST in ~/.config/zsh/local.zsh to expose it.
export OLLAMA_ORIGINS="app://obsidian.md*"
