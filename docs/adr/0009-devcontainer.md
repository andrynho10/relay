# ADR-0009: Reproducible development environment: devcontainer

- **Status:** Accepted
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
  start) is forwarded, so the private key never enters the container. The host `.gitconfig` that VS Code
  copies points to Windows paths (`gpg.ssh.program` and the public-key file), so the container sets
  `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n` environment variables, which git applies
  over every config file: `gpg.format=ssh`, `gpg.ssh.program=ssh-keygen` (Linux), `commit.gpgsign=true`,
  and `user.signingkey` as a public-key literal (`key::ssh-ed25519 …`) taken from the host variable
  `RELAY_GIT_SIGNING_KEY`. Editing the copied `.gitconfig` was rejected because VS Code may copy it again.
  `post-start.sh` warns when the variable is missing, no agent is forwarded, or the key is not loaded.
- **One-time host setup** (Windows PowerShell), then restart VS Code:
  `[Environment]::SetEnvironmentVariable('RELAY_GIT_SIGNING_KEY', 'key::' + (Get-Content "$env:USERPROFILE\.ssh\id_ed25519_signing.pub"), 'User')`
- **Hooks and host commits:** `pre-commit install` writes `.git/hooks/pre-commit`. When the host folder
  is opened (bind mount), that hook is shared with the host, so host commits need `pre-commit` on the
  host `PATH` too: `uv tool install pre-commit==4.6.2`. With "Clone Repository in Container Volume" this
  does not apply.

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

Verified in T2b (2026-10-14, Windows 11 host, amd64):
- The image builds in about 66 s from a pulled base image; size 3.4 GB, mostly the devcontainers base
  image. All checksums and the AWS CLI PGP signature verify during the build.
- Tool versions in the image: Python 3.14.8, uv 0.12.21, Node 24.21.0 (npm 11.19.0), Terraform 1.16.4,
  AWS CLI 2.37.6, gh 2.101.0, pre-commit 4.6.2, GNU Make 4.4.1.
- `post-create.sh` and `pre-commit run --all-files` pass inside the container, with the same named volumes
  as `devcontainer.json` (including a volume created beforehand as root).
- A commit made from VS Code inside the container, signed through the forwarded host ssh-agent, shows as
  verified on GitHub (commit `93579e5`, reason `valid`).

Checked later, as part of other tasks; a failure there leads to a new ADR:
- T9 spike: `aws login --remote` gives temporary `dev` credentials inside the container.
- T6: startup time and peak memory with the full local stack running fit the recommended resources.

Revisit if signing through the forwarded agent stops working, or if the measured resources do not fit
the host.
