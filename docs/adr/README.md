# Architecture decision records

Decisions are recorded as ADRs following [ADR-0001](0001-record-architecture-decisions.md).
Copy [`template.md`](template.md) to start a new one.

| # | Title | Status |
|---|---|---|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0002](0002-aws-as-the-single-cloud.md) | AWS as the single cloud provider | Accepted |
| [0003](0003-no-self-hosted-llm.md) | No self-hosted LLM; Claude API behind `LLMGateway` | Accepted |
| [0004](0004-postgres-pgvector-rls.md) | PostgreSQL + pgvector + Row-Level Security as the single database | Accepted |
| [0005](0005-ecs-fargate-for-compute.md) | ECS Fargate for compute | Accepted |
| [0006](0006-primary-region.md) | Primary AWS region: the one assigned to the projects | Proposed |
| [0007](0007-scope-and-cost.md) | Scope and cost: CV milestones and a USD 50/month budget | Accepted |
| [0008](0008-aws-account-model.md) | AWS account model and access matrix | Proposed |
| [0009](0009-devcontainer.md) | Reproducible development environment: devcontainer | Proposed |
