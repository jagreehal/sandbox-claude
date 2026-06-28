#!/usr/bin/env bats
load '../test_helper/common'

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  _OUTBOUND_IFACE=""   # reset the memo between tests
}

@test "outbound_iface: returns the detected interface" {
  detect_outbound_iface() { echo "eth0"; }
  run outbound_iface
  assert_success
  assert_output "eth0"
}

@test "outbound_iface: dies with a clear message when no interface is found" {
  detect_outbound_iface() { echo ""; }
  run outbound_iface
  assert_failure
  assert_output --partial "outbound network interface"
}

@test "outbound_iface: caches the first detected value" {
  detect_outbound_iface() { echo "eth-first"; }
  outbound_iface >/dev/null            # primes the cache in this shell
  detect_outbound_iface() { echo "eth-second"; }
  run outbound_iface
  assert_success
  assert_output "eth-first"
}
