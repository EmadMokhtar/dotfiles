load helpers

setup() {
  make_sandbox
  SECRET="$REPO_ROOT/bin/secret"
  MAP="$HOME/.config/secrets/secrets.map"
  # Fake commands. Every value below is a fake test string.
  stub security 'case "$1" in find-generic-password) echo "kc-value-123";; esac'
  stub op 'case "$1" in read) echo "op-value-456";; esac'
}

# write_map — write stdin to the map file with mode 600.
write_map() {
  mkdir -p "$(dirname "$MAP")"
  cat > "$MAP"
  chmod 600 "$MAP"
}

# ---- usage and platform gate ------------------------------------------------

@test "no arguments prints usage and exits 2" {
  run "$SECRET"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage: secret"* ]] || false
}

@test "--help prints usage and exits 0" {
  run "$SECRET" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: secret"* ]] || false
}

@test "an unknown command exits 2" {
  run "$SECRET" bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown command: bogus"* ]] || false
}

@test "every command stops on an unsupported OS" {
  stub uname 'echo Linux'
  for c in list "run X -- true" "set X" "open X"; do
    # shellcheck disable=SC2086
    run "$SECRET" $c
    [ "$status" -eq 1 ]
    [[ "$output" == *"unsupported OS: Linux (macOS only for now)"* ]] || false
  done
}

# ---- the map ------------------------------------------------------------------

@test "a missing map is reported" {
  run "$SECRET" list
  [ "$status" -eq 1 ]
  [[ "$output" == *"no map at $MAP"* ]] || false
}

@test "list shows names, source types and apps, never values or references" {
  write_map <<'EOF'
# comment line

KC_ONE     keychain
OP_ONE     op://Vault/Item/field
CMD_ONE    cmd:printf hunter2
app Claude                 KC_ONE
app Visual Studio Code     KC_ONE,OP_ONE
app Visual Studio Code     CMD_ONE
EOF
  run "$SECRET" list
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eq '^KC_ONE +keychain$'
  echo "$output" | grep -Eq '^OP_ONE +1password$'
  echo "$output" | grep -Eq '^CMD_ONE +command$'
  echo "$output" | grep -Eq '^Claude +KC_ONE$'
  echo "$output" | grep -Eq '^Visual Studio Code +KC_ONE,OP_ONE,CMD_ONE$'
  [[ "$output" != *"Vault"* ]] || false
  [[ "$output" != *"hunter2"* ]] || false
  [[ "$output" != *"kc-value-123"* ]] || false
}

@test "map errors name the line and the problem" {
  local cases=(
    "A keychain|A keychain|A is defined twice (lines 1 and 2)"
    "1BAD keychain||line 1: bad secret name: 1BAD"
    "A vault||line 1: bad source for A"
    "A cmd:||line 1: bad source for A"
    "app Zed||line 1: an app line needs an app name and a list"
    "A keychain|app Zed A,,B|line 2: bad list of secret names: A,,B"
    "A keychain|app Zed B|app 'Zed' lists B, which has no secret line"
  )
  local c first second expected
  for c in "${cases[@]}"; do
    IFS='|' read -r first second expected <<< "$c"
    mkdir -p "$(dirname "$MAP")"
    printf '%s\n' "$first" > "$MAP"
    [ -z "$second" ] || printf '%s\n' "$second" >> "$MAP"
    chmod 600 "$MAP"
    run "$SECRET" list
    [ "$status" -eq 1 ]
    [[ "$output" == *"$expected"* ]] || { echo "case '$c' gave: $output"; false; }
  done
}

@test "a map that other users can write is refused" {
  write_map <<'EOF'
A keychain
EOF
  chmod 664 "$MAP"
  run "$SECRET" list
  [ "$status" -eq 1 ]
  [[ "$output" == *"can be written by other users"* ]] || false
}

@test "a map owned by someone else is refused" {
  write_map <<'EOF'
A keychain
EOF
  stub stat 'echo "0 600"'
  run "$SECRET" list
  [ "$status" -eq 1 ]
  [[ "$output" == *"not owned by you"* ]] || false
}

# ---- secret run ---------------------------------------------------------------

