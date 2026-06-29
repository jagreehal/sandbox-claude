#!/usr/bin/env bash
# lib/sandbox-config.sh — Per-repo sandbox.config.json reader.
#
# A repo declares its sandbox spec in a committed `sandbox.config.json` at its
# root (schema: sandbox.schema.json). sandbox-start reads it on the HOST in
# "local mode" (run from inside a checkout) BEFORE the container is created, so
# config can drive image/stack selection, resources, and egress.
#
# Type-safety is authoring-time (the "$schema" reference gives editor
# autocomplete + validation). At runtime we do NOT re-validate the whole schema
# in bash; we read values with jq (applying schema defaults inline) and
# hand-check only the handful of fields where a bad value is dangerous or
# produces a cryptic failure (stack enum, cpu/memory shape, tool specifiers,
# env var names). Resolution order is owned by the caller: flag > config >
# default — so every getter here takes the schema default and the caller only
# falls back to it when no flag was given.
#
# Assumes lib/sandbox-common.sh is already sourced (uses die/warn, require_command).

SANDBOX_CONFIG_BASENAME="sandbox.config.json"
# Stacks that ship a stacks/<name>.sh script. Kept in sync with the schema enum.
SANDBOX_VALID_STACKS="base node python go rust dotnet unison"
# Public schema URL for the "$schema" key in generated configs. The config lives
# in a DIFFERENT repo than the schema, so a relative path won't resolve — a URL
# does (editors fetch it), and it matches the schema's own $id.
SANDBOX_SCHEMA_URL="https://raw.githubusercontent.com/jagreehal/sandbox-claude/main/sandbox.schema.json"

# Guess a repo's stack from build-tool marker files in <dir> (default cwd).
# Echoes one of SANDBOX_VALID_STACKS; "base" when nothing recognisable is found.
detect_stack() {
  local d="${1:-$PWD}"
  if [[ -f "$d/package.json" ]]; then
    echo node
  elif [[ -f "$d/pyproject.toml" || -f "$d/requirements.txt" || -f "$d/setup.py" ]]; then
    echo python
  elif [[ -f "$d/go.mod" ]]; then
    echo go
  elif [[ -f "$d/Cargo.toml" ]]; then
    echo rust
  elif compgen -G "$d/*.csproj" >/dev/null 2>&1 || compgen -G "$d/*.sln" >/dev/null 2>&1; then
    echo dotnet
  else
    echo base
  fi
}

# Locate the config file for a directory (default: cwd). Echoes the path if
# present, empty otherwise. Does not recurse — the file must sit at the dir root,
# matching where sandbox-start is expected to run (the repo top level).
find_config_file() {
  local dir="${1:-$PWD}"
  local path="${dir%/}/${SANDBOX_CONFIG_BASENAME}"
  if [[ -f "$path" ]]; then
    printf '%s' "$path"
  fi
}

# True if the file is parseable JSON. Used to fail fast with a clear message
# rather than letting malformed JSON surface as empty values downstream.
config_is_valid_json() {
  local file="$1"
  jq -e . "$file" >/dev/null 2>&1
}

# Read a scalar at a jq path, falling back to a default when absent or null.
# Usage: config_scalar <file> '.stack' 'base'
config_scalar() {
  local file="$1" path="$2" default="${3:-}"
  jq -r --arg d "$default" "(${path}) // \$d" "$file" 2>/dev/null
}

# Read a boolean at a jq path as the strings "true"/"false", with a default.
# NB: jq's `//` treats `false` as empty (it short-circuits on null OR false), so
# a literal `false` in the config would wrongly fall through to the default.
# Test for null explicitly instead.
config_bool() {
  local file="$1" path="$2" default="$3"
  jq -r --argjson d "$default" "if (${path}) == null then \$d else (${path}) end" "$file" 2>/dev/null
}

# Emit array elements one per line (empty output if absent).
# Usage: config_array <file> '.egress.allow'
config_array() {
  local file="$1" path="$2"
  jq -r "(${path} // [])[]" "$file" 2>/dev/null
}

# Emit "tool@version" lines from the .tools object (empty if none).
config_tools() {
  local file="$1"
  jq -r '(.tools // {}) | to_entries[] | "\(.key)@\(.value)"' "$file" 2>/dev/null
}

# Validate the dangerous fields. Dies with a clear message on a bad value.
# Schema covers everything in the editor; this guards the few values that, if
# wrong, break the container build or produce a cryptic incus/mise error.
validate_config() {
  local file="$1"

  config_is_valid_json "$file" ||
    die "Invalid JSON in ${file}. Check for trailing commas / unquoted keys."

  local stack
  stack=$(config_scalar "$file" '.stack' 'base')
  if ! printf '%s ' $SANDBOX_VALID_STACKS | grep -qw "$stack"; then
    die "Invalid stack '${stack}' in ${file}. Valid: ${SANDBOX_VALID_STACKS}."
  fi

  local cpu mem
  cpu=$(config_scalar "$file" '.resources.cpu' '')
  if [[ -n "$cpu" && ! "$cpu" =~ ^[0-9]+(-[0-9]+)?$ ]]; then
    die "Invalid resources.cpu '${cpu}' in ${file}. Expected an integer (e.g. \"4\") or range."
  fi
  mem=$(config_scalar "$file" '.resources.memory' '')
  if [[ -n "$mem" && ! "$mem" =~ ^[0-9]+([KMGT]i?B)?$ ]]; then
    die "Invalid resources.memory '${mem}' in ${file}. Expected e.g. \"8GiB\" or \"2048MiB\"."
  fi

  # Tool specifiers: KEY@VERSION where KEY is a plausible mise tool name.
  local entry
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    if [[ ! "$entry" =~ ^[A-Za-z0-9_.-]+@[A-Za-z0-9_.*-]+$ ]]; then
      die "Invalid tools entry '${entry}' in ${file}. Expected \"<tool>\": \"<version>\"."
    fi
  done < <(config_tools "$file")

  # Forwarded env var names must be valid identifiers (values live elsewhere).
  local name
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if [[ ! "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      die "Invalid grants.env name '${name}' in ${file}. Must be a valid env var identifier."
    fi
  done < <(config_array "$file" '.grants.env')
}

# Build the effective egress allowlist file: the bundled baseline UNION the
# repo's egress.allow extras. The baseline is always included so Claude Code
# keeps working inside the cage regardless of what a repo lists. Written to
# <out_file> (a stable per-container path, so a later restart can re-read it);
# the parent dir is created if needed. Echoes the path written.
build_effective_domains_file() {
  local config_file="$1" baseline="$2" out_file="$3"
  mkdir -p "$(dirname "$out_file")"
  cat "$baseline" >"$out_file"
  if [[ -n "$config_file" ]]; then
    {
      echo ""
      echo "# ── Added from $(basename "$config_file") (egress.allow) ──"
      config_array "$config_file" '.egress.allow'
    } >>"$out_file"
  fi
  printf '%s' "$out_file"
}
