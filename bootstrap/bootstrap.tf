terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  profile_map = {
    dev  = "bootstrap-dev"
    qa   = "bootstrap-qa"
    prod = "bootstrap-prod"
  }
}

provider "aws" {
  region  = var.aws_region
  profile = local.profile_map[var.environment]

  default_tags {
    tags = merge(
      var.tags,
      {
        Environment = var.environment
      }
    )
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  account_id            = data.aws_caller_identity.current.account_id
  region                = data.aws_region.current.name
  tfstate_bucket_name   = "${var.company_name}-tfstate-${var.environment}-${local.account_id}"
  cloudtrail_bucket_name = "cloudtrail-logs-${var.company_name}-${var.environment}-${local.account_id}"
  
  # OIDC subject claim pattern
  oidc_subject_claim = var.github_repo != "*" ? [
    "repo:${var.github_org}/${var.github_repo}:*"
  ] : [
    "repo:${var.github_org}/*"
  ]
  
  # Branch-restricted subject claims
  oidc_subject_claim_branches = [
    for branch in var.allowed_branches :
    var.github_repo != "*" ? 
      "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${branch}" :
      "repo:${var.github_org}/*:ref:refs/heads/${branch}"
  ]
}

# ================================================
# OIDC Identity Provider
# ================================================

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = {
    Name = "github-actions-oidc-provider"
  }
}

# ================================================
# IAM Role for GitHub Actions
# ================================================

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect = "Allow"
 
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }
 
    actions = [
      "sts:AssumeRoleWithWebIdentity",
      "sts:TagSession"  # ABAC: Allow tagging sessions
    ]
 
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
 
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.enable_branch_restriction ? local.oidc_subject_claim_branches : local.oidc_subject_claim
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "github-actions-terraform-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
  description        = "GitHub Actions OIDC role for ${var.environment} environment with ABAC support"
  
  # ABAC: Define which tags can be set during assume role
  dynamic "inline_policy" {
    for_each = var.enable_abac ? [1] : []
    content {
      name = "AllowSessionTagging"
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Sid    = "AllowPassSessionTags"
            Effect = "Allow"
            Action = "sts:TagSession"
            Resource = "*"
          }
        ]
      })
    }
  }
 
  tags = merge(
    var.default_resource_tags,
    {
      Name = "github-actions-terraform-${var.environment}"
    }
  )
}

# ================================================
# Terraform Deployment Policy
# ================================================

