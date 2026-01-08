terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "dev-admin"

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

    actions = ["sts:AssumeRoleWithWebIdentity"]

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
  description        = "GitHub Actions OIDC role for ${var.environment} environment"

  tags = {
    Name = "github-actions-terraform-${var.environment}"
  }
}

# ================================================
# Terraform Deployment Policy
# ================================================

data "aws_iam_policy_document" "terraform_deployment" {
  # S3 Bucket Management
  statement {
    sid    = "S3BucketManagement"
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

    resources = [
      "arn:aws:s3:::${var.company_name}-tfstate-*"
    ]
  }

  # S3 Object Management
  statement {
    sid    = "S3ObjectManagement"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetObjectVersion",
      "s3:DeleteObjectVersion"
    ]

    resources = [
      "arn:aws:s3:::${var.company_name}-tfstate-*/*"
    ]
  }

  # DynamoDB Table Management
  statement {
    sid    = "DynamoDBTableManagement"
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

    resources = [
      "arn:aws:dynamodb:${local.region}:${local.account_id}:table/terraform-state-locks-${var.environment}"
    ]
  }

  # DynamoDB State Locking
  statement {
    sid    = "DynamoDBStateLocking"
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable"
    ]

    resources = [
      "arn:aws:dynamodb:${local.region}:${local.account_id}:table/terraform-state-locks-${var.environment}"
    ]
  }

  # Add additional permissions here as needed
  # Examples: Lambda, Fargate, Glue, Bedrock, etc.
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

  tags = {
    Name = local.tfstate_bucket_name
  }
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

  tags = {
    Name = "terraform-state-locks-${var.environment}"
  }
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
