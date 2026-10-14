# Relay

**Relay is a multi-tenant B2B support copilot.** Each company uploads its documentation; Relay answers
its customers with retrieval-augmented generation and cited sources, triages tickets, and proposes
actions (refunds, plan changes, escalations) that the backend validates and a human approves when
they are sensitive.

It is a portfolio project built to a production standard: measured AI quality, tenant isolation,
security controls, observability and unit economics, all documented and tested.

> **Status:** Phase 0 — Foundations, in progress. See [`docs/PROGRESS.md`](docs/PROGRESS.md).

## Demo

_Coming with milestone 1: a short video of the staging demo and its measured cost._

## Milestones

The project is built as a sequence of demonstrable milestones; each one ships a release, a demo and
its real cost ([SPEC §10.0](docs/SPEC.md)).

| # | Milestone | What it shows | Status |
|---|---|---|---|
| 1 | RAG you can demo | Streaming answers with citations, cost and latency per answer, LLM traces, evals gating CI, keyless deploys to AWS | In progress |
| 2 | Secure multi-tenant SaaS | SSO-ready login, RBAC, Postgres Row-Level Security including vector search, cross-tenant test suite | Planned |
| 3 | Agent with human approval | Structured triage, a sensitive tool with policy and limits, approval inbox, red-team suite in CI | Planned |
| 4 | Measured economics | Model routing driven by evals, prompt caching, cost per resolution | Planned |
| 5 | Operations | Alert with runbook, tested restore, accessibility audit, case study and postmortem | Planned |

## Architecture

_Diagram coming with milestone 1._ In short: Next.js and FastAPI on ECS Fargate behind CloudFront;
PostgreSQL with pgvector and Row-Level Security; asynchronous ingestion through S3 and SQS workers;
every model call goes through an `LLMGateway` that records tokens, cost, latency and tenant.
Details in [SPEC §5](docs/SPEC.md) and the [architecture decision records](docs/adr/).

## Tech stack

- **Backend:** Python 3.12+, FastAPI, Pydantic v2, SQLAlchemy 2, Alembic
- **Frontend:** Next.js (App Router), TypeScript strict, Tailwind; Playwright + axe
- **Data:** PostgreSQL 16+ with pgvector and RLS, Valkey, S3
- **AI:** Claude API (Haiku, Sonnet, Opus) behind `LLMGateway`; PII redaction with Microsoft Presidio
- **Infrastructure:** AWS, Terraform, GitHub Actions with OIDC (no long-lived keys)
- **Observability:** OpenTelemetry, Langfuse

## Engineering practices

- Every external input is untrusted: users, uploaded documents, model output, webhooks.
- Tenant isolation is enforced in the database (RLS), not only in application code.
- Changes to prompts, models or retrieval must pass the eval suite without regression.
- Every change lands through a reviewed pull request with CI as a gate; `main` is protected.
- Decisions are recorded as ADRs; the threat model is updated every phase.

## Running locally

_Instructions land with the devcontainer and Docker Compose setup (Phase 0)._ Daily development is
fully local; only what cannot be emulated uses a temporary AWS `dev` environment.

## Cost

The project runs on a small, explicit budget ([SPEC §11](docs/SPEC.md)): staging is ephemeral and
destroyed every night, and real costs (idle per month, and per hour while running) are reported here
at each milestone.

## Documentation

- [Specification](docs/SPEC.md) — scope, architecture, security, milestones
- [Phase plans](docs/plans/) and [progress](docs/PROGRESS.md)
- [Architecture decision records](docs/adr/)

## License

[MIT](LICENSE) © 2026 Andrés Amaya Garcés
