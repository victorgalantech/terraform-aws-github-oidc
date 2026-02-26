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

    # ABAC: Ensure resource type is state-backend
    dynamic "condition" {
      for_each = var.enable_abac ? [1] : []
      content {
        test     = "StringEquals"
        variable = "s3:ResourceTag/resource-type"
        values   = ["state-backend"]
      }
    }
  }

  # S3 State Bucket Management - Destructive operations ONLY for bootstrap
  dynamic "statement" {
    for_each = var.enable_abac ? [1] : []
    content {
      sid    = "S3StateBucketManagementBootstrapOnly"
      effect = "Allow"

      actions = [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:PutBucketVersioning",
        "s3:PutBucketEncryption",
        "s3:PutBucketPublicAccessBlock",
        "s3:PutBucketPolicy",
        "s3:DeleteBucketPolicy",
        "s3:PutBucketTagging",
        "s3:PutLifecycleConfiguration",
        "s3:PutBucketAcl"
      ]

      resources = ["*"]

      # SECURITY: Only bootstrap project can create/delete buckets
      condition {
        test     = "StringEquals"
        variable = "aws:PrincipalTag/projectID"
        values   = ["bootstrap"]
      }

      # ABAC: Match environment tag
      condition {
        test     = "StringEquals"
        variable = "s3:ResourceTag/environment"
        values   = ["$${aws:PrincipalTag/environment}"]
      }

      # ABAC: Ensure resource type is state-backend
      condition {
        test     = "StringEquals"
        variable = "s3:ResourceTag/resource-type"
        values   = ["state-backend"]
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

    # ABAC: Ensure resource type is state-backend
    dynamic "condition" {
      for_each = var.enable_abac ? [1] : []
      content {
        test     = "StringEquals"
        variable = "s3:ResourceTag/resource-type"
        values   = ["state-backend"]
      }
    }

    # ABAC: Restrict ListBucket to only list own projectID prefix
    dynamic "condition" {
      for_each = var.enable_abac ? [1] : []
      content {
        test     = "StringLike"
        variable = "s3:prefix"
        values   = [
          "$${aws:PrincipalTag/projectID}/*",
          "$${aws:PrincipalTag/projectID}"
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
      "arn:aws:s3:::${var.company_name}-tfstate-${var.environment}-*/$${aws:PrincipalTag/projectID}/*"
    ] : [
      "arn:aws:s3:::${var.company_name}-tfstate-*/*"
    ]
  }

  # DynamoDB Lock Table Management - Read-only for all projects
  statement {
    sid    = "DynamoDBLockTableReadOnly"
    effect = "Allow"

    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:ListTables",
      "dynamodb:ListTagsOfResource"
    ]

    resources = var.enable_abac ? ["*"] : [
      "arn:aws:dynamodb:${local.region}:${local.account_id}:table/terraform-state-locks-${var.environment}"
    ]

    # ABAC: Match environment tag
    dynamic "condition" {
      for_each = var.enable_abac ? [1] : []
      content {
        test     = "StringEquals"
        variable = "dynamodb:ResourceTag/environment"
        values   = ["$${aws:PrincipalTag/environment}"]
      }
    }

    # ABAC: Ensure resource type is state-backend
    dynamic "condition" {
      for_each = var.enable_abac ? [1] : []
      content {
        test     = "StringEquals"
        variable = "dynamodb:ResourceTag/resource-type"
        values   = ["state-backend"]
      }
    }
  }

  # DynamoDB Lock Table Management - Destructive operations ONLY for bootstrap
  dynamic "statement" {
    for_each = var.enable_abac ? [1] : []
    content {
      sid    = "DynamoDBLockTableManagementBootstrapOnly"
      effect = "Allow"

      actions = [
        "dynamodb:CreateTable",
        "dynamodb:DeleteTable",
        "dynamodb:UpdateContinuousBackups",
        "dynamodb:TagResource",
        "dynamodb:UntagResource",
        "dynamodb:UpdateTable"
      ]

      resources = ["*"]

      # SECURITY: Only bootstrap project can create/delete tables
      condition {
        test     = "StringEquals"
        variable = "aws:PrincipalTag/projectID"
        values   = ["bootstrap"]
      }

      # ABAC: Match environment tag
      condition {
        test     = "StringEquals"
        variable = "dynamodb:ResourceTag/environment"
        values   = ["$${aws:PrincipalTag/environment}"]
      }

      # ABAC: Ensure resource type is state-backend
      condition {
        test     = "StringEquals"
        variable = "dynamodb:ResourceTag/resource-type"
        values   = ["state-backend"]
      }
    }
  }

  # DynamoDB State Locking - Project-isolated by LockID prefix (CRITICAL SECURITY)
  statement {
    sid    = "DynamoDBStateLockingProjectIsolated"
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
      "dynamodb:DescribeTimeToLive"
    ]

    resources = var.enable_abac ? ["*"] : [
      "arn:aws:dynamodb:${local.region}:${local.account_id}:table/terraform-state-locks-${var.environment}"
    ]

    # ABAC: Match environment tag
    dynamic "condition" {
      for_each = var.enable_abac ? [1] : []
      content {
        test     = "StringEquals"
        variable = "dynamodb:ResourceTag/environment"
        values   = ["$${aws:PrincipalTag/environment}"]
      }
    }

    # ABAC: Ensure resource type is state-backend
    dynamic "condition" {
      for_each = var.enable_abac ? [1] : []
      content {
        test     = "StringEquals"
        variable = "dynamodb:ResourceTag/resource-type"
        values   = ["state-backend"]
      }
    }

    # ABAC: Restrict to projectID lock prefix (CRITICAL SECURITY)
    dynamic "condition" {
      for_each = var.enable_abac ? [1] : []
      content {
        test     = "ForAllValues:StringLike"
        variable = "dynamodb:LeadingKeys"
        values   = ["$${aws:PrincipalTag/projectID}/*"]
      }
    }
  }
 
  # ABAC: Require tags on resource creation
  dynamic "statement" {
    for_each = var.enable_abac ? [1] : []
    content {
      sid    = "RequireResourceTagsOnCreation"
      effect = "Allow"
      
      actions = [
        "s3:CreateBucket",
        "dynamodb:CreateTable"
      ]
      
      resources = ["*"]
      
      # Require projectID tag matches principal
      condition {
        test     = "StringEquals"
        variable = "aws:RequestTag/projectID"
        values   = ["$${aws:PrincipalTag/projectID}"]
      }
      
      # Require environment tag matches principal
      condition {
        test     = "StringEquals"
        variable = "aws:RequestTag/environment"
        values   = ["$${aws:PrincipalTag/environment}"]
      }
      
      # Require managed-by tag
      condition {
        test     = "StringEquals"
        variable = "aws:RequestTag/managed-by"
        values   = ["terraform"]
      }
    }
  }

  # Allow listing operations (no tag restrictions needed)
  statement {
    sid    = "AllowListOperations"
    effect = "Allow"
    
    actions = [
      "s3:ListAllMyBuckets",
      "dynamodb:ListTables"
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
