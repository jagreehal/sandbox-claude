#!/usr/bin/env bats
# Unit tests for env_file_lookup (resolves a single env var from ~/.sandbox/env
# without bulk-injecting the file — the basis of the grants.env allowlist).
load '../test_helper/common'

@test "env_file_lookup: finds a plain KEY=VALUE" {
  cat > "${TEST_TMPDIR}/env" << 'EOF'
FOO=bar
BAZ=qux
EOF
  run env_file_lookup "${TEST_TMPDIR}/env" FOO
  assert_success
  assert_output "bar"
}

@test "env_file_lookup: handles 'export KEY=VALUE' form" {
  echo 'export TOKEN=sekret' > "${TEST_TMPDIR}/env"
  run env_file_lookup "${TEST_TMPDIR}/env" TOKEN
  assert_success
  assert_output "sekret"
}

@test "env_file_lookup: last definition wins" {
  cat > "${TEST_TMPDIR}/env" << 'EOF'
K=first
K=second
EOF
  run env_file_lookup "${TEST_TMPDIR}/env" K
  assert_success
  assert_output "second"
}

@test "env_file_lookup: ignores comments and blank lines" {
  cat > "${TEST_TMPDIR}/env" << 'EOF'
# a comment
   # indented comment

REAL=value
EOF
  run env_file_lookup "${TEST_TMPDIR}/env" REAL
  assert_success
  assert_output "value"
}

@test "env_file_lookup: preserves '=' inside values" {
  echo 'DATABASE_URL=postgres://u:p@h/db?x=1' > "${TEST_TMPDIR}/env"
  run env_file_lookup "${TEST_TMPDIR}/env" DATABASE_URL
  assert_success
  assert_output "postgres://u:p@h/db?x=1"
}

@test "env_file_lookup: returns failure for an absent key" {
  echo 'FOO=bar' > "${TEST_TMPDIR}/env"
  run env_file_lookup "${TEST_TMPDIR}/env" MISSING
  assert_failure
  assert_output ""
}

@test "env_file_lookup: returns failure for a missing file" {
  run env_file_lookup "${TEST_TMPDIR}/nope" ANY
  assert_failure
}
