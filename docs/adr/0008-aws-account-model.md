# ADR-0008: AWS account model and access matrix

- **Status:** Proposed — accepted (or revised) with the results of the T9 spike
- **Date:** 2026-10-14
- **Deciders:** Andrés Amaya Garcés

## Context

The account was created in AWS's new account experience. Facts checked on 2026-10-13 in the AWS Account
Management guide ("Sign up for AWS (new)", "Activate advanced AWS features", "Managed policies for your
organization", "Connect an AI coding tool") and the AWS CLI guide (`aws login`):

- Resources live in **projects**. Each project contains an AWS account, and the projects form an
  organization that AWS manages. A paid-plan project can have a monthly **spend limit**; a project that
  reaches it is paused.
- AWS manages the SCPs and RCPs. The paid-plan SCP statement `DenyIAMRestrictedActions` denies
  `iam:*Provider*`, so **the GitHub OIDC identity provider cannot be created**. `iam:CreateRole` is
  allowed outside `role/managed/*`. The RCP denies `sts:*` and other actions to principals outside the
  organization.
- GuardDuty, Security Hub, IAM Identity Center and Organizations are not available until advanced
  features are activated.
- **Activating advanced features** makes us the administrators of the organization, turns projects into
  member accounts, makes all services and regions available, and lets us edit SCPs. It is
  **irreversible**, removes all spend limits (paused projects are reactivated) and does not allow new ones.
- `aws login` (AWS CLI 2.32.0 or later) issues temporary credentials from a browser sign-in: valid for 12
  hours and renewable for 90 days, with a `--remote` mode for machines without a browser. The project used
  is the session chosen on the "Choose AWS sessions" page, not the profile name.

## Decision

1. Two projects, **`dev`** and **`staging`**, on the paid plan. There is no `prod` project.
2. **Access matrix:**

   | Environment | Who | How |
   |---|---|---|
   | `dev` | Andrés and the agent | Temporary credentials only (`aws login`) from the devcontainer |
   | `staging` | GitHub Actions only | OIDC; the deploy role trusts only `repo:andrynho10/relay:environment:staging` |
   | `prod` | Nobody | No project and no credentials; exists only in Terraform |

3. **Single exception:** `infra/bootstrap` (state bucket, OIDC provider, deploy role, Secrets Manager
   secret for the staging Anthropic key) runs once per project with Andrés's own credentials. It is
   documented in the bootstrap runbook and in the threat model.
4. **Advanced features are activated** when the T9 spike confirms the OIDC block, because keyless
   deployment from CI is a core requirement (SPEC §13). They are also activated if another person needs
   access through Identity Center, or if GuardDuty or Security Hub become necessary.
5. After activation, cost control moves from spend limits to Budgets, a Budget action and a custom cost
   SCP (ADR-0007).
6. Terraform providers pin `allowed_account_ids` per environment, and every manual `aws` or `terraform`
   command is preceded by `aws sts get-caller-identity`.
7. The AWS Agent Toolkit setup script is not used: the `aws login` profile is configured by hand.

## Alternatives considered

- **Long-lived IAM access keys in GitHub secrets:** technically allowed (`iam:CreateAccessKey` is not
  denied) but forbidden by the SPEC and the weakest option to show in a portfolio.
- **An OIDC provider in a separate classic account that assumes a role in the project:** blocked by the
  project RCP, which denies `sts:*` to principals outside the organization.
- **GitHub Actions runners hosted in CodeBuild inside the project:** keyless and keeps the spend limit,
  but adds a service outside SPEC §6, depends on CodeConnections being allowed by the SCP, and with a
  public repository exposes the deploy role to workflows triggered from forks unless filtered carefully.
- **Manual deploys from the devcontainer with `aws login`:** keeps the hard spend limit but drops
  continuous delivery, a central item of the project.
- **Activating advanced features immediately:** gives up the spend limit before confirming it is needed.

## Consequences

- Keyless CI/CD with a narrowly scoped trust policy, the pattern reviewers expect.
- Losing the hard spend limit is the main cost; it is mitigated by Budgets (which react with some
  delay), a Budget action, a cost SCP and a nightly destroy of staging.
- The bootstrap exception is a privileged human action and is treated as a risk in the threat model.
- Choosing the wrong browser session with `aws login` can target the wrong project; the account pinning
  in Terraform and the identity check make that fail early.

## Verification and revisit triggers

- T9 spike: (1) temporary `dev` credentials work inside the devcontainer without long-lived keys — if not,
  stop and ask; (2) `aws iam create-open-id-connect-provider` is denied as expected; (3) assigned region;
  (4) after activation, the Budget action and the cost SCP are in place and `aws login` still works.
- Revisit if AWS changes the managed SCPs, or if the project gains a second contributor.
