#!/usr/bin/env bash
# lib/sandbox-images.sh — Golden image acquisition.
#
# Two ways to get a golden-<stack>/ready snapshot:
#   BUILD (default today): launch Ubuntu, run the stack script inside, snapshot.
#                          Correct but slow (~10 min: apt + toolchain installs).
#   PULL  (opt-in):        download a maintainer-published, verified image
#                          tarball and import it. Fast (~1 min download).
#
# Sourced by sandbox-setup (the consumer) and sandbox-publish (the producer).
# Assumes lib/sandbox-common.sh is already sourced (uses vm_*, info/ok/warn/err,
# SANDBOX_PLATFORM, SANDBOX_MACHINE).
#
# SECURITY INVARIANT — FAIL CLOSED:
#   The pull path NEVER imports a tarball it could not verify. If the download,
#   checksum, or signature check fails, the functions return non-zero WITHOUT
#   importing anything, and the caller falls back to a local build. An
#   unverified image is never used. Authenticity (minisign) is enforced when
#   the tool + public key are present; absent them, a LOUD warning downgrades
#   to integrity-only (checksum) and never to "trust blindly".
#
# STATUS: the Incus-touching pull/import path is syntax-verified but has not
# yet been exercised end-to-end on a real Incus host. It is gated OFF by
# default (SANDBOX_IMAGE_TAG empty) so setup behaves exactly as before until a
# maintainer publishes images with sandbox-publish and a user opts in.

# Repo root (this file lives in lib/), used to locate the committed public key.
_SANDBOX_IMAGES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Config (all overridable by env) ───────────────────────────────
# Prebuilt images live on GitHub Releases: gh is already a dependency and the
# downloads are plain HTTPS, compatible with the container egress allowlist.
SANDBOX_IMAGE_REPO="${SANDBOX_IMAGE_REPO:-jagreehal/sandbox-claude}"
# Release tag holding the image assets. EMPTY disables pulling (build-only).
SANDBOX_IMAGE_TAG="${SANDBOX_IMAGE_TAG:-}"
# Minisign public key verifying the SHA256SUMS manifest's authenticity.
# Committed to the repo so the authenticity check needs no external trust root.
SANDBOX_IMAGE_PUBKEY="${SANDBOX_IMAGE_PUBKEY:-${_SANDBOX_IMAGES_ROOT}/keys/minisign.pub}"
# Local cache for downloaded tarballs + manifest.
SANDBOX_IMAGE_CACHE="${SANDBOX_IMAGE_CACHE:-${HOME}/.sandbox/images}"

# ── Portable sha256 (macOS shasum / Linux sha256sum) ──────────────
_sha256() {
  if command -v sha256sum &>/dev/null; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum &>/dev/null; then shasum -a 256 "$1" | awk '{print $1}'
  else return 1; fi
}

# ── Verify the manifest's authenticity + one file's integrity ─────
# verify_image <cache_dir> <filename>
# Returns 0 only if the file's checksum matches the (authenticated) manifest.
verify_image() {
  local cache="$1" file="$2"
  local sums="${cache}/SHA256SUMS"
  [[ -f "$sums" ]] || { err "manifest SHA256SUMS missing — refusing image"; return 1; }

  # Authenticity: the manifest must be signed by our key (when verifiable).
  if command -v minisign &>/dev/null && [[ -f "$SANDBOX_IMAGE_PUBKEY" ]]; then
    minisign -Vm "$sums" -p "$SANDBOX_IMAGE_PUBKEY" &>/dev/null \
      || { err "minisign authenticity check FAILED for SHA256SUMS — refusing image"; return 1; }
  else
    warn "minisign or public key unavailable: authenticity NOT verified (integrity-only)."
  fi

  # Integrity: the tarball must match the checksum recorded in the manifest.
  local want got
  want="$(awk -v f="$file" '$2==f {print $1}' "$sums")"
  [[ -n "$want" ]] || { err "no checksum for ${file} in manifest — refusing image"; return 1; }
  got="$(_sha256 "${cache}/${file}")" || { err "cannot compute sha256 — refusing image"; return 1; }
  [[ "$want" == "$got" ]] || { err "checksum MISMATCH for ${file} — refusing image"; return 1; }
  return 0
}

