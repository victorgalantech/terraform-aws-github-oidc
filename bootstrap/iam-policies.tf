# ================================================
# Terraform Deployment Policy Document
# ================================================

data "aws_iam_policy_document" "terraform_deployment" {
  # S3 State Bucket Management - Read-only for all projects
  statement {
    sid    = "S3StateBucketReadOnly"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning",
      "s3:GetBucketEncryption",
      "s3:GetEncryptionConfiguration",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketPolicy",
      "s3:GetBucketTagging",
      "s3:GetLifecycleConfiguration",
      "s3:GetBucketAcl",
      "s3:GetBucketCORS",
      "s3:GetBucketObjectLockConfiguration"
    ]

    resources = var.enable_abac ? ["*"] : ["arn:aws:s3:::${var.company_name}-tfstate-*"]

    # ABAC: Match environment tag
    dynamic "condition" {
      for_each = var.enable_abac ? [1] : []
      content {
        test     = "StringEquals"
        variable = "s3:ResourceTag/environment"
        values   = ["$${aws:PrincipalTag/environment}"]
      }
    }

    # ABAC: Ensure resources tagged
    dynamic "condition" {
      for_each = var.enable_abac ? [1] : []
      content {
        test     = "StringEquals"
        variable = "s3:ResourceTag/resource-type"
        values   = ["state-backend", "audit-logs"]
      }
    }
  }

  # S3 Bucket Creation - org-wide
  # Note: s3:CreateBucket does not support aws:RequestTag conditions - tags are applied
  # via a separate PutBucketTagging call after creation.
  # Security is enforced by the OIDC trust policy (only GitHub Actions can assume this role)
  # and by the environment principal tag (prevents cross-environment bucket creation).
  dynamic "statement" {
    for_each = var.enable_abac ? [1] : []
    content {
      sid    = "S3BucketCreation"
      effect = "Allow"

      actions = [
        "s3:CreateBucket",
        "s3:PutBucketTagging"
      ]

      resources = ["*"]

      # ABAC: Caller must be operating in the correct environment
      condition {
        test     = "StringEquals"
        variable = "aws:PrincipalTag/environment"
        values   = [var.environment]
      }
    }
  }

  # S3 Bucket Management - org-wide
  # Resource tag conditions (s3:ResourceTag/*) are intentionally NOT used here.
  # They cause a chicken-and-egg deadlock: the bucket must be tagged to be managed,
  # but management is needed before/during tagging (e.g. destroy/recreate cycles).
  # Security relies on:
  #   1. OIDC trust policy - only GitHub Actions from allowed repos can assume this role
  #   2. aws:PrincipalTag/environment - caller's session tag, always present, prevents cross-env ops
  dynamic "statement" {
    for_each = var.enable_abac ? [1] : []
    content {
      sid    = "S3BucketManagement"
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

      resources = ["*"]

      # ABAC: Principal tag (caller's session) - no chicken-and-egg since it's on the caller not the resource
      condition {
        test     = "StringEquals"
        variable = "aws:PrincipalTag/environment"
        values   = [var.environment]
      }
    }
  }

  # S3 State Objects - ListBucket operation (for Terraform init/backend config)
  statement {
    sid    = "S3StateListBucket"
    effect = "Allow"

    actions = [
      "s3:ListBucket"
    ]

    resources = var.enable_abac ? ["*"] : ["arn:aws:s3:::${var.company_name}-tfstate-*"]

    # ABAC: Match environment tag
    dynamic "condition" {
      for_each = var.enable_abac ? [1] : []
      content {
        test     = "StringEquals"
        variable = "s3:ResourceTag/environment"
        values   = ["$${aws:PrincipalTag/environment}"]
      }
    }

    # ABAC: Ensure resources tagged
    dynamic "condition" {
      for_each = var.enable_abac ? [1] : []
      content {
        test     = "StringEquals"
        variable = "s3:ResourceTag/resource-type"
        values   = ["state-backend", "audit-logs"]
      }
    }

    # ABAC: Restrict ListBucket to only list own projectID prefix
    dynamic "condition" {
      for_each = var.enable_abac ? [1] : []
      content {
        test     = "StringLike"
        variable = "s3:prefix"
        values   = [
          "$${aws:PrincipalTag/Project}/*",
          "$${aws:PrincipalTag/Project}"
        ]
      }
    }
  }

  # S3 State Objects - Project-isolated by key pattern (CRITICAL SECURITY)
  statement {
    sid    = "S3StateObjectsProjectIsolated"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetObjectVersion",
      "s3:DeleteObjectVersion"
    ]

    resources = var.enable_abac ? [
      "arn:aws:s3:::${var.company_name}-tfstate-${var.environment}-*/$${aws:PrincipalTag/Project}/*"
    ] : [
      "arn:aws:s3:::${var.company_name}-tfstate-*/*"
    ]
  }

  # Allow listing operations (no tag restrictions needed)
  statement {
    sid    = "AllowListOperations"
    effect = "Allow"
    
    actions = [
      "s3:ListAllMyBuckets"
    ]
    
    resources = ["*"]
  }

  # S3 Read permissions for ALL buckets (including CloudTrail)
  statement {
    sid    = "S3ReadAllBuckets"
    effect = "Allow"
    
    actions = [
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning",
      "s3:GetBucketEncryption",
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
    
    resources = ["arn:aws:s3:::*"]
  }

  # IAM Management - Full permissions for bootstrap project
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

  # CloudTrail Management
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

  # STS permissions for identity verification
  statement {
    sid    = "STSPermissions"
    effect = "Allow"
    
    actions = [
      "sts:GetCallerIdentity"
    ]
    
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
