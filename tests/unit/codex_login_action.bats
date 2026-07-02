#!/usr/bin/env bats
# Unit tests for codex_login_action (lib/sandbox-common.sh) — the pure decision
# table behind the grants.codexLogin reconciler in sandbox-start.
load '../test_helper/common'

@test "codex_login_action: enabled + already present => noop" {
  run codex_login_action yes yes ""
  assert_output "noop"
}

@test "codex_login_action: enabled + absent + no conflict => add" {
  run codex_login_action yes no ""
  assert_output "add"
}

@test "codex_login_action: enabled + absent + conflict => skip (does not add)" {
  run codex_login_action yes no "agent-other"
  assert_output "skip"
}

@test "codex_login_action: disabled + present => remove (converges off)" {
  run codex_login_action no yes ""
  assert_output "remove"
}

@test "codex_login_action: disabled + absent => noop" {
  run codex_login_action no no ""
  assert_output "noop"
}

@test "codex_login_action: disabled ignores a stale conflict value" {
  # conflict is only meaningful on the add path; off must still converge to remove.
  run codex_login_action no yes "agent-other"
  assert_output "remove"
}
