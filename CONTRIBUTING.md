# Contributing Guide

## Table of Contents

- [Development prerequisites](#development-prerequisites)
- [Local quality checks](#local-quality-checks)
- [Branch strategy](#branch-strategy)
- [Commit conventions](#commit-conventions)
- [Pull request process](#pull-request-process)
- [Updating pinned GitHub Actions](#updating-pinned-github-actions)

---

## Development prerequisites

| Tool | Version | Install |
|---|---|---|
| Terraform | ≥ 1.10.0 | [tfenv](https://github.com/tfutils/tfenv) or [official](https://developer.hashicorp.com/terraform/install) |
| Terragrunt | ≥ 0.67.0 | `brew install terragrunt` or [releases](https://github.com/gruntwork-io/terragrunt/releases) |
| TFLint | latest | `brew install tflint` |
| pre-commit | latest | `pip install pre-commit && pre-commit install` |
| AWS CLI | v2 | [official](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| Make | any | included on Linux/macOS; `choco install make` on Windows |

---

## Local quality checks

All checks run without AWS credentials — mock provider is used for tests.

```bash
# Format all modules
make fmt

# Validate syntax
make validate

# Run unit tests (mock provider — no real AWS account)
make test

# Lint with AWS ruleset
make lint

# Run all checks at once (same as CI validate job)
make fmt-check validate test lint
```

Pre-commit hooks run automatically on `git commit`. To run them manually:

```bash
pre-commit run --all-files
```

---

## Branch strategy

| Branch | Maps to environment | Who deploys |
|---|---|---|
| `feature/*`, `fix/*` | `dev` | Author, via PR |
| `develop` | `dev` | Auto on merge |
| `release/*` | `qa` | Auto on merge |
| `main` | `prod` | Auto on merge (requires PR approval) |

---

## Commit conventions

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>

[optional body]

[optional footer]
```

**Types:**

- `feat` — new feature or resource
- `fix` — bug fix
- `security` — security improvement (IAM policy, KMS, S3 policy)
- `refactor` — code restructure without behaviour change
- `docs` — documentation only
- `ci` — CI/CD changes
- `test` — adding or updating tests
- `chore` — dependency bumps, SHA pin updates

**Scopes:** `iam`, `s3`, `kms`, `cloudtrail`, `oidc`, `workflow`, `terragrunt`, `docs`

**Examples:**

```
feat(cloudtrail): add dedicated CMK with CloudTrail key policy
security(iam): scope deployment policy to environment-specific ARNs
fix(s3): separate access log bucket to prevent self-logging
ci(workflow): pin all Actions to commit SHA for supply-chain security
docs: add incident runbook for state bucket corruption
```

---

## Pull request process

1. **Branch** off `develop` (or `main` for hotfixes).
2. **Run checks locally** — `make fmt-check validate test lint` — before pushing.
3. **Open a PR** against `develop` (or `main`). Fill in the PR template:
   - What changed and why
   - Security impact (IAM, KMS, S3 policy changes must be explicitly noted)
   - How to test / validate
4. **CI must pass** — all 3 jobs (validate, security-scan, plan) must be green.
5. **One approval required** for `develop`; **two approvals** for `main`.
6. **Squash and merge** — one commit per PR on the target branch.
7. For `main` PRs, the reviewer must manually trigger the `apply` action via `workflow_dispatch` after merge if not using auto-apply.

### What goes in a PR vs a hotfix

| Change type | Branch | Target |
|---|---|---|
| New resource / module | `feature/<name>` | `develop` |
| IAM / KMS / S3 policy change | `security/<name>` | `develop` |
| Documentation only | `docs/<name>` | `develop` or `main` |
| Breaking prod incident fix | `hotfix/<name>` | `main` directly |

---

## Updating pinned GitHub Actions

All Actions in `.github/workflows/terraform-deploy.yml` are pinned to a commit SHA. When upgrading:

1. Find the target version tag on the Action's GitHub releases page.
2. Get the SHA of that tag:
   ```bash
   gh api repos/{owner}/{repo}/git/ref/tags/{tag} --jq '.object.sha'
   # For annotated tags (most Actions use these), resolve one more level:
   gh api repos/{owner}/{repo}/git/tags/{sha} --jq '.object.sha'
   ```
3. Update the workflow — replace the old SHA with the new one and update the version comment.
4. Open a PR with type `ci(workflow): bump <action> to <version>`.

**Current pinned versions:**

| Action | Version | SHA |
|---|---|---|
| `actions/checkout` | v4.2.2 | `11bd71901bbe5b1630ceea73d27597364c9af683` |
| `actions/upload-artifact` | v4.6.0 | `65c4c4a1e8c8b35b6f9a1bcbb2cf4f56e98afe6c` |
| `actions/download-artifact` | v4.1.8 | `fa0a91b85d4f404e444306234c7afecc4b494e94` |
| `actions/github-script` | v7.0.1 | `60a0d83039c74a4aee543508d2ffcb1c3799cdea` |
| `hashicorp/setup-terraform` | v3.1.1 | `651471c36a6092792c552e8b1bef71e592b462d8` |
| `aws-actions/configure-aws-credentials` | v4.0.2 | `e3dd6a429d7300a6a4c196c26e071d42e0343502` |
| `terraform-linters/setup-tflint` | v4.0.0 | `19a52fbac37dacb22a09518e4ef6ee234f2d4987` |
| `bridgecrewio/checkov-action` | v3.2.1 | `fdc39ed8de1c0e9d68305ca19c0ba95c3601695` |
| `aquasecurity/tfsec-action` | v1.0.3 | `b466648d6e39e7c75324f25d83891162a721f2d6` |
