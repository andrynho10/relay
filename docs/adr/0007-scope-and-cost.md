# ADR-0007: Scope and cost: CV milestones and a USD 50/month budget

- **Status:** Accepted
- **Date:** 2026-10-14
- **Deciders:** Andrés Amaya Garcés

## Context

Relay is a portfolio project meant to show breadth (AI, cloud, CI/CD, security, observability) at a
minimum production standard. The owner has a cash budget of **USD 50/month until the end of 2026**
(about USD 125 in total, borrowed money) and wants something shown in a CV as early as possible. The
original plan kept staging and production running all the time, with Multi-AZ, WAF and a NAT Gateway:
hundreds of dollars a month. A first re-scope then cut features that cost time, not money.

Verified facts (AWS docs, 2026-10-13): new accounts get USD 100 in credits plus up to USD 100 more for
completing activities, and the paid plan only charges usage above the credit balance. Upgrading the plan
and activating advanced features have no fee of their own. Anthropic API usage is not covered by AWS
credits. Anthropic workspaces support monthly spend limits per workspace (Claude docs, 2026-10-14).

## Decision

1. **Finish something demonstrable, then scale** (SPEC §10.0). Priority 1 is five milestones in order:
   1) RAG you can demo, 2) secure multi-tenant SaaS, 3) agent with human approval, 4) measured economics,
   5) operations and portfolio. Each one ships a release, a README update, a short video and measured
   cost. Milestone 3 is the minimum target. Priority 2 is a list of independent extensions (E1–E8) with
   estimated costs, started only after the current milestone closes.
2. **Two applied environments.** Daily development is local. `dev` is used only for what cannot be
   emulated and is destroyed after use. `staging` is created on demand and destroyed after use and every
   night by a scheduled workflow. `prod` exists in Terraform and is validated in CI but never applied.
3. **Budget split** (cash, per month):

   | Item | Cap | Control |
   |---|---|---|
   | Anthropic `dev` workspace | USD 10 | Workspace spend limit |
   | Anthropic `ci` workspace (evals) | USD 10 | Workspace spend limit |
   | Anthropic `staging` workspace (demos) | USD 5 | Workspace spend limit |
   | AWS | USD 25 reserve | Credits first; Budgets on gross cost |

4. **AWS cost controls:** Budgets on gross cost with alerts at USD 10, 25 and 40; spend limits while on
   plain projects; after advanced features, a Budget action that applies a deny policy at USD 45, Cost
   Anomaly Detection, and a custom SCP that denies expensive services the project does not use.
5. **Cheap-by-design infrastructure:** no NAT Gateway (ADR-0010), AWS-managed KMS keys in staging,
   single-AZ RDS, default CloudFront domain.
6. Real cost is measured and published: idle per month, and per hour while staging runs.

## Alternatives considered

- **The original plan (always-on staging and production, Multi-AZ, WAF, NAT):** well above the budget.
- **Cutting scope to save money:** most cut items (supply-chain scanners, Stripe in test mode, SSO in
  WorkOS staging, MCP server, ZAP) cost nothing; cutting them lowered the ceiling without saving cash.
- **Applying production as a second environment:** doubles cost and demonstrates nothing staging does not.

## Consequences

- The minimum standard holds while cash stays within budget: most priority 2 items cost cents per hour
  on ephemeral staging or nothing at all.
- Staging is not available on demand for visitors; demos are recorded, and an open public demo is the
  last extension (E8) and only if the budget allows.
- Availability SLOs can only be measured during a planned seven-day window (E6), not continuously.
- Forgetting staging running costs at most about a day thanks to the nightly destroy.

## Verification and revisit triggers

- Monthly: compare real spend (AWS gross cost, Anthropic per workspace) against the table above and
  record it in `docs/PROGRESS.md`.
- Revisit if spend reaches the USD 40 alert in any month, or if the budget changes.
