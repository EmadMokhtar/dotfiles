# Shared setup for bats tests. Each .bats file does `load helpers`.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export REPO_ROOT

# make_sandbox — give the test its own HOME and a directory of fake commands.
make_sandbox() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export STUB_BIN="$BATS_TEST_TMPDIR/bin"
  export CALL_LOG="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$HOME" "$STUB_BIN"
  : > "$CALL_LOG"
  export PATH="$STUB_BIN:$PATH"
}

# stub <name> [body...] — create a fake command that records "<name> <args>"
# in CALL_LOG and then runs <body> (default: nothing, exit 0).
stub() {
  local name="$1"; shift
  local body="${*:-:}"
  cat > "$STUB_BIN/$name" <<EOF
#!/bin/bash
printf '%s %s\n' "$name" "\$*" >> "$CALL_LOG"
$body
EOF
  chmod +x "$STUB_BIN/$name"
}

# calls_matching <pattern> — how many logged calls match a grep pattern.
calls_matching() {
  grep -c -- "$1" "$CALL_LOG" || true
}
