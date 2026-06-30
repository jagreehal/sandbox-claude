#!/usr/bin/env bats
# Integration: config `tools` (mise) versions apply on create, reapply on
# restart (no drift), and fail closed on an impossible version.
# Requires a built golden-node (with mise); run via tests/run-tests.sh integration.
load '../test_helper/integration'

_dir_file()   { echo "${BATS_FILE_TMPDIR}/toolsdir"; }
_tools_name() { echo "test-${BATS_ROOT_PID:-$$}-cfgtools"; }
_agent() { echo "agent-$(_tools_name)"; }

# node/mise live under the ubuntu user, so query the version AS ubuntu (a plain
# `incus exec` runs as root, which has no mise tools).
node_version() {
  vm_run incus exec "$(_agent)" --user "$SANDBOX_UID" --group "$SANDBOX_GID" \
    --env HOME="$SANDBOX_USER_HOME" -- bash -lc 'node --version'
}

setup_file() {
  local d name
  d="$(mktemp -d)"; echo "$d" > "$(_dir_file)"
  name="$(_tools_name)"
  cat > "${d}/sandbox.config.json" <<'JSON'
{ "stack": "node", "tools": { "node": "22" }, "grants": { "sshAgent": false } }
JSON
  ( cd "$d" && "${PROJECT_ROOT}/bin/sandbox-start" "$name" )
}

teardown_file() {
  "${PROJECT_ROOT}/bin/sandbox-stop" "$(_tools_name)" --rm 2>/dev/null || true
  rm -rf "$(cat "$(_dir_file)" 2>/dev/null)" 2>/dev/null || true
}

setup() { TEST_TMPDIR="$(mktemp -d)"; }

@test "tools.node=22 applies on create" {
  run node_version
  assert_success
  assert_output --partial "v22."
}

@test "changing tools.node reapplies on restart (no drift)" {
  local d name; d="$(cat "$(_dir_file)")"; name="$(_tools_name)"
  echo '{ "stack": "node", "tools": { "node": "20" }, "grants": { "sshAgent": false } }' > "${d}/sandbox.config.json"
  "${PROJECT_ROOT}/bin/sandbox-stop" "$name" >/dev/null
  ( cd "$d" && "${PROJECT_ROOT}/bin/sandbox-start" "$name" )
  run node_version
  assert_success
  assert_output --partial "v20."
}

@test "an impossible tools version fails closed with a clear error" {
  local d name
  d="$(mktemp -d)"; name="$(_tools_name)-bad"
  echo '{ "stack": "node", "tools": { "node": "999.999.999" }, "grants": { "sshAgent": false } }' > "${d}/sandbox.config.json"
  run bash -c "cd '$d' && '${PROJECT_ROOT}/bin/sandbox-start' '$name'"
  assert_failure
  assert_output --partial "undeclared runtime"
  # Clean up the half-provisioned container this intentionally-failing create left.
  "${PROJECT_ROOT}/bin/sandbox-stop" "$name" --rm 2>/dev/null || true
  rm -rf "$d"
}
