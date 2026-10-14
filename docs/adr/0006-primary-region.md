# ADR-0006: Primary AWS region: the one assigned to the projects

- **Status:** Proposed — accepted after step 3 of the T9 spike confirms the assigned region
- **Date:** 2026-10-14
- **Deciders:** Andrés Amaya Garcés

## Context

The kickoff chose `us-east-1` for its service catalogue. Checking the AWS docs on 2026-10-13 changed that:

- In the new account experience, AWS **assigns** each project a region from the country in the contact
  address: `us-east-2` (Ohio) for the Americas, `eu-north-1` for Europe, `ap-southeast-2` for Asia Pacific.
  It cannot be chosen, and changing the contact address does not change it.
- The managed SCP `RegionFloor` only allows regional resources in the assigned region; `us-east-1` is
  allowed only for global services (IAM, CloudFront, ACM, Budgets and similar).
- CloudFront features that create resources outside the assigned region, including WAF on CloudFront,
  are unavailable. Bedrock model invocation is allowed across regions.
- After activating advanced features (ADR-0008) other regions become available by editing the SCP.

Sources: AWS Account Management guide, "AWS Regions for your projects" and "Managed policies for your
organization", checked 2026-10-13.

## Decision

Use the region AWS assigns to the projects — `us-east-2` is expected — as the only region for regional
resources. Global services are used as they are. Terraform takes the region as a variable and never
hard-codes it.

## Alternatives considered

- **`us-east-1`:** only possible after activating advanced features and editing the managed SCP, for no
  benefit the project needs: staging uses the default CloudFront domain (no ACM certificate), and Bedrock
  can be invoked across regions.
- **A region closer to Latin America (`sa-east-1`):** higher prices and the same SCP constraint; latency to
  the model dominates the user-facing delay anyway.

## Consequences

- No SCP customisation is needed for regions; one fewer change to review and maintain.
- Bedrock embedding models must be checked for availability in, or cross-region invocation from, the
  assigned region before the embeddings ADR in Phase 1.
- Prices differ slightly from `us-east-1`; cost estimates use the assigned region's prices.

## Verification and revisit triggers

- T9 spike step 3: read the assigned region in AWS Settings → Project → Additional info, then accept.
- Revisit if a required service is unavailable in the assigned region, or a customer requires residency.
