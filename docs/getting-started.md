# Getting started

A step-by-step guide to running your first Claude Code agent inside a sandbox. By the end you will have an isolated container, cloned a repo into it, and run Claude in YOLO mode without it being able to touch your host.

If you just want the one-line story: **screen-node is the filter, sandbox-claude is the cage.** This guide sets up the cage.

> **Time:** about 15 minutes the first time, almost all of it the one-time `sandbox-setup` build. After that, new sandboxes start in seconds.

## Before you start

You need:

- **macOS** (Apple Silicon or Intel) with [OrbStack](https://orbstack.dev/), or a **native Linux** host.
- **[GitHub CLI](https://cli.github.com/) (`gh`)**, authenticated. The tool uses it to register a per-sandbox deploy key on the repo you clone.
- **Admin access** on any repo you want an agent to push to (needed to add the deploy key).
- Roughly **16 GB RAM** if you plan to run more than one agent at once.

Check what you have:

```bash
gh auth status     # should say you're logged in; if not, run: gh auth login
```

macOS only, install OrbStack if you don't have it:

```bash
brew install orbstack
```

Linux only, install the system prerequisites (iptables, gh, etc.) and add yourself to the `incus-admin` group:

```bash
sudo sandbox-linux-prereqs
# log out and back in (or run: newgrp incus-admin) so the group takes effect
```

## Step 1: Install the commands

Clone the repo and run the installer. It drops small wrapper scripts for every `sandbox-*` command into `~/.local/bin` and makes sure that directory is on your `PATH`.

```bash
git clone https://github.com/jagreehal/sandbox-claude.git
cd sandbox-claude
./install.sh
```

Open a new terminal (or `source ~/.zshrc`) so the commands are found. Confirm:

```bash
sandbox-setup --help 2>/dev/null || command -v sandbox-start
```

## Step 2: One-time infrastructure setup

This is the slow step, and you only do it once. It creates the OrbStack VM (macOS) or configures the host (Linux), installs Incus, applies the default egress firewall, installs the Squid proxy, and builds the **golden images** that new sandboxes are cloned from.

```bash
sandbox-setup
```

What you will see, in order: prerequisites check, the OrbStack machine, Incus, container network isolation, egress filtering, the Squid proxy, then "Acquiring golden images" which runs `apt` and toolchain installs inside a container. The base image takes a few minutes; each language stack adds a couple more. When it finishes you will see `=== Setup complete ===`.

> **Faster, once signed images are published:** `SANDBOX_IMAGE_TAG=<tag> sandbox-setup` pulls a verified prebuilt image instead of building locally. It is fail-closed: anything that does not verify falls back to a local build. Use `sandbox-setup --build` to always build locally.

## Step 3: Create your first sandbox

Point it at a repo you have admin on. Pick a stack that matches the project (`base`, `node`, `python`, `rust`, `go`, `dotnet`, `unison`).

```bash
sandbox-start my-project git@github.com:you/your-repo.git --stack node
```

This clones a golden image (instant), generates and registers a deploy key for the repo, clones the repo into `/workspace/project`, and prints a connection summary with the slot, ports, and the exact commands to connect.

Want a throwaway sandbox with no repo? Just `sandbox-start scratch`.

## Step 4: Open a shell and look around

```bash
sandbox my-project
```

You are now `ubuntu` inside the container, in `/workspace/project`. The host filesystem, your credentials, and your shell are not reachable from here. Type `exit` to leave.

Run a one-off command without opening a shell:

```bash
sandbox my-project --cmd "git status"
```

## Step 5: Run Claude Code in YOLO mode

```bash
sandbox my-project --claude
```

This launches `claude --dangerously-skip-permissions` inside the container. YOLO mode is the point: because the agent is caged, it can edit, run, and install freely without being able to reach your host. The first launch walks you through authentication; the token is stored inside the container and survives restarts.

## Step 5b: Run Codex instead (or as well)

```bash
sandbox my-project --codex
```

This launches `codex --dangerously-bypass-approvals-and-sandbox` — Codex's own equivalent of YOLO mode, safe here because the Incus cage is already the real sandbox boundary. The first launch prompts you to sign in with ChatGPT: Codex opens a browser OAuth flow that calls back to `http://localhost:1455`, which only reaches your browser if that port is forwarded from the container. Set `grants.codexLogin: true` in `sandbox.config.json` (see [Configuration](../README.md#configuration)) before first login so `sandbox-start` forwards it automatically; the credential is then stored inside the container and survives restarts, same as Claude's.

## Step 6: See what is running

```bash
sandbox-list
```

A table of every sandbox with its state, ports, egress mode, and health (Docker, ssh-agent, Claude auth, repo + branch).

## Step 7: Stop or remove

```bash
sandbox-stop my-project        # stop, keep the filesystem; restart later with sandbox-start
sandbox-start my-project       # restart a stopped sandbox
sandbox-stop my-project --rm   # destroy it and remove its deploy key from GitHub
```

## What you just got, and what you did not

**Protected:** your host filesystem and credentials (the agent runs in a container, inside a VM on macOS), per-container isolation, SSH keys that never touch the container's disk, and a default egress firewall that drops everything except DNS, HTTP, HTTPS, and SSH.

**Not protected, by design:** the agent can push to the repo its deploy key is scoped to, and it can read any API keys you injected. Without `--restrict-domains` it can reach any HTTPS endpoint. See the [Security Model](../README.md#security-model) for the full, honest list, it is worth reading once.

## Going further

- **Lock down egress to an allowlist:** add `--restrict-domains` when you start a sandbox. It limits HTTPS to an approved domain list (SSH and DNS stay open, see the Security Model).
- **Screen dependencies inside the cage (node):** the node stack already shadows `npm`/`pnpm`/`yarn` with [screen-node](https://github.com/jagreehal/screen-node), so an agent's `npm install` is vetted against malware advisories, typosquats, and the release-age worm window before anything is fetched. Bypass per command with `SCREEN_OFF=1`, or per sandbox with `sandbox-start <name> --no-screen`.
- **Expose a port** (e.g. a dev server or database): `sandbox-expose my-project 5432`.
- **Full command reference:** see the [README](../README.md#commands-reference).

## If something goes wrong

- **`gh` not authenticated:** run `gh auth login`, then retry.
- **Setup failed partway:** `sandbox-setup` is safe to re-run; it skips what is already done.
- **Need a clean slate:** `sandbox-nuke` destroys all containers, golden images, and the OrbStack VM. Then run `sandbox-setup` again.
- More symptoms and fixes are in the [Troubleshooting](../README.md#troubleshooting) section.
