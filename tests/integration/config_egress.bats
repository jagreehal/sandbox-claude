#!/usr/bin/env bats
# Integration: per-repo egress config + the apply_egress_state reconciler.
#   restrict:true on create        -> filtering on, allowlist = baseline ∪ egress.allow
#   allowlist change on restart     -> effective allowlist updated
#   restrict flipped false / config deleted on restart -> filtering torn down (converge)
#   explicit --domains-file         -> overrides config egress.allow
# Requires golden-base + Squid; run via tests/run-tests.sh integration.
load '../test_helper/integration'

_dir_file()  { echo "${BATS_FILE_TMPDIR}/egdir"; }
_eg_name()   { echo "test-${BATS_ROOT_PID:-$$}-cfgeg"; }
_agent()     { echo "agent-$(_eg_name)"; }
_squid_conf() { echo "/etc/squid/sandbox/containers/$(_agent).conf"; }
_eff_file()  { echo "${HOME}/.sandbox/effective-domains/$(_agent).txt"; }

setup_file() {
  local d name
  d="$(mktemp -d)"; echo "$d" > "$(_dir_file)"
  name="$(_eg_name)"
  cat > "${d}/sandbox.config.json" <<'JSON'
{ "stack": "base", "egress": { "restrict": true, "allow": ["alpha.example.test"] }, "grants": { "sshAgent": false } }
JSON
  ( cd "$d" && "${PROJECT_ROOT}/bin/sandbox-start" "$name" )
}

teardown_file() {
  "${PROJECT_ROOT}/bin/sandbox-stop" "$(_eg_name)" --rm 2>/dev/null || true
  rm -rf "$(cat "$(_dir_file)" 2>/dev/null)" 2>/dev/null || true
}

setup() { TEST_TMPDIR="$(mktemp -d)"; }

@test "restrict:true on create turns filtering on" {
  run get_metadata "$(_agent)" "restrict-domains"
  assert_output "yes"
  run vm_exec "test -f $(_squid_conf)"
  assert_success
}

@test "effective allowlist is baseline ∪ egress.allow" {
  # baseline domain present...
  run grep -qx "api.anthropic.com" "$(_eff_file)"
  assert_success
  # ...plus the repo's extra
  run grep -qx "alpha.example.test" "$(_eff_file)"
  assert_success
}

@test "allowlist change reapplies on restart" {
  local d name; d="$(cat "$(_dir_file)")"; name="$(_eg_name)"
  echo '{ "stack": "base", "egress": { "restrict": true, "allow": ["beta.example.test"] }, "grants": { "sshAgent": false } }' > "${d}/sandbox.config.json"
  "${PROJECT_ROOT}/bin/sandbox-stop" "$name" >/dev/null
  ( cd "$d" && "${PROJECT_ROOT}/bin/sandbox-start" "$name" )
  run grep -qx "beta.example.test" "$(_eff_file)"
  assert_success
  run grep -qx "alpha.example.test" "$(_eff_file)"
  assert_failure
}

@test "flipping restrict:false on restart tears filtering down (convergence)" {
  local d name; d="$(cat "$(_dir_file)")"; name="$(_eg_name)"
  echo '{ "stack": "base", "egress": { "restrict": false }, "grants": { "sshAgent": false } }' > "${d}/sandbox.config.json"
  "${PROJECT_ROOT}/bin/sandbox-stop" "$name" >/dev/null
  ( cd "$d" && "${PROJECT_ROOT}/bin/sandbox-start" "$name" )
  run get_metadata "$(_agent)" "restrict-domains"
  refute_output "yes"
  run vm_exec "test -f $(_squid_conf)"
  assert_failure
}

@test "explicit --domains-file overrides config egress.allow" {
  local d name dfile
  d="$(mktemp -d)"; name="$(_eg_name)-df"
  dfile="${BATS_FILE_TMPDIR}/only.txt"
  printf 'override.example.test\n' > "$dfile"
  # Config requests its own allow, but --domains-file must win (no baseline merge).
  cat > "${d}/sandbox.config.json" <<'JSON'
{ "stack": "base", "egress": { "restrict": true, "allow": ["ignored.example.test"] }, "grants": { "sshAgent": false } }
JSON
  ( cd "$d" && "${PROJECT_ROOT}/bin/sandbox-start" "$name" --domains-file "$dfile" )
  run vm_exec "cat /etc/squid/sandbox/containers/agent-${name}.domains"
  assert_success
  assert_output --partial "override.example.test"
  refute_output --partial "ignored.example.test"
  "${PROJECT_ROOT}/bin/sandbox-stop" "$name" --rm 2>/dev/null || true
  rm -rf "$d"
}
