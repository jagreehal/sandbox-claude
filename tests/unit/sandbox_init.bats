#!/usr/bin/env bats
# Unit tests for detect_stack (lib/sandbox-config.sh) and the sandbox-init CLI.
load '../test_helper/common'

run_init() {
  # Run sandbox-init with the temp dir as cwd.
  run bash -c "cd '${TEST_TMPDIR}' && '${PROJECT_ROOT}/bin/sandbox-init' $*"
}

@test "detect_stack: node from package.json" {
  echo '{}' > "${TEST_TMPDIR}/package.json"
  run detect_stack "${TEST_TMPDIR}"
  assert_output "node"
}

@test "detect_stack: python from pyproject.toml" {
  touch "${TEST_TMPDIR}/pyproject.toml"
  run detect_stack "${TEST_TMPDIR}"
  assert_output "python"
}

@test "detect_stack: go from go.mod" {
  touch "${TEST_TMPDIR}/go.mod"
  run detect_stack "${TEST_TMPDIR}"
  assert_output "go"
}

@test "detect_stack: rust from Cargo.toml" {
  touch "${TEST_TMPDIR}/Cargo.toml"
  run detect_stack "${TEST_TMPDIR}"
  assert_output "rust"
}

@test "detect_stack: dotnet from a .csproj" {
  touch "${TEST_TMPDIR}/App.csproj"
  run detect_stack "${TEST_TMPDIR}"
  assert_output "dotnet"
}

@test "detect_stack: base when nothing recognisable" {
  run detect_stack "${TEST_TMPDIR}"
  assert_output "base"
}

@test "detect_stack: node takes precedence over other markers" {
  echo '{}' > "${TEST_TMPDIR}/package.json"
  touch "${TEST_TMPDIR}/go.mod"
  run detect_stack "${TEST_TMPDIR}"
  assert_output "node"
}

@test "sandbox-init: generates a valid config and detects the stack" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  echo '{}' > "${TEST_TMPDIR}/package.json"
  run_init
  assert_success
  [ -f "${TEST_TMPDIR}/sandbox.config.json" ]
  run jq -r '.stack' "${TEST_TMPDIR}/sandbox.config.json"
  assert_output "node"
  run jq -r '.grants.env[0]' "${TEST_TMPDIR}/sandbox.config.json"
  assert_output "ANTHROPIC_API_KEY"
  run jq -r '."$schema"' "${TEST_TMPDIR}/sandbox.config.json"
  assert_output --partial "sandbox.schema.json"
}

@test "sandbox-init: omits stack key for a base repo" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  run_init
  assert_success
  run jq -e 'has("stack")' "${TEST_TMPDIR}/sandbox.config.json"
  assert_output "false"
}

@test "sandbox-init: refuses to clobber an existing config" {
  echo '{}' > "${TEST_TMPDIR}/sandbox.config.json"
  run_init
  assert_failure
  assert_output --partial "already exists"
}

@test "sandbox-init: --force overwrites, --stack overrides detection" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  echo 'not even json' > "${TEST_TMPDIR}/sandbox.config.json"
  run_init --force --stack go
  assert_success
  run jq -r '.stack' "${TEST_TMPDIR}/sandbox.config.json"
  assert_output "go"
}

@test "sandbox-init: rejects an unknown --stack" {
  run_init --stack haskell
  assert_failure
  assert_output --partial "Unknown stack"
}
