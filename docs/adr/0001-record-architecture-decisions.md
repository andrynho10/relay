# ADR-0001: Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-10-14
- **Deciders:** Andrés Amaya Garcés

## Context

Relay is built by one person with an AI coding agent, across many sessions. Decisions about providers,
data isolation, cost and infrastructure must survive between sessions, be defensible in an interview,
and not be silently contradicted by later work. CLAUDE.md already requires that an accepted ADR is not
contradicted without proposing a new one.

## Decision

- Architecture decisions are recorded as ADRs in `docs/adr/`, numbered sequentially (`NNNN-kebab-title.md`),
  using a lightweight MADR-style structure ([`template.md`](template.md)): context, decision, alternatives,
  consequences, verification.
- Statuses: **Proposed** (may still be edited), **Accepted** (immutable), **Superseded by ADR-NNNN**,
  **Rejected**. An accepted ADR is never rewritten; a change of mind is a new ADR that supersedes it, and
  the old one only gets its status line updated.
- An ADR is written when we choose or reject a provider or service, change a security or isolation
  boundary, make a cost trade-off that shapes the architecture, or deviate from `docs/SPEC.md`.
- Facts that can change (prices, quotas, service availability) are written with their source and the date
  they were checked.
- Each ADR is reviewed in a pull request like any other change. [`README.md`](README.md) keeps the index.

## Alternatives considered

- **Decisions only in the SPEC:** the SPEC describes the target state, not why alternatives were rejected,
  and it is edited freely, so the history of a decision is lost.
- **Decisions in PR descriptions or commit messages:** hard to find later and scattered across history.
- **A wiki outside the repo:** drifts from the code and is not reviewed with it.

## Consequences

- Small overhead per decision; in exchange, every non-obvious choice has a written rationale.
- Proposed ADRs make open questions explicit instead of leaving them implicit in code.

## Verification and revisit triggers

- At each phase close, check that new providers or boundaries introduced in the phase have an ADR.
