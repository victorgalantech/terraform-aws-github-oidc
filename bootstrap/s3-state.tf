# ================================================
# S3 Bucket for Terraform State Storage
# ================================================

resource "aws_s3_bucket" "terraform_state" {
  bucket = local.tfstate_bucket_name

  tags = {
    Name          = local.tfstate_bucket_name
    resource-type = "state-backend"
  }

  # Ensure IAM policy is fully applied before attempting bucket operations
  depends_on = [aws_iam_role_policy_attachment.github_actions_terraform_deployment]
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for Terraform state bucket encryption - ${var.environment}"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = {
    Name          = "terraform-state-kms-${var.environment}"
    resource-type = "kms-key"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = aws_kms_key.terraform_state.arn
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

# ================================================
# S3 Bucket Policy for Security Enforcement
# ================================================

data "aws_iam_policy_document" "terraform_state_bucket_policy" {
  # Deny non-HTTPS requests
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Enforce TLS 1.2 or higher
  statement {
    sid    = "EnforceTLS12OrHigher"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*"
    ]

    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values   = ["1.2"]
    }
  }
}

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  policy = data.aws_iam_policy_document.terraform_state_bucket_policy.json

  depends_on = [aws_s3_bucket_public_access_block.terraform_state]
}

# ================================================
# Lifecycle Configuration
# ================================================

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
  days_after_initiation = 7
}
  }
}


resource "aws_s3_bucket_logging" "terraform_state" {
  bucket        = aws_s3_bucket.terraform_state.id
  target_bucket = aws_s3_bucket.terraform_state.id
  target_prefix = "access-logs/"
}