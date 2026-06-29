#!/usr/bin/env bats
# Unit tests for lib/sandbox-config.sh (per-repo sandbox.config.json reader).
load '../test_helper/common'

# These tests need jq (the same host prerequisite sandbox-start requires when a
# config is present). Skip cleanly where it isn't installed.
setup() {
  TEST_TMPDIR="$(mktemp -d)"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

write_config() {
  printf '%s' "$1" > "${TEST_TMPDIR}/sandbox.config.json"
  printf '%s' "${TEST_TMPDIR}/sandbox.config.json"
}

@test "find_config_file: finds sandbox.config.json at dir root" {
  echo '{}' > "${TEST_TMPDIR}/sandbox.config.json"
  run find_config_file "${TEST_TMPDIR}"
  assert_success
  assert_output "${TEST_TMPDIR}/sandbox.config.json"
}

@test "find_config_file: empty when absent" {
  run find_config_file "${TEST_TMPDIR}"
  assert_success
  assert_output ""
}

@test "config_is_valid_json: accepts good, rejects malformed" {
  local good bad
  good="$(write_config '{"stack":"node"}')"
  run config_is_valid_json "$good"
  assert_success
  bad="${TEST_TMPDIR}/bad.json"
  echo '{"stack":}' > "$bad"
  run config_is_valid_json "$bad"
  assert_failure
}

@test "config_scalar: reads value, falls back to default when absent" {
  local f
  f="$(write_config '{"stack":"python"}')"
  run config_scalar "$f" '.stack' 'base'
  assert_output "python"
  run config_scalar "$f" '.resources.cpu' '2'
  assert_output "2"
}

@test "config_bool: reads boolean with default" {
  local f
  f="$(write_config '{"screen":false}')"
  run config_bool "$f" '.screen' true
  assert_output "false"
  run config_bool "$f" '.egress.restrict' false
  assert_output "false"
}

@test "config_array: emits elements one per line" {
  local f
  f="$(write_config '{"egress":{"allow":["a.com","b.com"]}}')"
  run config_array "$f" '.egress.allow'
  assert_line --index 0 "a.com"
  assert_line --index 1 "b.com"
}

@test "config_tools: emits tool@version lines" {
  local f
  f="$(write_config '{"tools":{"node":"22","python":"lts"}}')"
  run config_tools "$f"
  assert_line "node@22"
  assert_line "python@lts"
}

@test "validate_config: accepts the bundled example" {
  run validate_config "${PROJECT_ROOT}/sandbox.config.example.json"
  assert_success
}

@test "validate_config: rejects unknown stack" {
  local f
  f="$(write_config '{"stack":"haskell"}')"
  run validate_config "$f"
  assert_failure
  assert_output --partial "Invalid stack"
}

@test "validate_config: rejects malformed cpu" {
  local f
  f="$(write_config '{"resources":{"cpu":"lots"}}')"
  run validate_config "$f"
  assert_failure
  assert_output --partial "resources.cpu"
}

@test "validate_config: rejects malformed memory" {
  local f
  f="$(write_config '{"resources":{"memory":"big"}}')"
  run validate_config "$f"
  assert_failure
  assert_output --partial "resources.memory"
}

@test "validate_config: rejects invalid env var name" {
  local f
  f="$(write_config '{"grants":{"env":["1BAD"]}}')"
  run validate_config "$f"
  assert_failure
  assert_output --partial "grants.env"
}

@test "build_effective_domains_file: unions baseline with egress.allow" {
  local f out
  f="$(write_config '{"egress":{"allow":["extra.example"]}}')"
  out="${TEST_TMPDIR}/effective.txt"
  run build_effective_domains_file "$f" "${PROJECT_ROOT}/domains/anthropic-default.txt" "$out"
  assert_success
  assert_output "$out"
  # Contains both a baseline domain and the repo extra
  run grep -qx "api.anthropic.com" "$out"
  assert_success
  run grep -qx "extra.example" "$out"
  assert_success
}

@test "schema: sandbox.schema.json is valid JSON" {
  run jq -e . "${PROJECT_ROOT}/sandbox.schema.json"
  assert_success
}

@test "schema: every key in the example exists in schema properties" {
  # Structural drift guard (we deliberately don't ship a full JSON Schema
  # validator dependency — the editor does that via $schema).
  run jq -e -n \
    --slurpfile cfg "${PROJECT_ROOT}/sandbox.config.example.json" \
    --slurpfile sch "${PROJECT_ROOT}/sandbox.schema.json" \
    '($cfg[0] | keys) - (["$schema"] + ($sch[0].properties | keys)) | length == 0'
  assert_success
}
