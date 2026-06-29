#!/usr/bin/env bash
# lib/sandbox-cli.sh — Shared CLI conventions for the sandbox-* commands.
#
# Sourced transitively by every command (via lib/sandbox-common.sh). Each
# command sets a USAGE string and calls `maybe_help "$@"` right after sourcing,
# so `-h`/`--help` prints usage and exits 0 BEFORE any VM/network work — and the
# documented `sandbox-* --help` (docs/getting-started.md) actually works.

# Print the usage text and exit 0 if -h or --help appears in the arguments.
# Call as: maybe_help "$USAGE" "$@"  (usage text first, then the script's args).
# Passing $USAGE explicitly — rather than reading it as a global — keeps it a
# visible "use" for shellcheck across the non-followable lib source boundary.
maybe_help() {
  local usage="$1"
  shift
  local arg
  for arg in "$@"; do
    case "$arg" in
      -h | --help)
        printf '%s\n' "$usage"
        exit 0
        ;;
    esac
  done
}
