# Image signing keys

Prebuilt golden images are verified with [minisign](https://jedisct1.github.io/minisign/).
`sandbox-setup` checks the downloaded `SHA256SUMS` manifest against the **public
key committed here** before importing any image, so verification needs no
external trust root.

## Files

- `minisign.pub` — public key, committed. Used by `sandbox-setup` to verify pulls.
- The **secret key is never committed.** Keep it at `~/.sandbox/keys/minisign.key`
  (or pass `--key` to `sandbox-publish`).

## Generate a keypair (maintainer, one time)

```bash
mkdir -p ~/.sandbox/keys
minisign -G -p keys/minisign.pub -s ~/.sandbox/keys/minisign.key
git add keys/minisign.pub && git commit -m "chore: add image-signing public key"
```

## Trust model

- **Integrity** (always): each tarball's SHA-256 is checked against `SHA256SUMS`.
- **Authenticity** (when `minisign` + `minisign.pub` are present): `SHA256SUMS`
  itself must be signed by the secret key. This is what stops a compromised
  host from serving a malicious image with a matching checksum.
- **Fail-closed**: if any check fails, `sandbox-setup` imports nothing and falls
  back to building the image locally. An unverified image is never used.
