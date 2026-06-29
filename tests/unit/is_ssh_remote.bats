#!/usr/bin/env bats
# Unit tests for is_ssh_remote (lib/sandbox-common.sh) — drives the early
# grants.sshAgent=false validation in sandbox-start.
load '../test_helper/common'

@test "is_ssh_remote: scp-style git@ is SSH" {
  run is_ssh_remote "git@github.com:me/repo.git"
  assert_success
}

@test "is_ssh_remote: ssh:// scheme is SSH" {
  run is_ssh_remote "ssh://git@github.com/me/repo.git"
  assert_success
}

@test "is_ssh_remote: https is not SSH" {
  run is_ssh_remote "https://github.com/me/repo.git"
  assert_failure
}

@test "is_ssh_remote: http is not SSH" {
  run is_ssh_remote "http://example.com/me/repo.git"
  assert_failure
}

@test "is_ssh_remote: empty string is not SSH" {
  run is_ssh_remote ""
  assert_failure
}
