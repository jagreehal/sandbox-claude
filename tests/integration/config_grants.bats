#!/usr/bin/env bats
# Integration: per-repo config grants are ENFORCED and CONVERGE on restart.
#   - grants.env is an allowlist whose values come from the host/env file
#   - removing a grant clears the previously-injected secret on restart
#   - grants.sshAgent=false + an SSH remote fails fast with a precise message
# Requires a built golden-base; run on a real host via:
#   tests/run-tests.sh integration
load '../test_helper/integration'

_dir_file()  { echo "${BATS_FILE_TMPDIR}/cfgdir"; }
_cfg_name()  { echo "test-${BATS_ROOT_PID:-$$}-cfggrants"; }

setup_file() {
  local d name
  d="$(mktemp -d)"; echo "$d" > "$(_dir_file)"
  name="$(_cfg_name)"
  # Scratch container (no repo). Config grants one env var; its VALUE comes from
  # the host environment (never from the committed file). sshAgent off — no repo,
  # so no key is needed anyway.
  cat > "${d}/sandbox.config.json" <<'JSON'
{ "stack": "base", "grants": { "env": ["CONV_TEST_VAR"], "sshAgent": false } }
JSON
  ( cd "$d" && CONV_TEST_VAR=present "${PROJECT_ROOT}/bin/sandbox-start" "$name" )
}

teardown_file() {
  local name; name="$(_cfg_name)"
  "${PROJECT_ROOT}/bin/sandbox-stop" "$name" --rm 2>/dev/null || true
  rm -rf "$(cat "$(_dir_file)" 2>/dev/null)" 2>/dev/null || true
}

setup() { TEST_TMPDIR="$(mktemp -d)"; }

@test "granted env var is present after create" {
  run vm_run incus exec "agent-$(_cfg_name)" -- bash -lc 'echo "$CONV_TEST_VAR"'
  assert_success
  assert_output "present"
}

@test "removing the grant clears the secret on restart (convergence)" {
  local d name
  d="$(cat "$(_dir_file)")"; name="$(_cfg_name)"
  # Drop the grant, then stop + restart from the same directory.
  echo '{ "stack": "base", "grants": { "env": [], "sshAgent": false } }' > "${d}/sandbox.config.json"
  "${PROJECT_ROOT}/bin/sandbox-stop" "$name" >/dev/null
  ( cd "$d" && "${PROJECT_ROOT}/bin/sandbox-start" "$name" )
  run vm_run incus exec "agent-${name}" -- bash -lc 'echo "[$CONV_TEST_VAR]"'
  assert_success
  assert_output "[]"
}

@test "sshAgent:false + an SSH remote fails fast with a precise message" {
  local d
  d="$(cat "$(_dir_file)")"
  run bash -c "cd '${d}' && '${PROJECT_ROOT}/bin/sandbox-start' '$(_cfg_name)-ssh' git@github.com:example/repo.git"
  assert_failure
  assert_output --partial "SSH remote"
}

@test "grants.env value: ~/.sandbox/env wins over the host environment" {
  local d name envfile
  d="$(cat "$(_dir_file)")"; name="$(_cfg_name)"
  envfile="${BATS_FILE_TMPDIR}/envfile"
  echo 'PREC_VAR=from_file' > "$envfile"
  echo '{ "stack": "base", "grants": { "env": ["PREC_VAR"], "sshAgent": false } }' > "${d}/sandbox.config.json"
  "${PROJECT_ROOT}/bin/sandbox-stop" "$name" >/dev/null
  # Both sources set PREC_VAR; the file value must win.
  ( cd "$d" && SANDBOX_ENV_FILE="$envfile" PREC_VAR=from_host "${PROJECT_ROOT}/bin/sandbox-start" "$name" )
  run vm_run incus exec "agent-${name}" -- bash -lc 'echo "$PREC_VAR"'
  assert_success
  assert_output "from_file"
}

@test "deleting the config entirely clears previously-granted env on restart" {
  local d name
  d="$(cat "$(_dir_file)")"; name="$(_cfg_name)"
  # Re-grant a var and confirm it lands in the container.
  echo '{ "stack": "base", "grants": { "env": ["DEL_TEST_VAR"], "sshAgent": false } }' > "${d}/sandbox.config.json"
  "${PROJECT_ROOT}/bin/sandbox-stop" "$name" >/dev/null
  ( cd "$d" && DEL_TEST_VAR=here "${PROJECT_ROOT}/bin/sandbox-start" "$name" )
  run vm_run incus exec "agent-${name}" -- bash -lc 'echo "[$DEL_TEST_VAR]"'
  assert_output "[here]"

  # Delete the config file entirely, then restart — the secret must be cleared,
  # not left behind (env-managed metadata drives the convergence).
  rm -f "${d}/sandbox.config.json"
  "${PROJECT_ROOT}/bin/sandbox-stop" "$name" >/dev/null
  ( cd "$d" && "${PROJECT_ROOT}/bin/sandbox-start" "$name" )
  run vm_run incus exec "agent-${name}" -- bash -lc 'echo "[$DEL_TEST_VAR]"'
  assert_output "[]"
}
