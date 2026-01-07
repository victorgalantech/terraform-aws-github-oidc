# GitHub Actions OIDC Setup Guide for AWS

This guide walks you through setting up OpenID Connect (OIDC) authentication between GitHub Actions and AWS for secure, keyless deployments.

## 📋 Table of Contents

- [Why OIDC?](#why-oidc)
- [Prerequisites](#prerequisites)
- [Setup Overview](#setup-overview)
- [Step 1: Create dev-admin User with Required Permissions](#step-1-create-dev-admin-user-with-required-permissions)
- [Step 2: Create OIDC Identity Provider in AWS](#step-2-create-oidc-identity-provider-in-aws)
- [Step 3: Create IAM Roles per Environment](#step-3-create-iam-roles-per-environment)
- [Step 4: Configure GitHub Variables](#step-4-configure-github-variables)
- [Step 5: Test the Setup](#step-5-test-the-setup)
- [Troubleshooting](#troubleshooting)

---

## Why OIDC?

### Security Benefits

| Feature | IAM User Access Keys | OIDC (Recommended) |
|---------|---------------------|---------------------|
| **Credential Storage** | Long-lived keys in GitHub Secrets | No credentials stored |
| **Credential Rotation** | Manual, error-prone | Automatic per workflow run |
| **Credential Scope** | Broad, permanent access | Temporary, scoped to workflow |
| **Compromise Risk** | High (if leaked, valid indefinitely) | Low (temporary tokens) |
| **Audit Trail** | Limited to IAM user | Full CloudTrail with session details |

### How OIDC Works

```
┌─────────────────┐                    ┌──────────────────┐
│  GitHub Actions │                    │   AWS IAM OIDC   │
│    Workflow     │                    │     Provider     │
└────────┬────────┘                    └────────┬─────────┘
         │                                      │
         │  1. Request OIDC token              │
         ├──────────────────────────────────────>
         │                                      │
         │  2. Return signed JWT token         │
         <──────────────────────────────────────┤
         │                                      │
         │  3. Exchange token for AWS creds    │
         ├──────────────────────────────────────>
         │                                      │
         │  4. Validate token & return         │
         │     temporary AWS credentials       │
         <──────────────────────────────────────┤
         │                                      │
         │  5. Use credentials (valid ~1 hour) │
         │                                      │
```

---

## Prerequisites

- AWS account(s) for each environment (dev, qa, prod)
- GitHub repository with Actions enabled
- AWS CLI configured with admin access
- Permissions to create IAM identity providers and roles

---

## Setup Overview

**Multi-Account Architecture**: Perform steps 1-5 in **each AWS account** (dev, qa, prod).

1. **Create dev-admin User** with required IAM permissions (once per account)
2. **Create OIDC Identity Provider** in AWS (once per account)
3. **Create IAM Role** with trust policy for GitHub Actions (per environment/account)
4. **Configure GitHub Variables** with Role ARNs
5. **Test** the workflow

---

## Step 1: Create dev-admin User with Required Permissions

**IMPORTANT**: This is a prerequisite step that must be completed **before** setting up OIDC. You need to create an IAM user with specific permissions to manage OIDC providers and IAM roles.

### Why This User?

The `dev-admin` user will have explicit permissions to:
- Create and manage OIDC identity providers
- Create and manage IAM roles and policies
- **Does NOT** include resource provisioning permissions (EC2, S3, etc.) or PassRole capability

### Create the User in AWS Console

**In EACH AWS account (dev, qa, prod):**

1. Go to **IAM Console** → **Users** → **Create user**
2. Set username: `dev-admin`
3. Select **Attach policies directly**
4. Click **Create policy** (opens in new tab)

### Create the dev-admin-policy

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
                "iam:DetachRolePolicy",
                "iam:PutRolePolicy",
                "iam:DeleteRolePolicy",
                "iam:CreatePolicy",
                "iam:DeletePolicy",
                "iam:GetPolicy",
                "iam:ListPolicies",
                "iam:ListAttachedRolePolicies"
            ],
            "Resource": "*"
        }
    ]
}
```

7. Click **Next**
8. Set policy details:
   - **Policy name**: `dev-admin-policy`
   - **Description**: `Grants explicit permissions to create, update, and delete OIDC identity providers and associated IAM roles. Does not include resource provisioning permissions (EC2, S3, etc.) or PassRole`
9. Click **Create policy**

### Attach Policy to User

10. Return to the **Create user** tab
11. Refresh the policy list and search for `dev-admin-policy`
12. Select the checkbox next to `dev-admin-policy`
13. Click **Next** → **Create user**

### Create Access Keys

14. Go to the newly created `dev-admin` user
15. Navigate to **Security credentials** tab
16. Click **Create access key**
17. Select **Command Line Interface (CLI)**
18. Check the confirmation box
19. Click **Create access key**
20. **Save the credentials securely** - you'll need them for AWS CLI configuration

### Configure AWS CLI Profile

```bash
# Configure the dev-admin profile
aws configure --profile dev-admin
# Enter the Access Key ID and Secret Access Key from Step 20
# Set default region (e.g., eu-west-1)
# Set output format (json)

# Verify the profile
aws sts get-caller-identity --profile dev-admin
```

**Expected output:**
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXXXXX",
    "Account": "111111111111",
    "Arn": "arn:aws:iam::111111111111:user/dev-admin"
}
```

**Repeat this process** for QA and Prod AWS accounts to create the qa-admin and prod-admin profiles. (Note: You may wish to verify Dev is fully working first):
- `qa-admin` profile
- `prod-admin` profile (or `pro-admin`)

---

## Step 2: Create OIDC Identity Provider in AWS

### Option 1: AWS Console

**In EACH AWS account (dev, qa, prod):**

1. Go to **IAM Console** → **Identity providers** → **Add provider**
2. Select **OpenID Connect**
3. Configure provider:
   - **Provider URL**: `https://token.actions.githubusercontent.com`
   - **Audience**: `sts.amazonaws.com`
4. Click **Add provider**

### Option 2: AWS CLI

Run this command **in each AWS account**:

```bash
# Dev Account
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 1c58a3a8518e8759bf075b76b750d4f2df264fcd

# Repeat for QA and Prod accounts (switch AWS profile/credentials)
```

**Verify creation:**

```bash
aws iam list-open-id-connect-providers
```

Expected output:
```json
{
    "OpenIDConnectProviderList": [
        {
            "Arn": "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
        }
    ]
}
```

---

## Step 3: Create IAM Roles per Environment

You need **one IAM role per environment**, each in its respective AWS account.

### Role Naming Convention

- **Dev**: `github-actions-terraform-dev` (in dev AWS account)
- **QA**: `github-actions-terraform-qa` (in qa AWS account)
- **Prod**: `github-actions-terraform-pro` (in prod AWS account)

### Step 3.1: Create Trust Policy

Create a file `github-trust-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_ORG/*"
        }
      }
    }
  ]
}
```

**Important to do in the next step (3.2)**: 
- Replace `YOUR_ACCOUNT_ID` with your AWS account ID (different for dev/qa/prod)
- Replace `YOUR_GITHUB_ORG` with your actual GitHub org and repository name
- Example: `acmetechorg`

### Step 3.2: Create IAM Role (Dev Example)

```bash
# Switch to Dev AWS Account
export AWS_PROFILE=dev-admin

# Get your AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

# Update trust policy with your account ID and GitHub repo
sed "s/YOUR_ACCOUNT_ID/$ACCOUNT_ID/g" github-trust-policy.json > github-trust-policy-dev.json
GITHUB_ORG=<YOUR_GITHUB_ORG> #Replace for your actual github org
echo "Github org: $GITHUB_ORG"
sed -i "s|YOUR_GITHUB_ORG|$GITHUB_ORG|g" github-trust-policy-dev.json 

# Create the role
aws iam create-role \
  --role-name github-actions-terraform-dev \
  --assume-role-policy-document file://github-trust-policy-dev.json \
  --description "GitHub Actions OIDC role for build and develop the infrastructures (dev)"

# Get the role ARN
aws iam get-role \
  --role-name github-actions-terraform-dev \
  --query 'Role.Arn' \
  --output text
```

**Save the role ARN** - you'll need it for GitHub Variables in Step 4:
```
arn:aws:iam::111111111111:role/github-actions-terraform-dev
```

### Step 3.3: Create Permissions Policy

This policy will be used for **all deployments** in your organization (Lambdas, Fargate, Glue, Bedrock, etc.). You can add more permissions as needed in the future. (Optional)

Create a file `terraform-deployment-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3BucketManagement",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:GetBucketEncryption",
        "s3:PutBucketEncryption",
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
        "s3:PutBucketAcl"
      ],
      "Resource": "arn:aws:s3:::<COMPANY_NAME>-tfstate-*"
    },
    {
      "Sid": "S3ObjectManagement",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetObjectVersion",
        "s3:DeleteObjectVersion"
      ],
      "Resource": "arn:aws:s3:::<COMPANY_NAME>-tfstate-*/*"
    },
    {
      "Sid": "DynamoDBTableManagement",
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
        "dynamodb:UpdateTable"
      ],
      "Resource": "arn:aws:dynamodb:<REGION>:*:table/terraform-state-locks"
    },
    {
      "Sid": "DynamoDBStateLocking",
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:DeleteItem",
        "dynamodb:DescribeTable"
      ],
      "Resource": "arn:aws:dynamodb:<REGION>:*:table/terraform-state-locks"
    }
  ]
}
```

**Update placeholders:**
- Replace `<COMPANY_NAME>` with your bucket name prefix
- Replace `<REGION>` with your AWS region (e.g., `eu-west-1`)

**Attach policy to role:**

```bash
# Create managed policy
aws iam create-policy \
  --policy-name TerraformDeploymentPolicy \
  --policy-document file://terraform-deployment-policy.json \
  --description "Organization-wide deployment policy for Terraform, Lambdas, Fargate, Glue, Bedrock, and other AWS services"

# Get policy ARN
POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='TerraformDeploymentPolicy'].Arn" --output text)
echo "Policy ARN: $POLICY_ARN"

# Attach policy to role
aws iam attach-role-policy \
  --role-name github-actions-terraform-dev \
  --policy-arn $POLICY_ARN
```

**Note:** This policy currently includes S3 and DynamoDB permissions. You will expand it in the future to include permissions for Lambda, Fargate, Glue, Bedrock, and other services as your infrastructure grows.

### Verify Your Setup (Dev Account)

At this point, you have completed the setup for the **Dev environment**. Let's verify everything is in place:

```bash
# 1. Verify OIDC Provider exists
aws iam list-open-id-connect-providers --profile dev-admin

# 2. Verify IAM Role exists
aws iam get-role --role-name github-actions-terraform-dev --profile dev-admin

# 3. Verify attached policies
aws iam list-attached-role-policies --role-name github-actions-terraform-dev --profile dev-admin
```

### 📋 Recap: What You've Created in Dev Account

By completing Steps 1-3, you have created the following AWS resources in your **Dev account**:

| Resource Type | Resource Name | Purpose |
|--------------|---------------|---------|
| **IAM User** | `dev-admin` | Administrative user with permissions to manage OIDC and IAM roles |
| **IAM Policy** | `dev-admin-policy` | Grants `dev-admin` user permissions to create/manage OIDC providers and IAM roles |
| **OIDC Identity Provider** | `token.actions.githubusercontent.com` | Establishes trust between AWS and GitHub Actions |
| **IAM Role** | `github-actions-terraform-dev` | Role that GitHub Actions will assume via OIDC |
| **IAM Policy** | `TerraformDeploymentPolicy` | Organization-wide deployment policy for managing AWS resources (currently S3 and DynamoDB, expandable for Lambdas, Fargate, Glue, Bedrock, etc.) |

**Architecture Overview:**

```
GitHub Actions Workflow
         ↓
   [OIDC Token Request]
         ↓
AWS OIDC Provider (token.actions.githubusercontent.com)
         ↓
   [Validates Token]
         ↓
IAM Role: github-actions-terraform-dev
         ↓
   [Temporary Credentials]
         ↓
Permissions: TerraformDeploymentPolicy
         ↓
Access to: S3, DynamoDB, Lambda, Fargate, Glue, Bedrock, etc.
```

**What This Setup Enables:**
- ✅ **Keyless authentication** from GitHub Actions to AWS
- ✅ **Temporary credentials** (valid ~1 hour per workflow run)
- ✅ **Scoped permissions** limited to S3 and DynamoDB operations
- ✅ **Environment isolation** (dev resources only)
- ✅ **No long-lived secrets** stored in GitHub

**Important Notes:**
- This setup is **per AWS account** (currently completed for Dev)
- The `dev-admin` user credentials should be stored securely (AWS CLI profile)
- The GitHub Actions role ARN will be needed in Step 4 for GitHub Variables
- You must repeat this process for QA and Prod accounts with their respective naming conventions

### Step 3.4: Test with Dev Environment Before Proceeding

**⚠️ IMPORTANT**: Before creating OIDC setup in QA and Prod accounts, you should:

1. **Complete Steps 4-5** with your Dev environment
2. **Test the GitHub Actions CI/CD pipeline** thoroughly with the dev setup
3. **Verify all workflows execute successfully** using OIDC authentication
4. **Confirm deployments work as expected** in the dev environment

Once you have validated the dev setup works correctly, you can proceed to create the same infrastructure in QA and Prod accounts.

### Step 3.5: Repeat for QA and Prod (After Testing Dev)

**After successful testing in dev**, replicate the setup for QA and Prod environments:

**Switch to QA account:**
```bash
export AWS_PROFILE=qa-admin

# Repeat the following:
# - Step 2: Create OIDC Provider
# - Step 3.2: Create IAM Role (github-actions-terraform-qa)
# - Step 3.3: Create and attach TerraformDeploymentPolicy
```

**Switch to Prod account:**
```bash
export AWS_PROFILE=prod-admin

# Repeat the following:
# - Step 2: Create OIDC Provider
# - Step 3.2: Create IAM Role (github-actions-terraform-pro)
# - Step 3.3: Create and attach TerraformDeploymentPolicy
```

**Best Practice:** Test each environment sequentially (Dev → QA → Prod) before moving to the next.

---

## Step 4: Configure GitHub Variables

### Navigate to GitHub Settings

Go to: **Your Repository** → **Settings** → **Secrets and variables** → **Actions** → **Variables**

### Add Repository Variables

Click **New repository variable** and add the following:

| Variable Name | Example Value | Description |
|--------------|---------------|-------------|
| `AWS_ROLE_ARN_DEV` | `arn:aws:iam::111111111111:role/github-actions-terraform-dev` | Dev OIDC role ARN |
| `AWS_ROLE_ARN_QA` | `arn:aws:iam::222222222222:role/github-actions-terraform-qa` | QA OIDC role ARN |
| `AWS_ROLE_ARN_PROD` | `arn:aws:iam::333333333333:role/github-actions-terraform-pro` | Prod OIDC role ARN |

**Important Notes:**
- Use the **actual role ARNs** from Step 3.2 (each will have a different AWS account ID)
- Store these as **Variables**, not Secrets (they're not sensitive)
- Account IDs in ARNs should match your separate AWS accounts

---

## Step 5: Test the Setup

### 5.1: Update Your Workflow

Ensure your workflow has:

```yaml
permissions:
  id-token: write   # Required for OIDC
  contents: read    # Required to checkout code

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN_DEV }}
          role-session-name: GitHubActions-${{ github.run_id }}
          aws-region: eu-west-1
```

### 5.2: Create Test Branch

```bash
git checkout -b test/oidc-setup
git push origin test/oidc-setup
```

### 5.3: Monitor Workflow

1. Go to **Actions** tab in GitHub
2. Find the running workflow
3. Check "Configure AWS credentials (OIDC)" step

**Expected output:**
```
Assuming role with OIDC
Role ARN: arn:aws:iam::111111111111:role/github-actions-terraform-dev
Requesting temporary credentials
Credentials will expire at: 2024-12-26T14:30:00Z
✓ Successfully configured AWS credentials
```

### 5.4: Verify AWS Access

Check subsequent steps for successful AWS API calls.

### 5.5: Check CloudTrail (Optional)

In AWS CloudTrail, look for AssumeRoleWithWebIdentity events:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 5
```

You should see events with:
- **Principal**: `token.actions.githubusercontent.com`
- **SessionName**: `GitHubActions-<run-id>`

---

## Troubleshooting

### Error: "Not authorized to perform: sts:AssumeRoleWithWebIdentity"

**Cause**: Trust policy is misconfigured or OIDC provider not found.

**Solution**:
1. Verify OIDC provider exists:
   ```bash
   aws iam list-open-id-connect-providers
   ```
2. Check trust policy has correct repository:
   ```bash
   aws iam get-role --role-name github-actions-terraform-dev --query 'Role.AssumeRolePolicyDocument'
   ```
3. Ensure `token.actions.githubusercontent.com:sub` matches your repo pattern

### Error: "No OpenIDConnect provider found"

**Cause**: OIDC provider not created in AWS account.

**Solution**: Complete Step 2 in the correct AWS account.

### Error: "Access Denied" during Terraform operations

**Cause**: IAM role lacks necessary permissions.

**Solution**:
1. Check attached policies:
   ```bash
   aws iam list-attached-role-policies --role-name github-actions-terraform-dev
   ```
2. Verify policy has S3 and DynamoDB permissions (Step 3.3)
3. Check resource ARNs match your bucket/table names

### Error: "Token audience validation failed"

**Cause**: OIDC provider audience is incorrect.

**Solution**: Ensure audience is set to `sts.amazonaws.com`:
```bash
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com
```

---

## Security Best Practices

### 1. Restrict Trust Policy

**Limit to specific branches:**
```json
"Condition": {
  "StringEquals": {
    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
  },
  "StringLike": {
    "token.actions.githubusercontent.com:sub": [
      "repo:mycompany/terraform-states-s3-bucket:ref:refs/heads/main",
      "repo:mycompany/terraform-states-s3-bucket:ref:refs/heads/develop"
    ]
  }
}
```

**Limit to specific environments:**
```json
"StringEquals": {
  "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
  "token.actions.githubusercontent.com:environment": "production"
}
```

### 2. Use Separate Roles per Environment

- ✅ One role per AWS account (dev, qa, prod)
- ✅ Each role scoped to its environment's resources
- ✅ Prevents cross-environment access

### 3. Monitor Role Usage

Enable CloudTrail logging and set up CloudWatch alarms for:
- Failed AssumeRole attempts
- Unusual API call patterns
- Access from unexpected sources

### 4. Regular Audits

```bash
# Review role usage
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=github-actions-terraform-dev \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --max-results 100
```

---

## References

- [AWS IAM OIDC Identity Providers](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials)

---

## Summary

**Setup Time:** ~15 minutes per AWS account (one-time)

**Benefits:**
- ✅ No long-lived credentials
- ✅ Automatic credential rotation
- ✅ Better audit trail
- ✅ Reduced security risk
- ✅ Compliance-friendly

🎉 Your GitHub Actions workflow now uses secure, keyless OIDC authentication!
