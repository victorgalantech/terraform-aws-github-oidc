# =============================================================================
# Dev environment — account-specific settings
# =============================================================================

locals {
  environment = "dev"
  account_id  = "YOUR_DEV_ACCOUNT_ID" # Replace with your AWS account ID
  aws_profile = "bootstrap-dev"       # AWS CLI profile with bootstrap-dev IAM user credentials
}
