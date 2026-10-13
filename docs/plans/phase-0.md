# Phase 0 — Foundations

Status: **approved 2026-10-13 · re-scoped for cost 2026-10-13** · Spec: `docs/SPEC.md` §10, §11, §13 ·
Target release: `v0.1.0` (manual)

## Goal
Monorepo, git workflow, reproducible local environment, CI with baseline security scans, Terraform for
`dev`, `staging` and `prod` (prod validated only), initial ADRs, threat model v1, and a **walking skeleton**
(`/health` + minimal page) deployed on demand to an ephemeral staging via Terraform and GitHub Actions
with OIDC. AWS cost stays at a few dollars a month most of the time (ADR-0007).

## Decisions taken at kickoff and re-scoping
| Topic | Decision |
|---|---|
| Scope | "CV cut line" core vs. Roadmap (SPEC §10.0, ADR-0007) |
| AWS account | New account experience, paid plan, projects `dev` and `staging` (each an AWS account in an AWS-managed organization). The managed SCP denies `iam:*Provider*`, so the GitHub OIDC provider cannot be created; if the T9 spike confirms it, **advanced features are activated** (irreversible; projects become member accounts we administer; spend limits are removed). Other triggers: Identity Center for another person, GuardDuty/Security Hub (ADR-0008) |
| Access | `dev`: Andrés + agent, temporary credentials only (`aws login`) from the devcontainer. `staging`: GitHub Actions via OIDC only; the deploy role trusts only this repo and the `staging` GitHub Environment. `prod`: no project, no credentials. Single exception: `infra/bootstrap`, run once per project with Andrés's credentials |
| Environments | Daily development is 100 % local (Docker Compose). `dev` only for what cannot be emulated locally (Bedrock embeddings, testing a Terraform module before staging); everything created there is destroyed after use. `staging` applied on demand. `prod` in Terraform, `validate` only, never applied |
| Budget | AWS Budgets alerts at 5, 10 and 20 USD; spend limits while on plain projects; after advanced features, a Budget action that applies a deny policy at 20 USD (to verify) + Cost Anomaly Detection; staging destroyed when idle |
| Secrets | Anthropic API key per environment, each in its own Anthropic workspace with its own spend limit. Dev: local `.env` (gitignored). Staging: Secrets Manager secret created in `infra/bootstrap` (survives destroys, value never in Terraform state), value set by Andrés |
| AWS region | The region AWS assigns to the projects from the contact country (`us-east-2` expected for the Americas; confirmed in the T9 spike) (ADR-0006) |
| Local dev environment | Devcontainer; "clean machine" = Docker + VS Code + Dev Containers only (ADR-0009) |
| Network | No NAT Gateway (ADR-0010, written in T10) |
| Repo visibility | Public (free rulesets, CodeQL, secret-scanning push protection) |
| Deferred to Phase 1 ADRs | Embeddings provider, observability backend, Langfuse hosting |
| Name / domain | "Relay" is a codename; staging uses the default `*.cloudfront.net` domain (no ADR) |

