#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Check BATS is installed
if ! command -v bats &>/dev/null; then
  echo "Error: bats-core is not installed."
  echo "  macOS:  brew install bats-core"
  echo "  Linux:  apt install bats (or see https://github.com/bats-core/bats-core)"
  exit 1
fi

# Vendor the BATS helper libraries on first run (kept out of git; see .gitignore).
# Auto-cloning keeps the contributor loop to a single command: tests/run-tests.sh.
ensure_bats_helpers() {
  local repo dir
  for repo in bats-support bats-assert; do
    dir="${SCRIPT_DIR}/test_helper/${repo}"
    if [ ! -d "$dir" ]; then
      echo "Fetching ${repo} (one-time)..."
      git clone --depth 1 -q "https://github.com/bats-core/${repo}" "$dir" ||
        {
          echo "Error: could not clone ${repo}. Check network/git access." >&2
          exit 1
        }
    fi
  done
}
ensure_bats_helpers

# ── Cleanup: stop and remove any test containers left behind ────────
# Runs on EXIT (success, failure, or signal) to prevent leaked containers.
cleanup_test_containers() {
  # Source sandbox helpers for vm_exec (SCRIPT_DIR is expected by sandbox-common.sh)
  local _saved_script_dir="${SCRIPT_DIR}"
  SCRIPT_DIR="${PROJECT_ROOT}/bin" source "${PROJECT_ROOT}/lib/sandbox-common.sh" 2>/dev/null || return 0
  SCRIPT_DIR="${_saved_script_dir}"

  local containers
  containers=$(vm_exec "incus list -f csv -c n 2>/dev/null | grep '^agent-test-' || true" 2>/dev/null) || return 0
  if [[ -z "$containers" ]]; then
    return 0
  fi

  echo ""
  echo "Cleaning up leftover test containers..."
  local name
  for c in $containers; do
    # Strip the "agent-" prefix to get the name sandbox-stop expects
    name="${c#agent-}"
    echo "  Stopping ${c}..."
    "${PROJECT_ROOT}/bin/sandbox-stop" "$name" --rm 2>/dev/null || true
  done
  echo "Cleanup complete."
}

TIER="${1:-all}"

case "$TIER" in
  unit)
    echo "Running unit tests..."
    bats "${SCRIPT_DIR}/unit/"
    ;;
  integration)
    trap cleanup_test_containers EXIT
    echo "Running integration tests (requires sandbox-setup)..."
    bats "${SCRIPT_DIR}/integration/"
    ;;
  all)
    echo "Running unit tests..."
    bats "${SCRIPT_DIR}/unit/"
    echo ""
    trap cleanup_test_containers EXIT
    echo "Running integration tests (requires sandbox-setup)..."
    bats "${SCRIPT_DIR}/integration/"
    ;;
  *)
    echo "Usage: $0 [unit|integration|all]"
    exit 1
    ;;
esac
