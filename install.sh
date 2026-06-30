#!/usr/bin/env bash
# install.sh — Install wrapper scripts for all bin/sandbox* commands into a directory in your PATH
set -euo pipefail

DEST="${1:-${HOME}/.local/bin}"
mkdir -p "$DEST"

SCRIPT_DIR="$(cd "$(dirname "$0")/bin" && pwd)"

# Clean up old symlinks from previous installs
for script in "${SCRIPT_DIR}"/sandbox*; do
  name="$(basename "$script")"
  target="${DEST}/${name}"
  if [[ -L "$target" ]]; then
    rm "$target"
  fi
done

# Clean up renamed commands from previous installs
rm -f "${DEST}/sandbox-create" 2>/dev/null || true

echo "Installing sandbox commands to ${DEST}..."
echo ""

for script in "${SCRIPT_DIR}"/sandbox*; do
  name="$(basename "$script")"
  chmod +x "$script"
  cat >"${DEST}/${name}" <<EOF
#!/usr/bin/env bash
exec "${script}" "\$@"
EOF
  chmod +x "${DEST}/${name}"
  echo "  ${name} → ${DEST}/${name}"
done

echo ""

# Ensure DEST is in PATH
if [[ ":$PATH:" != *":${DEST}:"* ]]; then
  SHELL_RC=""
  if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$(basename "${SHELL:-}")" == "zsh" ]]; then
    SHELL_RC="${HOME}/.zshrc"
  elif [[ -f "${HOME}/.bashrc" ]]; then
    SHELL_RC="${HOME}/.bashrc"
  elif [[ -f "${HOME}/.bash_profile" ]]; then
    SHELL_RC="${HOME}/.bash_profile"
  fi

  if [[ -n "$SHELL_RC" ]]; then
    EXPORT_LINE="export PATH=\"\$HOME/.local/bin:\$PATH\""
    if ! grep -qF '.local/bin' "$SHELL_RC" 2>/dev/null; then
      echo "" >>"$SHELL_RC"
      echo "# Added by sandbox-claude installer" >>"$SHELL_RC"
      echo "$EXPORT_LINE" >>"$SHELL_RC"
      echo "Added ${DEST} to PATH in ${SHELL_RC}"
      echo "Run 'source ${SHELL_RC}' or open a new terminal to apply."
    else
      echo "${DEST} already referenced in ${SHELL_RC} but not in current PATH."
      echo "Run 'source ${SHELL_RC}' or open a new terminal to apply."
    fi
  else
    echo "WARNING: ${DEST} is not in your PATH and could not detect shell config."
    echo "Add this to your shell profile:"
    echo ""
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
  fi
fi

echo "Done. Run 'sandbox-setup' to initialise the infrastructure."
