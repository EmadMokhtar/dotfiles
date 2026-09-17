load helpers

@test "stub records its arguments" {
  make_sandbox
  stub hello
  hello world
  [ "$(cat "$CALL_LOG")" = "hello world" ]
}

@test "stub body runs" {
  make_sandbox
  stub hello 'echo hi; exit 3'
  run hello
  [ "$status" -eq 3 ]
  [ "$output" = "hi" ]
}
