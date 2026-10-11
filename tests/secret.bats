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
