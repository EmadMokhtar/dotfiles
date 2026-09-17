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
