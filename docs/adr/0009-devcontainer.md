# ADR-0009: Reproducible development environment: devcontainer

- **Status:** Proposed — reviewed by Andrés before T2b, accepted when T2b's measurements pass
- **Date:** 2026-10-14
- **Deciders:** Andrés Amaya Garcés

## Context

Phase 0 requires that `make dev` and `make check` work from scratch on a clean machine (SPEC §10). The
development host is Windows 11. Measured on 2026-10-14:

- Installed: Docker Desktop 29.8.2 using the **WSL2 backend** (kernel `6.18.54.1-microsoft-standard-WSL2`;
  the `wsl` command fails from Git Bash, but Docker runs on WSL2), VS Code, uv 0.12, Python 3.14, gh.
- Missing: `make`, Node, Terraform, AWS CLI, pre-commit.
- Host: 12 logical CPUs and 16 GB RAM; the Docker VM currently gets 12 CPUs and about 7.7 GiB.

CI runs on Linux. Reviewers who clone the repository may use any OS.

Facts checked in the VS Code documentation ("Sharing Git credentials with your container", "Improve disk
performance", 2026-10-14): the extension reuses the host's git credential helper, forwards a running
local SSH agent, and copies the host `.gitconfig` into the container on startup; bind mounts are slower
on Windows and macOS because containers run in a VM; named volumes and "Clone Repository in Container
Volume" avoid that cost. The page covers GPG signing only, not SSH signing.

## Decision

Development happens inside a **devcontainer** (`.devcontainer/`), built from a Dockerfile with every tool
pinned to an exact version: Python and uv, Node, Terraform, AWS CLI (2.32.0 or later for `aws login`),
gh, make, pre-commit 4.6.2. CI uses the same versions. A **clean machine** means: Docker, VS Code and the
Dev Containers extension; nothing else installed on the host.

**File performance on Windows.**
- Recommended mode: open the repository with **"Clone Repository in Container Volume"**, so the source
  lives in a named volume inside the Docker VM with native file performance.
- If the folder under `C:\Dev\relay` is opened instead, `node_modules`, `.venv`, the uv cache and `.next`
  are mounted as named volumes rather than living in the bind mount.

**GitHub inside the container.**
- No token is copied into the repository or the image. HTTPS pushes reuse the host's git credential helper.
- `gh auth login` (device flow) runs inside the container, and its configuration lives in a named volume.
- **Commit signing:** the host's Windows ssh-agent (OpenSSH Authentication Agent service, automatic
  start) is forwarded, so the private key never enters the container. Because the host `.gitconfig` is
  copied and points to Windows paths (`gpg.ssh.program` and the public-key file), the container overrides
  them in its global config: `gpg.ssh.program` uses Linux `ssh-keygen`, and `user.signingkey` is set to the
  public key as a literal (`key::ssh-ed25519 …`), so signing uses the forwarded agent. VS Code does not
  document SSH signing, so T2b must prove it with a signed commit that GitHub reports as verified.

**AWS `dev` inside the container.**
- Only a profile for the `dev` project, configured by hand. Credentials come from `aws login --remote`,
  are temporary, and are cached in a named volume mounted at `~/.aws` (the host `~/.aws` is never mounted,
  and the agent is denied reading it).
- `staging` and `prod` are never configured in the container (ADR-0008).

**Docker resources.**
- Recommended: at least 4 CPUs, **8 GB RAM** and about 60 GB of disk for the Docker VM. That covers
  Postgres, Valkey, API, web, workers and Playwright browsers, and leaves 8 GB for Windows and VS Code.
- With the WSL2 backend the limit is set in `%UserProfile%\.wslconfig` (`[wsl2]`, `memory=8GB`).
- The minimum that works is measured in T2b (startup time and peak memory with `make dev` running), not
  assumed.

## Alternatives considered

- **WSL2 with tools installed by hand:** works, but every machine drifts and reviewers on macOS or Linux
  get no equivalent.
- **Native Windows tooling:** `make` and shell scripts need Windows variants, and behaviour diverges from
  Linux CI.
- **A cloud development environment (Codespaces or similar):** consumes the budget and needs network
  access for every session.

## Consequences

- One definition of the toolchain for the host, reviewers and CI.
- The first open is slow (image build); later opens reuse the image and volumes.
- With "Clone in Container Volume", the source is not visible in the Windows file explorer; it is reached
  through VS Code or `docker` commands.
- Commit signing inside the container depends on agent forwarding and the overrides above; if it fails,
  commits from the container would be rejected by the `main` ruleset.

## Verification and revisit triggers

T2b passes when:
1. In a fresh clone opened in the devcontainer, `pre-commit run --all-files` passes.
2. A commit made inside the container is signed and shows as verified on GitHub.
3. `aws login --remote` gives temporary `dev` credentials (with the T9 spike).
4. Startup time and peak memory with the full stack running are recorded in this ADR.

Revisit if signing through the forwarded agent cannot be made to work, or if the measured resources do
not fit the host.
