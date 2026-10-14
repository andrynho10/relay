# ADR-0002: AWS as the single cloud provider

- **Status:** Accepted
- **Date:** 2026-10-14
- **Deciders:** Andrés Amaya Garcés

## Context

Relay needs managed containers, PostgreSQL with pgvector, a durable queue with a dead-letter queue,
object storage, a CDN, secrets and key management, and identity federation for CI. It is a portfolio
project, so the cloud choice should also match what B2B startups and the job market use most. SPEC §5
sets the principle "one cloud used well instead of many used badly".

## Decision

Use **AWS** as the only cloud provider: ECS Fargate, RDS PostgreSQL, SQS, S3, CloudFront, Secrets
Manager, KMS, CloudWatch, Budgets, and Bedrock for embeddings (SPEC §6). Infrastructure is defined in
Terraform. Third-party SaaS is used only where AWS has no reasonable equivalent or the SPEC names it
(Claude API, WorkOS, Stripe, Langfuse, Grafana Cloud), each with its own ADR when adopted.

## Alternatives considered

- **Google Cloud:** Cloud Run would make the compute layer simpler, but AWS has wider adoption among the
  startups and roles this project targets, and the SPEC's security controls (IAM per service, OIDC from
  GitHub, KMS) are equally available on AWS.
- **Azure:** no advantage for this stack and less common in the target market.
- **Multi-cloud:** doubles the identity, networking and security surface for no benefit at this scale.

## Consequences

- One IAM model, one billing account and one set of security controls to learn and document.
- IAM is powerful but verbose; least-privilege policies take effort and must be reviewed.
- The account is created in AWS's new account experience, which constrains regions and some services
  until advanced features are activated (ADR-0006, ADR-0008).

## Verification and revisit triggers

- Revisit if a required service is unavailable or too expensive on AWS for the budget in ADR-0007.
