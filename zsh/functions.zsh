# mkd <dir> — create a directory and enter it
mkd() { mkdir -p "$@" && cd "$_" || return; }

# gi <templates> — print a .gitignore from gitignore.io, e.g. `gi python,macos`
gi() { curl -L -s "https://www.gitignore.io/api/$*"; }

# git_tag <tag> — create a tag and push it
git_tag() { git tag "$1" && git push origin "$1"; }

# git_force_tag <tag> — recreate an existing tag and force-push it
git_force_tag() { git tag -d "$1"; git tag "$1" && git push origin -f "$1"; }
