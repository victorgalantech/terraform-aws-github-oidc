output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider"
  value       = aws_iam_openid_connect_provider.github_actions.arn
}

output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_role_name" {
  description = "Name of the GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.name
}

output "terraform_state_bucket" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "terraform_state_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "dynamodb_lock_table" {
  description = "DynamoDB table name for state locking"
  value       = aws_dynamodb_table.terraform_locks.id
}

output "dynamodb_lock_table_arn" {
  description = "ARN of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_locks.arn
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = local.account_id
}

output "aws_region" {
  description = "AWS Region"
  value       = local.region
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "cloudtrail_name" {
  description = "CloudTrail name (if enabled)"
  value       = var.enable_cloudtrail ? aws_cloudtrail.github_actions_oidc[0].name : null
}

output "cloudtrail_bucket" {
  description = "CloudTrail S3 bucket name (if enabled)"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail[0].id : null
}

output "cloudtrail_arn" {
  description = "CloudTrail ARN (if enabled)"
  value       = var.enable_cloudtrail ? aws_cloudtrail.github_actions_oidc[0].arn : null
}

output "backend_config" {
  description = "Backend configuration for state migration"
  value = {
    bucket         = aws_s3_bucket.terraform_state.id
    key            = "bootstrap/terraform.tfstate"
    region         = local.region
    dynamodb_table = aws_dynamodb_table.terraform_locks.id
    encrypt        = true
  }
}

output "github_variable_setup" {
  description = "GitHub variable to set in repository"
  value = {
    AWS_ROLE_ARN_DEV  = var.environment == "dev" ? aws_iam_role.github_actions.arn : null
    AWS_ROLE_ARN_QA   = var.environment == "qa" ? aws_iam_role.github_actions.arn : null
    AWS_ROLE_ARN_PROD = var.environment == "prod" ? aws_iam_role.github_actions.arn : null
  }
}

output "next_steps" {
  description = "Next steps after bootstrap"
  value = <<-EOT
  
  ========================================
  Bootstrap Complete! 🎉
  ========================================
  
  Resources Created:
  - OIDC Provider: ${aws_iam_openid_connect_provider.github_actions.arn}
  - IAM Role: ${aws_iam_role.github_actions.name}
  - S3 State Bucket: ${aws_s3_bucket.terraform_state.id}
  - DynamoDB Lock Table: ${aws_dynamodb_table.terraform_locks.id}
  ${var.enable_cloudtrail ? "- CloudTrail: ${aws_cloudtrail.github_actions_oidc[0].name} (enabled for audit logging)" : "- CloudTrail: disabled"}
  
  Next Steps:
  
  1. Migrate state to S3 backend:
     
     terraform init -migrate-state -backend-config="backend-config.hcl"
  
  2. Set GitHub Variables (Settings → Secrets and variables → Actions → Variables):
     
     Name: AWS_ROLE_ARN_${upper(var.environment)}
     Value: ${aws_iam_role.github_actions.arn}
  
  3. Verify the setup:
     
     aws sts get-caller-identity --profile bootstrap-dev
     aws s3 ls s3://${aws_s3_bucket.terraform_state.id}
     aws dynamodb describe-table --table-name ${aws_dynamodb_table.terraform_locks.id}
     ${var.enable_cloudtrail ? "aws cloudtrail get-trail-status --name ${aws_cloudtrail.github_actions_oidc[0].name}" : ""}
  
  4. Test GitHub Actions workflow with OIDC authentication
  ${var.enable_cloudtrail ? "\n  5. Query CloudTrail logs to monitor OIDC authentications:\n     aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity" : ""}
  
  ========================================
  EOT
}