data "aws_iam_policy_document" "terraform_deployment" {
  # S3 State Bucket Management - Shared across ALL projects
  statement {
    sid    = "S3StateBucketManagement"
    effect = "Allow"

    actions = [
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
    ]

    resources = var.enable_abac ? ["*"] : ["arn:aws:s3:::${var.company_name}-tfstate-*"]

    # ABAC: Match environment tag (NO projectID restriction - shared backend)
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

    # ABAC: Ensure managed-by terraform
    dynamic "condition" {
      for_each = var.enable_abac ? [1] : []
      content {
        test     = "StringEquals"
        variable = "s3:ResourceTag/managed-by"
        values   = ["terraform"]
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
  # When ABAC enabled: Uses dynamic resource pattern with projectID
  # When RBAC enabled: Uses company name pattern
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

    # ABAC: Resource pattern embeds projectID from principal tag
    # This restricts each project to ONLY their own state file path
    # Example: marketing-ai can only access ${bucket}/marketing-ai/*
    resources = var.enable_abac ? [
      "arn:aws:s3:::${var.company_name}-tfstate-${var.environment}-*/$${aws:PrincipalTag/projectID}/*"
    ] : [
      "arn:aws:s3:::${var.company_name}-tfstate-*/*"
    ]

    # Note: With ABAC, the projectID in the resource ARN pattern enforces isolation
    # marketing-ai session → can only access s3://bucket/marketing-ai/*
    # dataplatform session → can only access s3://bucket/dataplatform/*
  }

  # DynamoDB Lock Table Management - Shared across ALL projects
  statement {
    sid    = "DynamoDBLockTableManagement"
    effect = "Allow"

    actions = [
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
    ]

    resources = var.enable_abac ? ["*"] : [
      "arn:aws:dynamodb:${local.region}:${local.account_id}:table/terraform-state-locks-${var.environment}"
    ]

    # ABAC: Match environment tag (NO projectID restriction)
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

  # DynamoDB State Locking - Project-isolated by LockID prefix (CRITICAL SECURITY)
  statement {
    sid    = "DynamoDBStateLockingProjectIsolated"
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable"
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
    # Each project can ONLY access lock records for their own state files
    # LockID format: "projectID/terraform.tfstate-md5"
    # Example: marketing-ai can only access locks starting with "marketing-ai/"
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

  # ================================================================
  # FUTURE: Add project-specific resources below with projectID ABAC
  # ================================================================
  # When adding Lambda, ECS, Glue, Bedrock, or other resources that should
  # be isolated per project, use this pattern:
  #
  # statement {
  #   sid    = "LambdaManagementProjectSpecific"
  #   effect = "Allow"
  #   actions = ["lambda:*"]
  #   resources = var.enable_abac ? ["*"] : ["arn:aws:lambda:${local.region}:${local.account_id}:function:*"]
  #
  #   # ABAC: Require projectID match for project-specific resources
  #   dynamic "condition" {
  #     for_each = var.enable_abac ? [1] : []
  #     content {
  #       test     = "StringEquals"
  #       variable = "lambda:ResourceTag/projectID"
  #       values   = ["$${aws:PrincipalTag/projectID}"]
  #     }
  #   }
  #
  #   dynamic "condition" {
  #     for_each = var.enable_abac ? [1] : []
  #     content {
  #       test     = "StringEquals"
  #       variable = "lambda:ResourceTag/environment"
  #       values   = ["$${aws:PrincipalTag/environment}"]
  #     }
  #   }
  #
  #   # DO NOT add resource-type condition for project-specific resources
  # }
}

resource "aws_iam_policy" "terraform_deployment" {
  name        = "TerraformDeploymentPolicy-${var.environment}"
  description = "Organization-wide deployment policy for GitHub Actions in ${var.environment} environment"
  policy      = data.aws_iam_policy_document.terraform_deployment.json

  tags = {
    Name = "TerraformDeploymentPolicy-${var.environment}"
  }
}

resource "aws_iam_role_policy_attachment" "github_actions_terraform_deployment" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.terraform_deployment.arn
}

# ================================================
# S3 Bucket for Terraform State
# ================================================

resource "aws_s3_bucket" "terraform_state" {
  bucket = local.tfstate_bucket_name

  tags = merge(
    var.default_resource_tags,
    {
      Name          = local.tfstate_bucket_name
      projectID     = var.project_id
      environment   = var.environment
      managed-by    = "terraform"
      resource-type = "state-backend"  # Shared across ALL projects
    }
  )
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# ================================================
# DynamoDB Table for State Locking
# ================================================

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-state-locks-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(
    var.default_resource_tags,
    {
      Name          = "terraform-state-locks-${var.environment}"
      projectID     = var.project_id
      environment   = var.environment
      managed-by    = "terraform"
      resource-type = "state-backend"  # Shared across ALL projects
    }
  )
}

# ================================================
# CloudTrail for OIDC Audit Logging (Optional)
# ================================================

resource "aws_s3_bucket" "cloudtrail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = local.cloudtrail_bucket_name

  tags = {
    Name = local.cloudtrail_bucket_name
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail[0].id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    expiration {
      days = var.cloudtrail_retention_days
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_bucket_policy" {
  count = var.enable_cloudtrail ? 1 : 0

  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail[0].arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = ["arn:aws:cloudtrail:${local.region}:${local.account_id}:trail/github-actions-oidc-${var.environment}"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail[0].arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = ["arn:aws:cloudtrail:${local.region}:${local.account_id}:trail/github-actions-oidc-${var.environment}"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail[0].id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy[0].json
}

resource "aws_cloudtrail" "github_actions_oidc" {
  count                         = var.enable_cloudtrail ? 1 : 0
  name                          = "github-actions-oidc-${var.environment}"
  s3_bucket_name                = aws_s3_bucket.cloudtrail[0].id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.terraform_state.arn}/*"]
    }

    data_resource {
      type   = "AWS::DynamoDB::Table"
      values = [aws_dynamodb_table.terraform_locks.arn]
    }
  }

  tags = {
    Name = "github-actions-oidc-${var.environment}"
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
