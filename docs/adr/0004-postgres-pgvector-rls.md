# ADR-0004: PostgreSQL + pgvector + Row-Level Security as the single database

- **Status:** Accepted
- **Date:** 2026-10-14
- **Deciders:** Andrés Amaya Garcés

## Context

Tenant isolation is Relay's central security property: no tenant may read another tenant's data,
including through semantic search over embedded documents (SPEC §7). Relay stores relational data
(tenants, users, tickets, approvals, audit log) and vectors for retrieval. Every extra data store is
another place where isolation must be implemented and tested.

## Decision

- Use one **PostgreSQL 16+** database (RDS in AWS) with the **pgvector** extension for embeddings.
- Enable **Row-Level Security** on every table that holds tenant data, including the vector table.
- The current tenant is set per transaction with `SET LOCAL` from the authenticated token, never from the
  request body. The application connects with a role that does not have `BYPASSRLS`; migrations run with a
  separate owner role.
- From milestone 1, every tenant-scoped table carries a `tenant_id` column, so milestone 2 adds policies
  without reshaping the schema.

## Alternatives considered

- **A dedicated vector database** (managed vector service or OpenSearch): a second isolation boundary to
  build and test, another provider or cluster to pay for, and data synchronisation between stores.
- **Schema-per-tenant or database-per-tenant:** strong isolation, but migrations, pooling and operations
  grow with the number of tenants.
- **Filtering by `tenant_id` in application code only:** one forgotten `WHERE` clause is a data leak; RLS
  makes the database enforce the rule.

## Consequences

- Vector search inherits the same isolation as the rest of the data and is covered by the same tests.
- **Recall risk:** an approximate index (HNSW) returns a global top-k that RLS filters afterwards, so a
  small tenant can get too few results. Mitigations: pgvector iterative index scans (0.8 or later) or
  per-tenant partitioning. The pgvector version offered by RDS in our region must be verified in Phase 1.
- Connection pooling must keep the tenant setting scoped to the transaction; poolers that pin or reuse
  session state need care.
- One database is a shared resource for relational and vector workloads; sizing is revisited with load.
- The full Postgres role model (platform admin, workers, aggregated metrics) gets its own ADR in Phase 2.

## Verification and revisit triggers

- A cross-tenant test suite, including vector search, runs in CI and must never read another tenant's rows
  (SPEC §10, milestone 2).
- Revisit if retrieval evals show RLS-filtered recall below the quality bar despite the mitigations.
