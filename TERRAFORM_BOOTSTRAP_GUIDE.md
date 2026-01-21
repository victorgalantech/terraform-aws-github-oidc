# Terraform Bootstrap Guide for GitHub Actions OIDC

This guide walks you through bootstrapping your **complete AWS CI/CD infrastructure** using Terraform with the `bootstrap-dev` user credentials. This single repository provides everything you need: OIDC authentication, IAM roles, S3 state backend, and DynamoDB locking - no external dependencies required.

**Repository:** `terraform-aws-oidc-bootstrap`

This approach automates the creation of OIDC providers, IAM roles, S3 state backend, and DynamoDB locking table, followed by seamless state migration to S3.

## 📋 Table of Contents

- [Why Terraform Bootstrap?](#why-terraform-bootstrap)
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Step 1: Configure Terraform Variables](#step-1-configure-terraform-variables)
- [Step 2: Initialize and Plan](#step-2-initialize-and-plan)
- [Step 3: Apply Bootstrap Infrastructure](#step-3-apply-bootstrap-infrastructure)
- [Step 4: Migrate State to S3 Backend](#step-4-migrate-state-to-s3-backend)
- [Step 5: Verify Setup](#step-5-verify-setup)
- [Step 6: Configure GitHub Variables](#step-6-configure-github-variables)
- [Step 7: Test GitHub Actions Workflow](#step-7-test-github-actions-workflow)
- [Multi-Environment Setup](#multi-environment-setup)
- [Troubleshooting](#troubleshooting)
- [State Migration Rollback](#state-migration-rollback)
- [Next Steps](#next-steps)
- [Best Practices](#best-practices)
- [Summary](#summary)

---

## Why Terraform Bootstrap?

### Benefits Over Manual Setup

- ✅ **Declarative Infrastructure** - All resources defined in code
- ✅ **Repeatable** - Deploy identical setups across dev/qa/prod
- ✅ **Version Controlled** - Track infrastructure changes in git
- ✅ **State Management** - Automatic state backend creation and migration
- ✅ **Idempotent** - Safe to run multiple times
- ✅ **Less Error-Prone** - Reduces manual configuration mistakes

### What Gets Created

This **single repository** creates your complete CI/CD foundation:

1. **AWS OIDC Identity Provider** - `token.actions.githubusercontent.com`
2. **IAM Role** - `github-actions-terraform-{environment}`
3. **IAM Policy** - `TerraformDeploymentPolicy-{environment}` (expandable for Lambda, ECS, Glue, Bedrock)
4. **S3 Bucket** - `{company}-tfstate-{environment}-{account-id}` (versioned, encrypted, lifecycle rules)
5. **DynamoDB Table** - `terraform-state-locks-{environment}` (point-in-time recovery, pay-per-request)
6. **CloudTrail** - `github-actions-oidc-{environment}` (optional, enabled by default for audit logging)
7. **Automated State Migration** - Seamless local → S3 transition

---

## Prerequisites

### 1. Required Tools

- **Terraform** >= 1.6.0 ([Install](https://developer.hashicorp.com/terraform/downloads))
- **AWS CLI** >= 2.x ([Install](https://aws.amazon.com/cli/))
- **Git** (for version control)

Verify installations:

```bash
terraform version
aws --version
git --version
```

### 2. Create bootstrap-dev User with Required Permissions

**IMPORTANT**: This is a prerequisite step that must be completed **before** setting up OIDC. You need to create an IAM user with specific permissions to manage OIDC providers and IAM roles.

### Why This User?

The `bootstrap-dev` user will have explicit permissions to:
- Create and manage OIDC identity providers
- Create and manage IAM roles and policies
- Create and manage CloudTrial
- Create and manage S3 for terraform state bucket
- Create and manage DynamoDB table for terrafomr state lock
- **Does NOT** include resource provisioning permissions (EC2, Lambda, Bedrock, etc.) or PassRole capability

### Create the User in AWS Console

**In EACH AWS account (dev, qa, prod):**

1. Go to **IAM Console** → **Users** → **Create user**
2. Set username: `bootstrap-dev`
3. Select **Attach policies directly**
4. Click **Create policy** (opens in new tab)

### Create the bootstrap-dev-policy

5. In the policy editor, select the **JSON** tab
6. Paste the following policy:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ManageOIDC",
            "Effect": "Allow",
            "Action": [
                "iam:CreateOpenIDConnectProvider",
                "iam:DeleteOpenIDConnectProvider",
                "iam:GetOpenIDConnectProvider",
                "iam:ListOpenIDConnectProviders",
                "iam:TagOpenIDConnectProvider",
                "iam:UpdateOpenIDConnectProviderThumbprint"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ManageRolesAndPolicies",
            "Effect": "Allow",
            "Action": [
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:UpdateRole",
                "iam:GetRole",
                "iam:ListRoles",
                "iam:TagRole",
                "iam:AttachRolePolicy",
                "iam:ListRolePolicies",
                "iam:DetachRolePolicy",
                "iam:PutRolePolicy",
                "iam:DeleteRolePolicy",
                "iam:CreatePolicy",
                "iam:DeletePolicy",
                "iam:GetPolicy",
                "iam:ListPolicies",
                "iam:ListAttachedRolePolicies",
                "iam:SimulatePrincipalPolicy",
                "iam:TagPolicy",
                "iam:ListInstanceProfilesForRole",
                "iam:GetPolicyVersion",
                "iam:ListPolicyVersions"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ManageCloudTrail",
            "Effect": "Allow",
            "Action": [
                "cloudtrail:CreateTrail",
                "cloudtrail:DeleteTrail",
                "cloudtrail:UpdateTrail",
                "cloudtrail:StartLogging",
                "cloudtrail:StopLogging",
                "cloudtrail:LookupEvents",
                "cloudtrail:DescribeTrails",
                "cloudtrail:GetTrailStatus",
                "cloudtrail:GetEventSelectors",
                "cloudtrail:PutEventSelectors",
                "cloudtrail:ListTags",
                "cloudtrail:AddTags",
                "cloudtrail:RemoveTags"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ManageS3ForTerraform",
            "Effect": "Allow",
            "Action": [
                "s3:CreateBucket",
                "s3:DeleteBucket",
                "s3:ListBucket",
                "s3:GetBucketLocation",
                "s3:GetBucketVersioning",
                "s3:PutBucketVersioning",
                "s3:GetBucketPublicAccessBlock",
                "s3:PutBucketPublicAccessBlock",
                "s3:GetBucketPolicy",
                "s3:PutBucketPolicy",
                "s3:DeleteBucketPolicy",
                "s3:GetBucketTagging",
                "s3:PutBucketTagging",
                "s3:GetLifecycleConfiguration",
                "s3:PutLifecycleConfiguration",
                "s3:GetBucketAcl",
                "s3:PutBucketAcl",
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListAllMyBuckets",
                "s3:GetBucketCORS",
                "s3:GetBucketWebsite",
                "s3:GetBucketAcl",
                "s3:GetAccelerateConfiguration",
                "s3:GetBucketRequestPayment",
                "s3:GetBucketLogging",
                "s3:GetReplicationConfiguration",
                "s3:GetEncryptionConfiguration",
                "s3:GetBucketObjectLockConfiguration",
                "s3:PutEncryptionConfiguration"
            ],
            "Resource": [
                "arn:aws:s3:::*-tfstate-*",
                "arn:aws:s3:::*-tfstate-*/*"
            ]
        },
        {
            "Sid": "ManageDynamoDBForTerraform",
            "Effect": "Allow",
            "Action": [
                "dynamodb:CreateTable",
                "dynamodb:DeleteTable",
                "dynamodb:DescribeTable",
                "dynamodb:DescribeContinuousBackups",
                "dynamodb:UpdateContinuousBackups",
                "dynamodb:ListTables",
                "dynamodb:ListTagsOfResource",
                "dynamodb:TagResource",
                "dynamodb:UntagResource",
                "dynamodb:UpdateTable",
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:DeleteItem",
                "dynamodb:DescribeTimeToLive"
            ],
            "Resource": "arn:aws:dynamodb:*:*:table/terraform-state-locks-*"
        },
        {
            "Sid": "ManageS3ForCloudTrail",
            "Effect": "Allow",
            "Action": [
                "s3:CreateBucket",
                "s3:PutBucketPolicy",
                "s3:GetBucketPolicy",
                "s3:PutBucketPublicAccessBlock",
                "s3:ListBucket",
                "s3:GetBucketTagging",
                "s3:GetBucketAcl",
                "s3:GetBucketCORS",
                "s3:GetBucketWebsite",
                "s3:GetBucketVersioning",
                "s3:GetAccelerateConfiguration",
                "s3:GetBucketRequestPayment",
                "s3:GetBucketLogging",
                "s3:GetReplicationConfiguration",
                "s3:GetEncryptionConfiguration",
                "s3:GetBucketObjectLockConfiguration",
                "s3:GetLifecycleConfiguration",
                "s3:DeleteBucket",
                "s3:PutBucketTagging",
                "s3:GetBucketPublicAccessBlock",
                "s3:PutLifecycleConfiguration",
                "s3:DeleteBucketPolicy"
            ],
            "Resource": "arn:aws:s3:::cloudtrail-logs-*"
        },
        {
            "Sid": "AuditCloudWatchLogs",
            "Effect": "Allow",
            "Action": [
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:FilterLogEvents",
                "logs:GetLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
```

7. Click **Next**
8. Set policy details:
   - **Policy name**: `bootstrap-dev-policy`
   - **Description**: `Grants permissions to manage OIDC identity providers, IAM roles and policies, CloudTrail logging, and policy simulation. Does not include resource provisioning permissions -EC2, Lambda, etc.- or PassRole capability.`
9. Click **Create policy**

### Attach Policy to User

10. Return to the **Create user** tab
11. Refresh the policy list and search for `bootstrap-dev-policy`
12. Select the checkbox next to `bootstrap-dev-policy`
13. Click **Next** → **Create user**

### Create Access Keys

14. Go to the newly created `bootstrap-dev` user
15. Navigate to **Security credentials** tab
16. Click **Create access key**
17. Select **Command Line Interface (CLI)**
18. Check the confirmation box
19. Click **Create access key**
20. **Save the credentials securely** - you'll need them for AWS CLI configuration

### Configure AWS CLI Profile

```bash
# Configure the bootstrap-dev profile
aws configure --profile bootstrap-dev
# Enter the Access Key ID and Secret Access Key from step 20 above
# Set default region (e.g., eu-west-1)
# Set output format (json)

# Verify the profile
aws sts get-caller-identity --profile bootstrap-dev
```

**Expected output:**
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXXXXX",
    "Account": "111111111111",
    "Arn": "arn:aws:iam::111111111111:user/bootstrap-dev"
}
```

**Repeat this process** for QA and Prod AWS accounts to create the bootstrap-qa and bootstrap-prod profiles. (Note: You may wish to verify Dev is fully working first):
- `bootstrap-qa` profile
- `bootstrap-prod` profile (or `bootstrap-prod`)

### 4. GitHub Information

You'll need:
- GitHub organization name
- GitHub repository name (or use `*` for all repos in org)
- Repository admin access (to set GitHub variables)

---

## Step 1: Configure Terraform Variables

Navigate to the bootstrap directory:

```bash
cd terraform-aws-github-oidc/bootstrap
```

### 2.1: Copy Example Variables File

```bash
cp terraform.tfvars.example terraform.tfvars
```

### 1.2: Edit terraform.tfvars

Open `terraform.tfvars` and configure your values:

```hcl
aws_region   = "eu-west-1"
environment  = "dev"
github_org   = "your-github-org"        # Replace with your GitHub organization
github_repo  = "*"                       # "*" for all repos, or specific repo name
company_name = "yourcompany"             # Replace with your company prefix

# Optional: Enable branch restrictions
enable_branch_restriction = false
allowed_branches         = ["main", "develop", "release/*"]

# Optional: CloudTrail for audit logging (recommended for compliance)
enable_cloudtrail        = true          # Set to false to disable CloudTrail
cloudtrail_retention_days = 90           # Days to retain CloudTrail logs

# Optional: Custom tags
tags = {
  ManagedBy = "Terraform"
  Purpose   = "GitHubActionsOIDC"
  Team      = "DevOps"
}
```

**Important Notes:**
- `github_repo = "*"` allows **all repositories** in your organization to use OIDC
- Use a specific repo name (e.g., `"my-app-repo"`) to restrict to a single repository
- `company_name` will be used as the S3 bucket prefix: `{company_name}-tfstate-{env}-{account-id}`
- `enable_cloudtrail = true` (default) creates CloudTrail for auditing OIDC authentications and AWS API calls
- CloudTrail logs are stored in a dedicated S3 bucket with automatic expiration after `cloudtrail_retention_days`

### 1.3: Validate Configuration

Review the configuration:

```bash
cat terraform.tfvars
```

Ensure:
- No placeholder values remain (e.g., `YOUR_GITHUB_ORG`)
- `github_org` matches your actual GitHub organization
- `company_name` follows AWS S3 naming rules (lowercase, no special characters except hyphens)

---

## Step 2: Initialize and Plan

### 2.1: Initialize Terraform

This downloads the required AWS provider and initializes the working directory:

```bash
terraform init
```

**Expected output:**
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.x.x...

Terraform has been successfully initialized!
```

### 2.2: Validate Configuration

Check for syntax errors:

```bash
terraform validate
```

**Expected output:**
```
Success! The configuration is valid.
```

### 2.3: Review Execution Plan

Generate and review the plan before applying:

```bash
terraform plan -out=tfplan
```

**What to verify in the plan:**
- **5-6 resources** to be created:
  - `aws_iam_openid_connect_provider.github_actions`
  - `aws_iam_role.github_actions`
  - `aws_iam_policy.terraform_deployment`
  - `aws_iam_role_policy_attachment.github_actions_terraform_deployment`
  - `aws_s3_bucket.terraform_state` (+ related resources)
  - `aws_dynamodb_table.terraform_locks`

Review the output carefully:
- Check role ARNs match your account
- Verify S3 bucket name follows convention
- Confirm trust policy includes correct GitHub org/repo

**Example output:**
```
Plan: 10 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + github_actions_role_arn = "arn:aws:iam::002332700133:role/github-actions-terraform-dev"
  + terraform_state_bucket  = "yourcompany-tfstate-dev-002332700133"
  + dynamodb_lock_table     = "terraform-state-locks-dev"
```

---

## Step 3: Apply Bootstrap Infrastructure

### 3.1: Apply the Plan

Execute the saved plan:

```bash
terraform apply tfplan
```

**OR** apply directly (will prompt for confirmation):

```bash
terraform apply
```

Type `yes` when prompted.

**Expected output:**
```
aws_iam_openid_connect_provider.github_actions: Creating...
aws_s3_bucket.terraform_state: Creating...
aws_dynamodb_table.terraform_locks: Creating...
...
Apply complete! Resources: 10 added, 0 changed, 0 destroyed.

Outputs:

github_actions_role_arn = "arn:aws:iam::002332700133:role/github-actions-terraform-dev"
terraform_state_bucket = "yourcompany-tfstate-dev-002332700133"
dynamodb_lock_table = "terraform-state-locks-dev"
...
```

### 3.2: Verify Resources Created

Check each resource:

```bash
# Verify OIDC provider
aws iam list-open-id-connect-providers --profile bootstrap-dev

# Verify IAM role
aws iam get-role --role-name github-actions-terraform-dev --profile bootstrap-dev

# Verify S3 bucket (Terraform state)
aws s3 ls --profile bootstrap-dev | grep tfstate

# Verify DynamoDB table
aws dynamodb describe-table --table-name terraform-state-locks-dev --profile bootstrap-dev

# Verify CloudTrail (if enabled)
aws cloudtrail get-trail-status --name github-actions-oidc-dev --profile bootstrap-dev

# Verify CloudTrail S3 bucket (if enabled)
aws s3 ls --profile bootstrap-dev | grep cloudtrail-logs
```

### 3.3: Save Outputs

Save the outputs for later use:

```bash
terraform output > bootstrap-outputs.txt
cat bootstrap-outputs.txt
```

**Important:** Keep the `github_actions_role_arn` value - you'll need it for GitHub Variables.

---

## Step 4: Migrate State to S3 Backend

Currently, the Terraform state is stored **locally** in `terraform.tfstate`. For production use, we need to migrate it to the S3 bucket we just created.

### 4.1: Generate Backend Configuration

Create `backend-config.hcl` with values from outputs:

```bash
# Get values from Terraform outputs
BUCKET=$(terraform output -raw terraform_state_bucket)
REGION=$(terraform output -raw aws_region)
DYNAMODB_TABLE=$(terraform output -raw dynamodb_lock_table)

# Create backend configuration file
cat > backend-config.hcl <<EOF
bucket         = "$BUCKET"
key            = "bootstrap/terraform.tfstate"
region         = "$REGION"
dynamodb_table = "$DYNAMODB_TABLE"
encrypt        = true
EOF

echo "Created backend-config.hcl:"
cat backend-config.hcl
```

**Example backend-config.hcl:**
```hcl
bucket         = "yourcompany-tfstate-dev-002332700133"
key            = "bootstrap/terraform.tfstate"
region         = "eu-west-1"
dynamodb_table = "terraform-state-locks-dev"
encrypt        = true
```

### 4.2: Update backend.tf

Edit `backend.tf` and uncomment the backend configuration:

```hcl
terraform {
  backend "s3" {
    # Configuration provided via backend-config.hcl
  }
}
```

### 4.3: Backup Local State

**CRITICAL:** Create a backup before migration:

```bash
cp terraform.tfstate terraform.tfstate.backup
cp terraform.tfstate.backup ../terraform.tfstate.backup.$(date +%Y%m%d-%H%M%S)
ls -la terraform.tfstate*
```

### 4.4: Reinitialize with Backend Migration

Run Terraform init with the `-migrate-state` flag:

```bash
terraform init -migrate-state -backend-config=backend-config.hcl
```

**Terraform will prompt:**
```
Initializing the backend...
Do you want to copy existing state to the new backend?
  Pre-existing state was found while migrating the previous "local" backend to the
  newly configured "s3" backend. No existing state was found in the newly
  configured "s3" backend. Do you want to copy this state to the new "s3"
  backend? Enter "yes" to copy and "no" to start with an empty state.

  Enter a value:
```

**Type `yes` and press Enter.**

**Expected output:**
```
Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.

Terraform has been successfully initialized!
```

### 4.5: Verify State in S3

Check that state was uploaded:

```bash
aws s3 ls s3://$BUCKET/bootstrap/ --profile bootstrap-dev
```

**Expected output:**
```
2026-01-07 20:00:00      12345 terraform.tfstate
```

### 4.6: Test State Lock

Verify DynamoDB locking works:

```bash
# Run a plan - this will acquire a lock
terraform plan

# Should complete successfully with no changes
```

---

## Step 5: Verify Setup

### 5.1: Verify Terraform State

```bash
# Check current state
terraform state list

# Should show all resources
```

**Expected output:**
```
aws_dynamodb_table.terraform_locks
aws_iam_openid_connect_provider.github_actions
aws_iam_policy.terraform_deployment
aws_iam_role.github_actions
aws_iam_role_policy_attachment.github_actions_terraform_deployment
aws_s3_bucket.terraform_state
...
```

### 5.2: Verify AWS Resources

```bash
# Check S3 bucket versioning
aws s3api get-bucket-versioning \
  --bucket $(terraform output -raw terraform_state_bucket) \
  --profile bootstrap-dev

# Check S3 encryption
aws s3api get-bucket-encryption \
  --bucket $(terraform output -raw terraform_state_bucket) \
  --profile bootstrap-dev

# Check DynamoDB point-in-time recovery
aws dynamodb describe-continuous-backups \
  --table-name $(terraform output -raw dynamodb_lock_table) \
  --profile bootstrap-dev
```

### 5.3: Test IAM Role Trust Policy

```bash
# Get role trust policy
aws iam get-role \
  --role-name github-actions-terraform-dev \
  --query 'Role.AssumeRolePolicyDocument' \
  --profile bootstrap-dev
```

Verify the trust policy includes:
- Federated principal: Your OIDC provider ARN
- Condition for `token.actions.githubusercontent.com:aud`
- Condition for `token.actions.githubusercontent.com:sub` with your GitHub org

### 5.4: Simulate IAM Policy

Test that GitHub Actions role can access S3 and DynamoDB:

```bash
# Simulate S3 access
aws iam simulate-principal-policy \
  --policy-source-arn $(terraform output -raw github_actions_role_arn) \
  --action-names s3:PutObject \
  --resource-arns "arn:aws:s3:::$(terraform output -raw terraform_state_bucket)/*" \
  --profile bootstrap-dev

# Should show: EvalDecision: allowed
```

### 5.5: Monitor CloudTrail Logs (If Enabled)

If you enabled CloudTrail, you can monitor OIDC authentication attempts:

```bash
# Query recent OIDC authentication events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 10 \
  --profile bootstrap-dev

# Check CloudTrail status
aws cloudtrail get-trail-status \
  --name github-actions-oidc-dev \
  --profile bootstrap-dev

# View CloudTrail configuration
aws cloudtrail get-trail \
  --name github-actions-oidc-dev \
  --profile bootstrap-dev
```

**What CloudTrail Logs:**
- ✅ Every OIDC `AssumeRoleWithWebIdentity` authentication attempt
- ✅ All S3 operations on the Terraform state bucket
- ✅ All DynamoDB operations on the state lock table
- ✅ Full audit trail with GitHub workflow details (repository, branch, commit SHA)

For detailed CloudTrail setup and querying, see [CLOUDTRAIL_SETUP.md](CLOUDTRAIL_SETUP.md).

---

## Step 6: Configure GitHub Variables

### 6.1: Get Role ARN

```bash
terraform output github_actions_role_arn
```

Copy the output (e.g., `arn:aws:iam::002332700133:role/github-actions-terraform-dev`)

### 6.2: Set GitHub Repository Variable

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **Variables** tab → **New repository variable**
4. Set:
   - **Name**: `AWS_ROLE_ARN_DEV`
   - **Value**: `arn:aws:iam::002332700133:role/github-actions-terraform-dev`
5. Click **Add variable**

### 6.3: Verify Variable

Go back to the Variables page and confirm `AWS_ROLE_ARN_DEV` is listed.

---

## Step 7: Test GitHub Actions Workflow

### 7.1: Create Test Workflow

Create `.github/workflows/test-oidc.yml`:

```yaml
name: Test OIDC Setup

on:
  push:
    branches:
      - main
      - develop
      - feature/*
  pull_request:
    branches:
      - main
      - develop

permissions:
  id-token: write
  contents: read

jobs:
  test-oidc:
    runs-on: ubuntu-latest
    if: github.event.pull_request.head.repo.full_name == github.repository || github.event_name == 'push'
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN_DEV }}
          role-session-name: GitHubActions-${{ github.run_id }}
          aws-region: eu-west-1
      
      - name: Verify AWS credentials
        run: |
          echo "Testing AWS OIDC authentication..."
          aws sts get-caller-identity
          echo "✅ Successfully authenticated with AWS using OIDC!"
      
      - name: Test S3 access
        run: |
          echo "Testing S3 access..."
          aws s3 ls s3://$(cat bootstrap/terraform.tfvars | grep company_name | cut -d'"' -f2)-tfstate-dev-* || echo "Bucket access test"
      
      - name: Test DynamoDB access
        run: |
          echo "Testing DynamoDB access..."
          aws dynamodb describe-table --table-name terraform-state-locks-dev || echo "Table access test"
```

### 7.2: Commit and Push

```bash
git add .github/workflows/test-oidc.yml
git add bootstrap/
git commit -m "Add Terraform bootstrap and OIDC test workflow"
git push origin main
```

### 7.3: Monitor Workflow

1. Go to **Actions** tab in GitHub
2. Click on the workflow run
3. Verify all steps complete successfully

**Expected output in "Verify AWS credentials" step:**
```json
{
    "UserId": "AROAXXXXXXXXXXXXXXXXX:GitHubActions-123456",
    "Account": "002332700133",
    "Arn": "arn:aws:sts::002332700133:assumed-role/github-actions-terraform-dev/GitHubActions-123456"
}
✅ Successfully authenticated with AWS using OIDC!
```

---

## Multi-Environment Setup

To set up QA and Prod environments:
1. Create the `bootstrap-qa` and `bootstrap-prod` users in their respective AWS accounts (see [Prerequisites](#2-create-bootstrap-dev-user-with-required-permissions))
2. Configure AWS CLI profiles for each environment
3. Follow Steps 1-7 with environment-specific configurations

### Create Environment-Specific tfvars

```bash
# QA environment
cd bootstrap
cp terraform.tfvars terraform-qa.tfvars

# Edit terraform-qa.tfvars
sed -i 's/environment = "dev"/environment = "qa"/' terraform-qa.tfvars
```

### Apply for Each Environment

```bash
# QA
terraform workspace new qa || terraform workspace select qa
terraform apply -var-file=terraform-qa.tfvars

# Prod
terraform workspace new prod || terraform workspace select prod
terraform apply -var-file=terraform-prod.tfvars
```

### Update GitHub Variables

Set additional variables:
- `AWS_ROLE_ARN_QA`
- `AWS_ROLE_ARN_PROD`

---

## Troubleshooting

### Issue: "Error creating S3 bucket: BucketAlreadyExists"

**Cause:** S3 bucket names must be globally unique.

**Solution:** Change `company_name` in `terraform.tfvars` to something more unique.

### Issue: "AccessDenied" when running terraform apply

**Cause:** bootstrap-dev user lacks required permissions.

**Solution:** Verify bootstrap-dev policy includes all required permissions (see [Prerequisites - Create bootstrap-dev User](#2-create-bootstrap-dev-user-with-required-permissions)).

### Issue: State migration fails

**Cause:** Backend configuration incorrect or S3 bucket not accessible.

**Solution:**
1. Verify backend-config.hcl values
2. Check S3 bucket exists: `aws s3 ls --profile bootstrap-dev`
3. Restore from backup: `cp terraform.tfstate.backup terraform.tfstate`

### Issue: "Error acquiring the state lock"

**Cause:** DynamoDB table lock not released properly.

**Solution:**
```bash
# View lock info
aws dynamodb get-item \
  --table-name terraform-state-locks-dev \
  --key '{"LockID": {"S": "yourcompany-tfstate-dev-002332700133/bootstrap/terraform.tfstate"}}' \
  --profile bootstrap-dev

# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

### Issue: GitHub Actions workflow fails with "Not authorized to perform sts:AssumeRoleWithWebIdentity"

**Cause:** Trust policy doesn't match repository or branch.

**Solution:**
1. Check trust policy: `terraform output` to see configuration
2. Verify GitHub org/repo name is correct
3. Ensure workflow is running from expected branch
4. Check `enable_branch_restriction` setting

---

## State Migration Rollback

If state migration fails or you need to rollback:

### Restore Local State

```bash
# Stop using S3 backend
rm -rf .terraform
cp terraform.tfstate.backup terraform.tfstate

# Re-initialize with local backend
terraform init
```

### Re-comment backend.tf

```hcl
# terraform {
#   backend "s3" {
#   }
# }
```

### Verify State

```bash
terraform state list
```

---

## Next Steps

### 1. Set Up CloudTrail (Recommended)
For audit logging and compliance:
- See [CLOUDTRAIL_SETUP.md](CLOUDTRAIL_SETUP.md)
- Monitor all OIDC authentications and API calls
- Meet regulatory requirements

### 2. Use This Bootstrap for Your Applications
Now that your foundation is set, deploy your applications:
- **Lambda functions** - Serverless applications
- **ECS/Fargate** - Containerized workloads  
- **Glue jobs** - Data pipelines
- **Bedrock** - AI/ML applications
- **Any Terraform-managed infrastructure**

All your application Terraform code can use the S3 backend and OIDC role created by this bootstrap.

### 3. Expand to QA and Prod
Replicate this setup to other environments:
- Follow [Multi-Environment Setup](#multi-environment-setup)
- Use environment-specific `terraform.tfvars` files
- Each environment gets its own S3 bucket and DynamoDB table

### 4. Set Up Branch Protection
Configure GitHub repository settings:
- Require pull request reviews before merging to main
- Enforce status checks (successful CI/CD)
- Require branches to be up to date before merging

### 5. Expand TerraformDeploymentPolicy
As your needs grow, add permissions to `bootstrap.tf`:
```hcl
# Add to data "aws_iam_policy_document" "terraform_deployment"
statement {
  sid    = "LambdaManagement"
  effect = "Allow"
  actions = [
    "lambda:CreateFunction",
    "lambda:UpdateFunctionCode",
    "lambda:UpdateFunctionConfiguration",
    # ... more Lambda permissions
  ]
  resources = ["*"]
}
```

---

## Best Practices

### 1. State File Security

- ✅ **Never commit** `terraform.tfstate` to git
- ✅ **Enable versioning** on S3 state bucket (already done by bootstrap)
- ✅ **Enable encryption** on S3 state bucket (already done by bootstrap)
- ✅ **Backup state files** before major changes

### 2. Access Control

- ✅ Use separate `bootstrap-dev` user per environment
- ✅ Rotate access keys regularly
- ✅ Enable MFA on bootstrap-dev user
- ✅ Use CloudTrail to monitor bootstrap-dev activities

### 3. Infrastructure Changes

- ✅ Always run `terraform plan` before `apply`
- ✅ Review plan output carefully
- ✅ Use feature branches for infrastructure changes
- ✅ Peer review Terraform code changes

### 4. State Locking

- ✅ Never disable state locking
- ✅ Use `terraform force-unlock` only as last resort
- ✅ Ensure DynamoDB table has point-in-time recovery enabled

---

## Summary

You've successfully:

- ✅ Created OIDC provider, IAM role, and deployment policy with Terraform
- ✅ Bootstrapped S3 backend and DynamoDB locking table
- ✅ Migrated Terraform state from local to S3
- ✅ Configured GitHub variables for OIDC authentication
- ✅ Tested GitHub Actions workflow with AWS access

**Your infrastructure is now fully automated and ready for CI/CD deployments! 🚀**

---

## References

- [Terraform S3 Backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [AWS OIDC with GitHub Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [OIDC_SETUP_GUIDE.md](OIDC_SETUP_GUIDE.md) - Manual setup alternative
- [AWS_IAM_POLICIES.md](AWS_IAM_POLICIES.md) - IAM policy reference
- [CLOUDTRAIL_SETUP.md](CLOUDTRAIL_SETUP.md) - Audit logging setup
