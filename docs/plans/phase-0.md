# Phase 0 — Foundations

Status: **approved 2026-10-13** · Spec: `docs/SPEC.md` §10 (Phase 0), §13 · Target release: `v0.1.0`

## Goal
Monorepo, git workflow, local environment, CI with security scans, Terraform skeleton, initial ADRs,
threat model v1, and a **walking skeleton** (`/health` + minimal page) deployed to staging on AWS via
Terraform and GitHub Actions with OIDC.

## Decisions taken at kickoff (to be formalised as ADRs in T2)
| Topic | Decision |
|---|---|
| AWS region | `us-east-1` (ADR-0006) |
| Local dev environment | Devcontainer; "clean machine" = Docker + VS Code + Dev Containers only (ADR-0009) |
| Budget | ~$50/month; staging is ephemeral (`terraform destroy` when idle); AWS Budgets alert at $40 |
| Repo visibility | Public (free rulesets, CodeQL, secret-scanning push protection) |
| Observability | OTel Collector (ADOT) → Grafana Cloud free tier (ADR-0007) |
| LLM tracing | Langfuse Cloud, only redacted text is sent (ADR-0008) |
| Embeddings | Bedrock Cohere Embed multilingual as *Proposed* default; final decision in Phase 1 with evals (ADR-0010) |
| Name / domain | "Relay" is a codename; staging uses the default `*.cloudfront.net` domain (ADR-0011) |

## Prerequisites (owner: Andrés)
- [ ] AWS Organizations with `dev`, `staging`, `prod` accounts + IAM Identity Center; AWS Budgets alert.
- [ ] SSH commit-signing key configured in git and GitHub (the `main` ruleset requires signed commits).
- [ ] Run `infra/bootstrap` once in `staging` (and `dev`) with admin credentials, following the runbook.
- [ ] GitHub: apply the `main` ruleset, enable secret scanning + push protection, create the `staging` environment.
- [ ] Install the VS Code Dev Containers extension.

## Tasks (one branch + PR each)
- [ ] **T0 `docs/phase-0-plan`** — this file; update `docs/PROGRESS.md`.
- [ ] **T1 `chore/repo-hygiene`** — `.gitignore`, `.dockerignore`, `.gitattributes` (force LF), `.editorconfig`,
      `.env.example`, `.pre-commit-config.yaml` (gitleaks, ruff, ruff-format, prettier, terraform fmt, check-yaml),
      README template.
- [ ] **T2 `docs/initial-adrs`** — ADRs 0001–0011 (MADR). ADR-0009 is reviewed with Andrés before T2b.
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
      eslint, tsc, Playwright + axe, image builds); `security.yml` (gitleaks, CodeQL, Semgrep, Trivy fs + image,
      Checkov, CycloneDX SBOM); Dependabot; CODEOWNERS; PR template. Actions pinned by SHA.
- [ ] **T8 `ci/release-please`** — `bump-minor-pre-major`, CHANGELOG, images tagged with SHA + version.
- [ ] **T9 `feat/infra-bootstrap`** — S3 state bucket (`use_lockfile`), GitHub OIDC provider, deploy role per
      account; runbook `docs/runbooks/bootstrap-account.md`.
- [ ] **T10 `feat/infra-staging-skeleton`** — VPC (2 AZ), ECR, ECS Fargate (api, web), ALB, CloudFront,
      RDS Postgres single-AZ `t4g.micro` with KMS, Secrets Manager for DB credentials, CloudWatch logs;
      `terraform.yml` posts `plan` on every PR. WAF and Multi-AZ are Phase 5. Stop and ask if this grows.
- [ ] **T11 `ci/deploy-staging`** — merge to `main` → build → push to ECR → `terraform apply` (staging, OIDC)
      → smoke test `/health/ready` and the page through CloudFront.
- [ ] **T12 `docs/threat-model-v1`** — STRIDE per component and data flow, with planned mitigations per phase.
- [ ] **T13 `chore/phase-0-close`** — `main` ruleset JSON (existing checks only), update CLAUDE.md
      (real commands, devcontainer; `make evals`/`make redteam` marked "from Phase 1/3"), PROGRESS, BACKLOG review,
      release `v0.1.0`.

## Definition of done
- `make dev` and `make check` work from a clean clone inside the devcontainer (verified after wiping volumes
  and images); `make test-integration` green.
- CI green on `main`: lint, types, unit, integration, e2e + axe, gitleaks, CodeQL, Semgrep, Trivy, Checkov,
  SBOM, `terraform validate`/`plan`.
- A push to `main` deploys only to staging; `https://<id>.cloudfront.net/` serves the page and
  `/health/ready` returns 200 against real RDS. No long-lived AWS keys in GitHub.
- A test fails if any route does not declare its authorization.
- Migration 0001 runs `upgrade` and `downgrade` in CI.
- ADRs 0001–0011, threat model v1, bootstrap and deploy runbooks committed.
- `main` ruleset active; release `v0.1.0` with CHANGELOG.
- Staging `terraform destroy` tested and documented.
- PROGRESS and CLAUDE.md updated; lint/types/tests reported with real results.

## Known risks carried into later phases
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