## Prerequisites (owner: Andrés)
- [x] SSH commit-signing key configured in git and GitHub.
- [x] Windows ssh-agent running with the signing key loaded, and `gpg.ssh.program` pointing to the
      Windows `ssh-keygen` (commits from the agent's non-interactive shell fail without it).
- [ ] GitHub: enable secret scanning + push protection; create the `staging` environment (before T11).
- [ ] Install the VS Code Dev Containers extension (before T2b).
- [ ] Anthropic console: one workspace + API key per environment (`dev`, `staging`), each with a spend limit.
- [ ] **Just before T9:** upgrade the AWS account to the paid plan; create projects `dev` and `staging`
      with a spend limit each; create AWS Budgets alerts at 5, 10 and 20 USD.
- [ ] **After the T9 spike, if the OIDC block is confirmed:** activate advanced features (irreversible),
      then the Budget action at 20 USD and Cost Anomaly Detection.
- [ ] Run `infra/bootstrap` once per project (`dev`, `staging`) following the runbook, and load the
      staging Anthropic key with `aws secretsmanager put-secret-value`.
- [ ] Apply the `main` ruleset (T13).

## Tasks (one branch + PR each)
- [ ] **T0 `docs/phase-0-plan`** — this file; SPEC re-scoping; update `docs/PROGRESS.md` and CLAUDE.md.
- [ ] **T1 `chore/repo-hygiene`** — `.gitignore`, `.dockerignore`, `.gitattributes` (force LF), `.editorconfig`,
      `.env.example` (includes `ANTHROPIC_API_KEY=` with no value and a comment pointing to the dev
      workspace), `.pre-commit-config.yaml` (gitleaks, ruff, ruff-format, prettier, terraform fmt, check-yaml),
      README template. Verify Anthropic workspace spend limits in the official docs.
- [ ] **T2 `docs/initial-adrs`** — ADRs 0001–0009 (list below). ADR-0009 is reviewed with Andrés before T2b.
- [ ] **T2b `chore/devcontainer`** — implement the devcontainer per ADR-0009; measure startup time and resources.
- [ ] **T3 `feat/api-skeleton`** — FastAPI, Pydantic v2, pydantic-settings; `GET /health` (liveness),
      `GET /health/ready` (DB ping); RFC 9457 error handler; JSON logs with `trace_id`/`tenant_id`;
      mandatory declarative authorization per route + a test that fails if any route lacks one;
      Alembic migration 0001 (reversible): `CREATE EXTENSION vector` + `relay_app` role without `BYPASSRLS`.
- [ ] **T4 `feat/worker-skeleton`** — package, config, entrypoint with graceful SIGTERM shutdown, tests.
      No SQS consumer yet (Phase 1).
- [ ] **T5 `feat/web-skeleton`** — Next.js App Router, strict TS, Tailwind, ESLint; `/` shows API status;
      Playwright + axe with zero violations; `standalone` build.
- [ ] **T6 `chore/local-env`** — `docker-compose.yml` (Postgres 16+ with pgvector, Valkey, api, web) with
      healthchecks; `Makefile`: `dev`, `check`, `test-integration`, `fmt`, `down`. S3/SQS emulators decided in Phase 1.
- [ ] **T7 `ci/pipeline`** — `ci.yml` (ruff, mypy --strict, pytest, integration with service containers,
      eslint, tsc, Playwright + axe, image builds); `security.yml` with the baseline only: **gitleaks, CodeQL,
      Trivy (fs + image), Dependabot**; CODEOWNERS; PR template. Actions pinned by SHA.
      Semgrep, Checkov and SBOM → Roadmap.
- ~~**T8 `ci/release-please`**~~ — moved to Roadmap. The `v0.1.0` release is created manually in T13.
      (Task numbers are kept so references stay valid.)
- [ ] **T9 `feat/infra-bootstrap`** — **starts with a spike**, in this order; results go into ADR-0008:
      1. **Temporary credentials for `dev` inside the devcontainer** with `aws login --remote --profile relay-dev`
         (AWS CLI ≥ 2.32.0, cache in a named volume), configuring the profile by hand — **without** the
         Agent Toolkit setup script (unreviewed `curl` script, AWS MCP server outside SPEC §6, rules file that
         would compete with CLAUDE.md). **Blocking: if there is no way without long-lived keys, stop and ask.**
      2. **Confirm the OIDC block:** `aws iam create-open-id-connect-provider` in `dev` is expected to be denied
         by `DenyIAMRestrictedActions` (`iam:*Provider*`). Also check `iam:CreateRole` with a GitHub trust
         policy and an S3 state bucket (`use_lockfile`).
      3. **Region** actually assigned to the projects (AWS Settings → Project → Additional info) → ADR-0006.
      4. If the block is confirmed: Andrés activates advanced features (irreversible; removes spend limits),
         then verify in the docs and create the Budget action that applies a deny policy at 20 USD, plus Cost
         Anomaly Detection. Re-check that `aws login` still works for `dev` afterwards.
      5. Terraform providers pin `allowed_account_ids` per environment, so that choosing the wrong session on
         the "Choose AWS sessions" page cannot apply to the wrong project.
      **If anything else is blocked, stop and ask.** Then: `infra/bootstrap` (state bucket, OIDC provider,
      deploy role trusted only by `repo:andrynho10/relay:environment:staging`, Secrets Manager secret for the
      staging Anthropic key without a value) + runbook `docs/runbooks/bootstrap-account.md`, which documents
      the bootstrap exception (Andrés's own credentials, once per project). ADR-0008 moves to *Accepted*.
- [ ] **T10 `feat/infra-staging-skeleton`** — VPC (2 AZ) **without NAT Gateway**: Fargate tasks (api, web)
      in public subnets with a public IP and a security group that only accepts traffic from the ALB; RDS
      Postgres single-AZ `t4g.micro` in private subnets with no internet egress; ECR, ALB, CloudFront
      (default domain), Secrets Manager for DB credentials, AWS-managed KMS keys, CloudWatch logs.
      `infra/envs/prod` mirrors staging and is only `validate`d. `terraform.yml`: `plan` for staging on
      every PR, `fmt`/`validate` for all envs. ADR-0010 (network without NAT; VPC endpoints rejected on cost).
      Stop and ask if this grows.
- [ ] **T11 `ci/deploy-staging`** — `deploy-staging.yml` on **`workflow_dispatch`** (not on every merge):
      build → push to ECR (tag = SHA) → `terraform apply` (staging, OIDC) → smoke test `/health/ready` and the
      page through CloudFront. `destroy-staging.yml` on `workflow_dispatch`. Both use the `staging`
      GitHub Environment. Runbook `docs/runbooks/staging.md` (deploy, destroy, cost check).
- [ ] **T12 `docs/threat-model-v1`** — STRIDE per component and data flow, with planned mitigations per phase,
      including the no-NAT network, the account model and access matrix, and the bootstrap exception
      (human admin credentials, once per project) as an explicit risk with its controls.
- [ ] **T13 `chore/phase-0-close`** — `main` ruleset JSON (existing checks only), update CLAUDE.md
      (real commands), PROGRESS, BACKLOG review, manual signed tag + `gh release create v0.1.0` with notes.

## ADRs (only real decisions)
| # | ADR | Written in |
|---|---|---|
| 0001 | Record architecture decisions (MADR, immutable, superseded by new ADRs) | T2 |
| 0002 | AWS as the single cloud | T2 |
| 0003 | No local/self-hosted LLM; Claude API behind `LLMGateway` | T2 |
| 0004 | PostgreSQL + pgvector + RLS as the single database | T2 |
| 0005 | ECS Fargate for compute | T2 |
| 0006 | Primary region = the one AWS assigns to the projects (`us-east-2` expected) | T2 as *Proposed*, *Accepted* after the T9 spike |
| 0007 | **Scope and cost**: CV cut line, two applied environments, ephemeral staging, budgets, measured cost | T2 |
| 0008 | **AWS account model**: `dev`/`staging` projects in an AWS-managed organization; access matrix; bootstrap exception; advanced features activated when the OIDC block is confirmed (or for Identity Center / GuardDuty / Security Hub), with the cost-control trade-off | T2 as *Proposed*, *Accepted* after the T9 spike |
| 0009 | Devcontainer (Windows file performance, GitHub and AWS `dev` auth inside the container, Docker resources) | T2 |
| 0010 | **Network without NAT Gateway** (public-subnet Fargate + strict SGs; VPC endpoints rejected on cost) | T10 |

## Definition of done
- `make dev` and `make check` work from a clean clone inside the devcontainer (verified after wiping volumes
  and images); `make test-integration` green.
- CI green on `main`: lint, types, unit, integration, e2e + axe, gitleaks, CodeQL, Trivy,
  `terraform fmt`/`validate` (all envs) and `plan` (staging).
- Manual deploy to staging succeeds; `https://<id>.cloudfront.net/` serves the page and `/health/ready`
  returns 200 against real RDS. No long-lived AWS keys in GitHub.
- Manual destroy of staging succeeds and leaves only the bootstrap resources; **idle cost and hourly
  cost while up are measured** and recorded in PROGRESS.
- Budgets alerts (5/10/20 USD) active, plus the Budget action at 20 USD and Cost Anomaly Detection if
  advanced features were activated (spend limits otherwise).
- `aws login` works for `dev` inside the devcontainer; no long-lived AWS keys exist anywhere.
- A test fails if any route does not declare its authorization.
- Migration 0001 runs `upgrade` and `downgrade` in CI.
- ADRs 0001–0010, threat model v1, bootstrap and staging runbooks committed.
- `main` ruleset active; release `v0.1.0` created manually.
- PROGRESS and CLAUDE.md updated; lint/types/tests reported with real results.

## Known risks carried into later phases
- The new AWS account experience is still rolling out to a limited set of customers, and its docs change.
- Activating advanced features is irreversible and removes the hard spend limit; cost control then depends
  on Budgets alerts, a Budget action and Cost Anomaly Detection, which react with some delay → keep staging
  destroyed when idle and check the cost after each demo.
- `aws login` picks credentials from the session chosen in the browser, not from the profile name → a wrong
  choice targets the wrong project; mitigated with `allowed_account_ids` and `aws sts get-caller-identity`.
- Free-tier limits of Grafana Cloud, Langfuse and WorkOS AuthKit change over time → verify on each
  vendor's pricing page when writing its ADR (Phase 1 observability, Phase 2 AuthKit).
- Public-subnet Fargate tasks have public IPs: inbound is closed by security groups, but outbound is open
  → threat model v1 must cover egress.
- SPEC §2 cost table: cached 3,000 tokens on Sonnet 5.5 cost $0.0006 (not $0.0003), and thinking tokens
  (cannot be disabled on Sonnet 5.5) are not counted. Measure in Phase 1.
- Native citations are incompatible with structured outputs → citation-validation ADR in Phase 1.
- Forced `tool_choice` is rejected on the 5.5 models → triage uses structured outputs.
- pgvector HNSW + RLS can return too few rows for small tenants → iterative scans (pgvector ≥ 0.8) or
  per-tenant partitioning; verify the RDS pgvector version.
- Postgres role model for RLS (app role, platform admin, workers, pooling with `SET LOCAL`) → ADR in Phase 2.
- End-customer widget identity mechanism undefined → Phase 2.
- PII redaction scope for tenant documents (legitimate business contact data) → Phase 1 policy.
- SSE behaviour through CloudFront + ALB → verify before Phase 1 streaming work (BACKLOG).
- TTFT p95 ≤ 2 s SLO is at risk with redaction + retrieval + adaptive thinking → measure from Phase 1.
