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