# A map with one secret of each source type.
three_sources_map() {
  write_map <<'MAPEOF'
KC_ONE     keychain
OP_ONE     op://Vault/Item/field
CMD_ONE    cmd:printf cmd-value-789
MAPEOF
}

@test "run injects values from the keychain, 1Password and a command" {
  three_sources_map
  run "$SECRET" run KC_ONE OP_ONE CMD_ONE -- sh -c 'printf "%s|%s|%s" "$KC_ONE" "$OP_ONE" "$CMD_ONE"'
  [ "$status" -eq 0 ]
  [ "$output" = "kc-value-123|op-value-456|cmd-value-789" ]
  [ "$(calls_matching 'security find-generic-password -a KC_ONE -s dotfiles-secrets -w$')" -eq 1 ]
  [ "$(calls_matching 'op read --no-newline op://Vault/Item/field$')" -eq 1 ]
}

@test "run does not leak a value into the arguments of another command" {
  three_sources_map
  run "$SECRET" run KC_ONE OP_ONE -- true
  [ "$status" -eq 0 ]
  [ "$(calls_matching 'kc-value-123')" -eq 0 ]
  [ "$(calls_matching 'op-value-456')" -eq 0 ]
}

@test "run keeps spaces, quotes, dollar signs and equals signs in a value" {
  printf '%s' 'a b$c"d'\''e=f  g' > "$HOME/special.txt"
  write_map <<EOF
SPECIAL    cmd:cat $HOME/special.txt
EOF
  run "$SECRET" run SPECIAL -- sh -c 'printf "%s" "$SPECIAL"'
  [ "$status" -eq 0 ]
  [ "$output" = 'a b$c"d'\''e=f  g' ]
}

@test "run passes the program's arguments through unchanged" {
  three_sources_map
  run "$SECRET" run KC_ONE -- sh -c 'printf "%s|%s" "$1" "$2"' _ "a b" "c  d"
  [ "$status" -eq 0 ]
  [ "$output" = "a b|c  d" ]
}

@test "run passes the exit code of the program through" {
  three_sources_map
  run "$SECRET" run KC_ONE -- sh -c 'exit 7'
  [ "$status" -eq 7 ]
}

@test "run needs --, a name and a command" {
  three_sources_map
  run "$SECRET" run KC_ONE true
  [ "$status" -eq 2 ]
  run "$SECRET" run -- true
  [ "$status" -eq 2 ]
  run "$SECRET" run KC_ONE --
  [ "$status" -eq 2 ]
  run "$SECRET" run --bogus KC_ONE -- true
  [ "$status" -eq 2 ]
}

@test "run fails closed on a name that is not in the map" {
  three_sources_map
  run "$SECRET" run KC_ONE NOPE -- touch "$HOME/ran"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot resolve NOPE: not in the map"* ]] || false
  [ ! -e "$HOME/ran" ]
}

@test "run fails closed when one source fails and does not start the program" {
  three_sources_map
  stub op 'echo "not signed in" >&2; exit 1'
  run "$SECRET" run KC_ONE OP_ONE -- touch "$HOME/ran"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot resolve OP_ONE"* ]] || false
  [[ "$output" == *"not signed in"* ]] || false
  [ ! -e "$HOME/ran" ]
}

@test "run treats an empty value as a failure" {
  three_sources_map
  stub security 'exit 0'
  run "$SECRET" run KC_ONE -- touch "$HOME/ran"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot resolve KC_ONE: the value is empty"* ]] || false
  [ ! -e "$HOME/ran" ]
}

@test "run --optional warns, skips the failed secret and still runs" {
  three_sources_map
  stub op 'exit 1'
  run "$SECRET" run --optional KC_ONE OP_ONE -- sh -c 'printf "%s|%s" "$KC_ONE" "${OP_ONE-unset}"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"warning: OP_ONE:"* ]] || false
  [[ "$output" == *"kc-value-123|unset"* ]] || false
}

@test "run reports a missing 1Password CLI" {
  three_sources_map
  rm "$STUB_BIN/op"
  PATH="$STUB_BIN:/usr/bin:/bin" run "$SECRET" run OP_ONE -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"the 1Password CLI (op) is not installed"* ]] || false
}

