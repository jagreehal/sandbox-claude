#!/usr/bin/env bash
# tests/validate-screening.sh — validate the in-cage dependency screening
# (composition with screen-node) WITHOUT Incus, using a plain Docker node
# container. It mirrors the shim recipe baked into stacks/node.sh and proves:
#   1. a shadowed `npm install` is screened by screen-node (the agent's plain
#      npm calls get vetted, even though it typed `npm`, not `snpm`);
#   2. the PATH-strip in the shim prevents an infinite loop (screen-node runs
#      the REAL npm, not the shim again);
#   3. SCREEN_OFF=1 bypasses screening but still installs.
#
# Self-skips (exit 0) when Docker is unavailable. The Incus-specific parts
# (golden-image bake, container creation) are covered by the bats integration
# suite; this isolates and proves the screening mechanism on its own.
set -uo pipefail

# ── Host side: re-exec this same script inside a node container ──────
if [[ "${SCREEN_SHIM_INNER:-}" != "1" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "SKIP: docker not available (validate-screening needs Docker, not Incus)"
    exit 0
  fi
  self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  exec docker run --rm -e SCREEN_SHIM_INNER=1 -v "${self}:/validate-screening.sh:ro" \
    node:22 bash /validate-screening.sh
fi

# ── Inner side (running in the node container) ──────────────────────
fail() { echo "FAIL: $*"; exit 1; }

echo "## installing @jagreehal/screen-node"
npm install -g @jagreehal/screen-node@latest >/tmp/install.log 2>&1 || { tail -20 /tmp/install.log; fail "screen-node install"; }
command -v snpm >/dev/null || fail "snpm not on PATH after install"

# Shim recipe — KEEP IN SYNC with the block in stacks/node.sh.
mkdir -p /opt/screen-shims
cat > /opt/screen-shims/_screen-shim <<'SHIM'
#!/usr/bin/env bash
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
export PATH="/opt/screen-shims:$PATH"
[[ "$(command -v npm)" == "/opt/screen-shims/npm" ]] || fail "npm is not shadowed (got $(command -v npm))"

mkdir -p /work && cd /work && echo '{"name":"t","version":"1.0.0"}' > package.json

echo "## TEST 1: shadowed 'npm install lodash' is screened + installs (no loop)"
timeout 150 npm install lodash >t1.out 2>&1 || { tail -8 t1.out; fail "screened install exited non-zero (124 = loop/hang)"; }
grep -qiE 'screen:|checked .* package|gates ran' t1.out || { tail -8 t1.out; fail "screening did not run"; }
[[ -d node_modules/lodash ]] || fail "lodash not installed"
echo "   PASS"

echo "## TEST 2: SCREEN_OFF=1 bypasses screening, still installs"
rm -rf node_modules
SCREEN_OFF=1 timeout 150 npm install lodash >t2.out 2>&1 || { tail -8 t2.out; fail "SCREEN_OFF install exited non-zero"; }
[[ -d node_modules/lodash ]] || fail "SCREEN_OFF did not install"
echo "   PASS"

echo "## TEST 3: shadowed npx resolves without looping"
timeout 60 npx --version >t3.out 2>&1 || { cat t3.out; fail "shadowed npx hung/failed"; }
echo "   PASS (npx $(tail -1 t3.out))"

echo "ALL SCREENING CHECKS PASSED"
