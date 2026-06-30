#!/usr/bin/env bash
# tests/test_helper/common.bash — Shared setup for all BATS tests

# Load BATS helper libraries
TEST_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
load "${TEST_HELPER_DIR}/bats-support/load"
load "${TEST_HELPER_DIR}/bats-assert/load"

# Derive project root
PROJECT_ROOT="$(cd "${TEST_HELPER_DIR}/../.." && pwd)"

# Source sandbox-common.sh for access to pure functions.
# This will run detect_platform() at source time, which is fine on macOS/Linux.
# The outbound interface is resolved lazily (outbound_iface), so sourcing does
# not shell out to `ip route`.
SCRIPT_DIR="${PROJECT_ROOT}/bin"
source "${PROJECT_ROOT}/lib/sandbox-common.sh"
source "${PROJECT_ROOT}/lib/sandbox-config.sh"

# Create a temporary directory for test fixtures, cleaned up automatically
setup() {
  TEST_TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}
