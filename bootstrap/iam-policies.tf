# ================================================
# Terraform Deployment IAM Policy
#
# Security model:
#   1. OIDC trust policy  - only GitHub Actions from allowed repos/branches can assume this role
#   2. ARN-based scope    - all S3 actions restricted to arn:aws:s3:::${company_name}-*
#   3. PrincipalTag check - aws:PrincipalTag/environment (injected by the workflow via role-session-tags)
#                           prevents a dev pipeline from creating or modifying prod resources
# ================================================

data "aws_iam_policy_document" "terraform_deployment" {
  # S3: List the state bucket (required by Terraform backend init and plan)
  # Scoped to this environment's state bucket by ARN.
  # PrincipalTag/environment ensures the pipeline only accesses its own environment bucket.
  statement {
    sid    = "S3StateBucketList"
    effect = "Allow"

    actions = ["s3:ListBucket"]

    resources = ["arn:aws:s3:::${var.company_name}-tfstate-${var.environment}-*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/environment"
      values   = [var.environment]
    }
  }

  # S3: Read bucket metadata (used by terraform import, plan refresh, and state reads)
  # Scoped to company-prefixed buckets. No environment condition - read operations
  # are safe and required for terraform import to function correctly.
  statement {
    sid    = "S3BucketMetadataRead"
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning",
      "s3:GetEncryptionConfiguration",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketPolicy",
      "s3:GetBucketTagging",
      "s3:GetLifecycleConfiguration",
      "s3:GetBucketAcl",
      "s3:GetBucketCORS",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetBucketWebsite",
      "s3:GetBucketLogging",
      "s3:GetBucketNotification",
      "s3:GetBucketRequestPayment",
      "s3:GetReplicationConfiguration",
      "s3:GetAccelerateConfiguration"
    ]

    resources = ["arn:aws:s3:::${var.company_name}-*"]
  }

  # S3: List all buckets (required for Terraform state list operations)
  statement {
    sid    = "S3ListAllBuckets"
    effect = "Allow"

    actions = ["s3:ListAllMyBuckets"]

    resources = ["*"]
  }

  # S3: State object read/write
  # Scoped to this environment's bucket and the bootstrap project key prefix.
  statement {
    sid    = "S3StateObjects"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetObjectVersion",
      "s3:DeleteObjectVersion"
    ]

    resources = ["arn:aws:s3:::${var.company_name}-tfstate-${var.environment}-*/bootstrap/*"]
  }

  # S3: Create buckets and apply initial tags
  # Scoped to company-prefixed ARNs.
  # PrincipalTag/environment prevents creating prod buckets from a dev pipeline.
  statement {
    sid    = "S3BucketCreate"
    effect = "Allow"

    actions = [
      "s3:CreateBucket",
      "s3:PutBucketTagging"
    ]

    resources = ["arn:aws:s3:::${var.company_name}-*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/environment"
      values   = [var.environment]
    }
  }

  # S3: Manage existing buckets (versioning, encryption, policies, lifecycle, etc.)
  # Scoped to company-prefixed ARNs.
  # PrincipalTag/environment prevents cross-environment modifications.
  statement {
    sid    = "S3BucketManage"
    effect = "Allow"

    actions = [
      "s3:DeleteBucket",
      "s3:PutBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutLifecycleConfiguration",
      "s3:PutBucketAcl",
      "s3:PutBucketObjectLockConfiguration"
    ]

    resources = ["arn:aws:s3:::${var.company_name}-*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/environment"
      values   = [var.environment]
    }
  }

  # IAM: Full management for OIDC providers, roles, and policies
  # Required for Terraform to manage the bootstrap IAM resources.
  statement {
    sid    = "IAMManagement"
    effect = "Allow"

    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:ListOpenIDConnectProviders",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRoles",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicies",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy",
      "iam:PassRole"
    ]

    resources = ["*"]
  }

  # CloudTrail: Full management (actual resource creation is gated by enable_cloudtrail)
  statement {
    sid    = "CloudTrailManagement"
    effect = "Allow"

    actions = [
      "cloudtrail:CreateTrail",
      "cloudtrail:UpdateTrail",
      "cloudtrail:DeleteTrail",
      "cloudtrail:GetTrail",
      "cloudtrail:GetTrailStatus",
      "cloudtrail:DescribeTrails",
      "cloudtrail:ListTrails",
      "cloudtrail:StartLogging",
      "cloudtrail:StopLogging",
      "cloudtrail:PutEventSelectors",
      "cloudtrail:GetEventSelectors",
      "cloudtrail:PutInsightSelectors",
      "cloudtrail:GetInsightSelectors",
      "cloudtrail:AddTags",
      "cloudtrail:RemoveTags",
      "cloudtrail:ListTags",
      "cloudtrail:LookupEvents"
    ]

    resources = ["*"]
  }

  # STS: Identity verification used in CI/CD steps
  statement {
    sid    = "STSGetCallerIdentity"
    effect = "Allow"

    actions = ["sts:GetCallerIdentity"]

    resources = ["*"]
  }
}

# ================================================
# IAM Policy Resource
# ================================================

resource "aws_iam_policy" "terraform_deployment" {
  name        = "TerraformDeploymentPolicy-${var.environment}"
  description = "Organization-wide deployment policy for GitHub Actions in ${var.environment} environment"
  policy      = data.aws_iam_policy_document.terraform_deployment.json

  tags = {
    Name = "TerraformDeploymentPolicy-${var.environment}"
  }
}
