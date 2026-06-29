#!/usr/bin/env bash
# stacks/node.sh — Node.js alt package managers + quality/coverage tools
# Runs INSIDE container after base.sh (installs Node.js + npm, then tools)
set -eo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "Installing Node stack..."

# Node.js via mise — pre-warm the latest LTS (was pinned to NodeSource 22.x).
# This is the image's default; a per-repo sandbox.config.json `tools.node` can
# request a different version, which sandbox-start applies at start. Installed
# as ubuntu so it lives under ~ubuntu/.local/share/mise and rides the shims PATH.
su - ubuntu -c 'mise use -g node@lts'

# Alt package managers + coverage/lint/format tooling, installed into the
# mise-managed node so they ride on the shims PATH for the agent. (Runs before
# the screening shims below are created, so these build-time installs use the
# real npm directly — no shim loop.)
su - ubuntu -c 'mise exec node@lts -- npm install -g pnpm yarn c8 eslint prettier'

# Bun runtime (installed as ubuntu — lives under /home/ubuntu/.bun)
su - ubuntu -c 'curl -fsSL https://bun.sh/install | bash'

# ── Dependency screening inside the cage (composition with screen-node) ──────
# The cage protects the host, but the agent's work escapes via the deploy key
# (`git push`). A dependency that runs a malicious install script could tamper
# with the source tree that then rides out. screen-node closes that gap: it vets
# the versions an install is about to fetch (known-bad advisories, typosquats,
# the release-age worm window) BEFORE they download. We shadow the package
# managers so the agent's plain `npm install` is screened transparently, even in
# YOLO mode. This is the one place shadowing npm is correct: a throwaway cage,
# not the user's host. Screening is ON by default; `SCREEN_OFF=1 npm install ...`
# bypasses it for a single command.
su - ubuntu -c 'mise exec node@lts -- npm install -g @jagreehal/screen-node'

mkdir -p /opt/screen-shims
cat >/opt/screen-shims/_screen-shim <<'SHIM'
#!/usr/bin/env bash
# Screening shim. Invoked via a symlink named npm/pnpm/yarn/npx; $0 says which.
# Maps the real PM to its screen-node front-end (snpm/spnpm/syarn/snpx), then
# drops this shim dir from PATH so screen-node runs the REAL pm, not us (no loop).
self="$(basename "$0")"
case "$self" in
  npm)  s=snpm ;;
  pnpm) s=spnpm ;;
  yarn) s=syarn ;;
  npx)  s=snpx ;;
  *)    s="s${self}" ;;
esac
export PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF '/opt/screen-shims' | paste -sd: -)"
exec "$s" "$@"
SHIM
chmod +x /opt/screen-shims/_screen-shim
for pm in npm pnpm yarn npx; do ln -sf _screen-shim "/opt/screen-shims/${pm}"; done

# Put the shims first on PATH for every login shell. Claude runs via `bash
# --login`, and the package managers it spawns inherit this PATH (unlike shell
# aliases, which a non-interactive subprocess would not see).
echo 'export PATH="/opt/screen-shims:$PATH"' >/etc/profile.d/10-screen-shims.sh

echo "Node stack complete (dependency screening on; SCREEN_OFF=1 to bypass)"