@test "run without --optional stops when the map is missing" {
  run "$SECRET" run KC_ONE -- touch "$HOME/ran"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no map at $MAP"* ]] || false
  [ ! -e "$HOME/ran" ]
}

@test "run --optional starts the program, without secrets, when the map is missing" {
  run "$SECRET" run --optional KC_ONE -- sh -c 'printf "started|%s" "${KC_ONE-unset}"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"no map at $MAP"* ]] || false
  [[ "$output" == *"continuing without secrets"* ]] || false
  [[ "$output" == *"started|unset"* ]] || false
}

@test "run --optional starts the program, without secrets, when the map is unsafe or broken" {
  write_map <<'EOF'
KC_ONE     keychain
EOF
  chmod 664 "$MAP"
  run "$SECRET" run --optional KC_ONE -- sh -c 'printf "started|%s" "${KC_ONE-unset}"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"continuing without secrets"* ]] || false
  [[ "$output" == *"started|unset"* ]] || false

  write_map <<'EOF'
KC_ONE     vault
EOF
  run "$SECRET" run --optional KC_ONE -- sh -c 'printf "started|%s" "${KC_ONE-unset}"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"continuing without secrets"* ]] || false
  [[ "$output" == *"started|unset"* ]] || false
}

# ---- secret set -----------------------------------------------------------------

@test "set asks security for the value, never passes it, and creates the map" {
  run "$SECRET" set NEW_KEY
  [ "$status" -eq 0 ]
  [ "$(cat "$CALL_LOG")" = "security add-generic-password -U -a NEW_KEY -s dotfiles-secrets -w" ]
  [ "$(stat -f %Lp "$HOME/.config/secrets")" = "700" ]
  [ "$(stat -f %Lp "$MAP")" = "600" ]
  grep -Eq '^NEW_KEY +keychain$' "$MAP"
}

@test "set does not add a second line for a name that is already in the map" {
  write_map <<'EOF'
NEW_KEY    keychain
EOF
  run "$SECRET" set NEW_KEY
  [ "$status" -eq 0 ]
  [ "$(grep -c NEW_KEY "$MAP")" -eq 1 ]
  [ "$(calls_matching 'add-generic-password')" -eq 1 ]
}

@test "set refuses a name that has another source" {
  write_map <<'EOF'
OP_ONE     op://Vault/Item/field
EOF
  run "$SECRET" set OP_ONE
  [ "$status" -eq 1 ]
  [[ "$output" == *"another source"* ]] || false
  [ "$(calls_matching 'add-generic-password')" -eq 0 ]
}

@test "set starts a new line when the map does not end with one" {
  mkdir -p "$(dirname "$MAP")"
  printf 'FIRST_KEY keychain' > "$MAP"
  chmod 600 "$MAP"
  run "$SECRET" set SECOND_KEY
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$MAP" | tr -d ' ')" -eq 2 ]
  grep -Eq '^FIRST_KEY keychain$' "$MAP"
  grep -Eq '^SECOND_KEY +keychain$' "$MAP"
}

@test "set leaves the map alone when security fails" {
  write_map <<'EOF'
FIRST_KEY  keychain
EOF
  stub security 'exit 1'
  run "$SECRET" set SECOND_KEY
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not store SECOND_KEY"* ]] || false
  [ "$(grep -c SECOND_KEY "$MAP")" -eq 0 ]
}

@test "set works for a name that an app line lists before it has a secret line" {
  write_map <<'EOF'
app Zed    LATER_KEY
EOF
  run "$SECRET" set LATER_KEY
  [ "$status" -eq 0 ]
  grep -Eq '^LATER_KEY +keychain$' "$MAP"
}

@test "set rejects bad names and a missing name" {
  run "$SECRET" set 1bad
  [ "$status" -eq 1 ]
  run "$SECRET" set app
  [ "$status" -eq 1 ]
  run "$SECRET" set
  [ "$status" -eq 2 ]
  [ "$(calls_matching 'add-generic-password')" -eq 0 ]
}