# ── Move a file host -> sandbox VM (macOS via orb; Linux is the host) ──
vm_put_file() {
  local src="$1" dst="$2"
  if [[ "$SANDBOX_PLATFORM" == "macos" ]]; then
    orb run -m "${SANDBOX_MACHINE}" tee "$dst" < "$src" >/dev/null
  else
    cp "$src" "$dst"
  fi
}

# ── Move a file sandbox VM -> host (used by the publisher) ─────────
vm_get_file() {
  local src="$1" dst="$2"
  if [[ "$SANDBOX_PLATFORM" == "macos" ]]; then
    orb run -m "${SANDBOX_MACHINE}" cat "$src" > "$dst"
  else
    cp "$src" "$dst"
  fi
}

# ── Import a VERIFIED tarball and reconstruct golden-<stack>/ready ──
# Keeps downstream tooling (sandbox-start, require_golden) unchanged: the end
# state is identical to a locally-built golden image.
import_golden_tarball() {
  local tarball="$1" golden_name="$2"
  local vm_tarball="/tmp/${golden_name}.tar.gz"
  local img_alias="import-${golden_name}"

  vm_put_file "$tarball" "$vm_tarball" || return 1

  # Import the unified image, launch a container from it with the same security
  # flags a local base build uses, snapshot 'ready', then tidy up.
  # (incus image import has no --reuse, so clear any stale alias first.)
  vm_exec "incus image delete '${img_alias}' 2>/dev/null || true"
  vm_exec "incus image import '${vm_tarball}' --alias '${img_alias}'" || return 1
  vm_exec "incus delete '${golden_name}' --force 2>/dev/null || true"
  vm_exec "incus launch '${img_alias}' '${golden_name}' \
            -c security.nesting=true \
            -c security.syscalls.intercept.mknod=true \
            -c security.syscalls.intercept.setxattr=true" || return 1
  vm_exec "sleep 3 && incus exec '${golden_name}' -- cloud-init status --wait 2>/dev/null || true"
  vm_exec "incus stop '${golden_name}'" || return 1
  vm_exec "incus snapshot create '${golden_name}' ready" || return 1
  vm_exec "incus image delete '${img_alias}' 2>/dev/null || true"
  vm_exec "rm -f '${vm_tarball}' 2>/dev/null || true"
}

# ── Try pull -> verify -> import for one stack ────────────────────
# Returns 0 if a verified image was imported; non-zero (caller builds locally)
# if pulling is disabled or any step fails. No image is imported unverified.
pull_golden_image() {
  local stack="$1"
  local golden_name="golden-${stack}"

  [[ -n "$SANDBOX_IMAGE_TAG" ]] || return 1            # pulling is opt-in
  command -v gh &>/dev/null || { warn "gh missing: cannot pull ${golden_name}"; return 1; }

  mkdir -p "$SANDBOX_IMAGE_CACHE"
  info "Pulling prebuilt ${golden_name} (${SANDBOX_IMAGE_REPO}@${SANDBOX_IMAGE_TAG})..."
  gh release download "$SANDBOX_IMAGE_TAG" -R "$SANDBOX_IMAGE_REPO" \
      -p "SHA256SUMS" -p "SHA256SUMS.minisig" -p "${golden_name}.tar.gz" \
      -D "$SANDBOX_IMAGE_CACHE" --clobber 2>/dev/null \
    || { warn "download failed for ${golden_name} — will build locally"; return 1; }

  verify_image "$SANDBOX_IMAGE_CACHE" "${golden_name}.tar.gz" \
    || { warn "verification failed for ${golden_name} — will build locally"; return 1; }

  import_golden_tarball "${SANDBOX_IMAGE_CACHE}/${golden_name}.tar.gz" "$golden_name" \
    || { warn "import failed for ${golden_name} — will build locally"; return 1; }

  ok "${golden_name}/ready imported from verified prebuilt image"
}
