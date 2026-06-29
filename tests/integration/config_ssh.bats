#!/usr/bin/env bats
# Integration: grants.sshAgent transitions on a real container (no GitHub needed —
# we provision an in-container key via --ssh-key, then exercise the transitions).
#   true(+--ssh-key) -> key + SSH config present
#   -> false         -> key, SSH config, and agent socket all revoked
#   -> true(+key)    -> reprovisioned
# Requires a built golden-base; run via tests/run-tests.sh integration.
load '../test_helper/integration'

_dir_file()  { echo "${BATS_FILE_TMPDIR}/sshdir"; }
_ssh_name()  { echo "test-${BATS_ROOT_PID:-$$}-cfgssh"; }
_agent()     { echo "agent-$(_ssh_name)"; }
# Deterministic key path (stable across this file's tests).
_key()       { echo "${BATS_FILE_TMPDIR}/id_test"; }

setup_file() {
  local d name
  d="$(mktemp -d)"; echo "$d" > "$(_dir_file)"
  name="$(_ssh_name)"
  ssh-keygen -t ed25519 -f "$(_key)" -N "" -q
  # Create with sshAgent:true (config) + an explicit key, so a deploy key lands
  # in the container without needing a GitHub repo.
  cat > "${d}/sandbox.config.json" <<'JSON'
{ "stack": "base", "grants": { "sshAgent": true } }
JSON
  ( cd "$d" && "${PROJECT_ROOT}/bin/sandbox-start" "$name" --ssh-key "$(_key)" )
}

teardown_file() {
  "${PROJECT_ROOT}/bin/sandbox-stop" "$(_ssh_name)" --rm 2>/dev/null || true
  rm -rf "$(cat "$(_dir_file)" 2>/dev/null)" 2>/dev/null || true
}

setup() { TEST_TMPDIR="$(mktemp -d)"; }

@test "key + SSH config present after create with a key" {
  run vm_run incus exec "$(_agent)" -- test -f /home/ubuntu/.ssh/deploy-key
  assert_success
  run vm_run incus exec "$(_agent)" -- test -f /home/ubuntu/.ssh/config
  assert_success
}

@test "sshAgent:false revokes key, SSH config, and agent socket on restart" {
  local d name; d="$(cat "$(_dir_file)")"; name="$(_ssh_name)"
  echo '{ "stack": "base", "grants": { "sshAgent": false } }' > "${d}/sandbox.config.json"
  "${PROJECT_ROOT}/bin/sandbox-stop" "$name" >/dev/null
  ( cd "$d" && "${PROJECT_ROOT}/bin/sandbox-start" "$name" )
  run vm_run incus exec "$(_agent)" -- test -e /home/ubuntu/.ssh/deploy-key
  assert_failure
  run vm_run incus exec "$(_agent)" -- test -e /home/ubuntu/.ssh/config
  assert_failure
  run vm_run incus exec "$(_agent)" -- test -e /run/ssh-agent.sock
  assert_failure
}

@test "sshAgent:true + --ssh-key reprovisions the key on restart" {
  local d name; d="$(cat "$(_dir_file)")"; name="$(_ssh_name)"
  echo '{ "stack": "base", "grants": { "sshAgent": true } }' > "${d}/sandbox.config.json"
  "${PROJECT_ROOT}/bin/sandbox-stop" "$name" >/dev/null
  ( cd "$d" && "${PROJECT_ROOT}/bin/sandbox-start" "$name" --ssh-key "$(_key)" )
  run vm_run incus exec "$(_agent)" -- test -f /home/ubuntu/.ssh/deploy-key
  assert_success
}
