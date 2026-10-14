# ADR-0005: ECS Fargate for compute

- **Status:** Accepted
- **Date:** 2026-10-14
- **Deciders:** Andrés Amaya Garcés

## Context

Relay runs three stateless workloads: the FastAPI API (with long-lived streaming responses over SSE), the
Next.js web app, and Python workers that consume SQS and load heavyweight libraries (PII recognizers,
document parsers). One person operates it, staging is created and destroyed on demand (ADR-0007), and the
AWS account uses the new account experience, where some services are unavailable (ADR-0008).

## Decision

Run all three workloads as containers on **Amazon ECS with Fargate**, behind an Application Load
Balancer. Images are built in CI, tagged with the commit SHA and version, and never deployed as `latest`.
Services scale on CPU (API, web) and queue depth (workers).

## Alternatives considered

- **EKS:** a fixed hourly fee for the control plane and Kubernetes operations, with no benefit at this
  scale; creating and destroying a cluster is also slow, which works against an ephemeral staging.
- **AWS Lambda:** long SSE streams, cold starts and large dependencies (language models for PII detection)
  fit poorly; workers would need a different packaging from the API.
- **AWS App Runner:** simpler, but listed as not supported in the new account experience (checked
  2026-10-13 in the AWS Account Management guide).
- **EC2 instances:** operating-system patching and capacity management for one person.

## Consequences

- No servers to patch; the same container image runs locally (Docker Compose) and in AWS.
- Fargate tasks need network access to ECR, CloudWatch Logs and Secrets Manager; without a NAT Gateway
  this shapes the network design (ADR-0010, written in T10).
- Per-task pricing makes idle environments cost money, which is why staging is ephemeral.

## Verification and revisit triggers

- The walking skeleton (Phase 0) deploys API and web to Fargate through Terraform and GitHub Actions.
- Revisit if load tests (priority 2, E6) show Fargate cost or scaling limits that another option avoids.
