# AWS GitHub Actions OIDC Setup 🔐

[![Terraform](https://img.shields.io/badge/Terraform-1.6+-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-IAM%20%7C%20OIDC-FF9900?logo=amazon-aws)](https://aws.amazon.com/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**Secure, keyless authentication for GitHub Actions workflows on AWS using OpenID Connect (OIDC).**

This repository provides everything you need to set up OIDC authentication between GitHub Actions and AWS, eliminating the need for long-lived IAM user access keys.

---

## 🎯 What This Solves

### The Problem

Traditional GitHub Actions authentication with AWS requires:
- ❌ Creating IAM users with access keys
- ❌ Storing long-lived credentials in GitHub Secrets
- ❌ Manual credential rotation
- ❌ Security risk if credentials are leaked

### The Solution (OIDC)

- ✅ **No stored credentials** - GitHub generates temporary tokens
- ✅ **Automatic rotation** - New credentials per workflow run
- ✅ **Better security** - Tokens expire after ~1 hour
- ✅ **Enhanced auditing** - Clear CloudTrail logs with session details
- ✅ **Modern best practice** - Recommended by AWS and GitHub

---

## 📋 Table of Contents

- [What This Solves](#-what-this-solves)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Documentation](#-documentation)
- [Terraform Modules](#-terraform-modules)
- [Examples](#-examples)
- [Security Best Practices](#-security-best-practices)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)

---

## ⚠️ Prerequisites

- AWS account(s) - one per environment (dev, qa, prod)
- GitHub repository with Actions enabled
- AWS CLI installed and configured
- Terraform 1.6+ (if using Terraform modules)
- Permissions to create IAM identity providers and roles

---

## 🚀 Quick Start

### Option 1: Manual Setup (AWS Console + CLI)

**Time:** ~15 minutes per AWS account

👉 **Follow [OIDC_SETUP_GUIDE.md](OIDC_SETUP_GUIDE.md) for step-by-step instructions**

**Summary:**
1. Create OIDC identity provider in AWS
2. Create IAM role with trust policy for GitHub
3. Attach permissions policy to role
4. Configure GitHub Variables with role ARN

### Option 2: Terraform Automation (Recommended)

**Time:** ~5 minutes per AWS account

```bash
cd terraform

# Configure for your environment
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Deploy
terraform init
terraform plan
terraform apply
```

**What gets created:**
- ✅ OIDC identity provider
- ✅ IAM role with GitHub trust policy
- ✅ IAM policy with required permissions
- ✅ Policy attachment to role

---

## 📚 Documentation

### Complete Guides

- **[OIDC_SETUP_GUIDE.md](OIDC_SETUP_GUIDE.md)** - Complete manual setup walkthrough
- **[AWS_IAM_POLICIES.md](AWS_IAM_POLICIES.md)** - IAM policy reference and examples

### Quick References

- **[examples/github-actions-role/](examples/github-actions-role/)** - Example Terraform configuration
- **[terraform/](terraform/)** - Reusable Terraform module

---

## 🏗️ Terraform Modules

This repository provides reusable Terraform modules for automated setup:

### Module: `oidc-provider`

Creates AWS OIDC identity provider for GitHub Actions.

```hcl
module "github_oidc" {
  source = "./terraform"

  github_org        = "your-org"
  github_repo       = "your-repo"
  role_name         = "github-actions-terraform-dev"
  aws_region        = "eu-west-1"
  
  # S3 and DynamoDB permissions
  s3_bucket_patterns = [
    "arn:aws:s3:::<company>-tfstate-*",
    "arn:aws:s3:::<company>-tfstate-*/*"
  ]
  
  dynamodb_table_arns = [
    "arn:aws:dynamodb:eu-west-1:*:table/terraform-state-locks"
  ]
}
```

**Outputs:**
- `role_arn` - IAM role ARN to use in GitHub Variables
- `oidc_provider_arn` - OIDC provider ARN

---

## 💡 Examples

### Example 1: Single Environment

```bash
cd examples/github-actions-role
terraform init
terraform apply
```

Creates OIDC setup for one environment (e.g., dev).

### Example 2: Multi-Account Setup

Deploy to 3 separate AWS accounts:

```bash
# Dev Account
export AWS_PROFILE=dev-admin
cd examples/github-actions-role
terraform workspace new dev
terraform apply -var-file=dev.tfvars

# QA Account
export AWS_PROFILE=qa-admin
terraform workspace new qa
terraform apply -var-file=qa.tfvars

# Prod Account
export AWS_PROFILE=prod-admin
terraform workspace new prod
terraform apply -var-file=prod.tfvars
```

---

## 🔐 Security Best Practices

### 1. Scope Trust Policies

**Restrict to specific branches:**

```json
"Condition": {
  "StringLike": {
    "token.actions.githubusercontent.com:sub": [
      "repo:myorg/myrepo:ref:refs/heads/main",
      "repo:myorg/myrepo:ref:refs/heads/develop"
    ]
  }
}
```

**Restrict to specific environments:**

```json
"StringEquals": {
  "token.actions.githubusercontent.com:environment": "production"
}
```

### 2. Use Separate Roles per Environment

- ✅ One AWS account per environment (dev, qa, prod)
- ✅ Separate IAM role in each account
- ✅ Least privilege permissions scoped to environment resources

### 3. Enable Monitoring

```bash
# Enable CloudTrail
aws cloudtrail create-trail \
  --name github-actions-audit \
  --s3-bucket-name my-cloudtrail-logs

# Monitor AssumeRole events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity
```

### 4. Regular Audits

- Review CloudTrail logs monthly
- Check for unauthorized access attempts
- Verify role permissions are still appropriate
- Update trust policies as team structure changes

---

## 🐛 Troubleshooting

### Error: "Not authorized to perform: sts:AssumeRoleWithWebIdentity"

**Cause**: Trust policy misconfigured or OIDC provider not found.

**Solution**:
1. Verify OIDC provider exists in AWS account
2. Check trust policy repository name matches exactly
3. Ensure `token.actions.githubusercontent.com:sub` pattern is correct

### Error: "No OpenIDConnect provider found"

**Cause**: OIDC provider not created in AWS account.

**Solution**: Run Step 1 of setup guide or deploy Terraform module.

### Error: "Access Denied" during workflow

**Cause**: IAM role lacks necessary permissions.

**Solution**: 
1. Review attached policies on the role
2. Check resource ARNs match your bucket/table names
3. See [AWS_IAM_POLICIES.md](AWS_IAM_POLICIES.md) for required permissions

---

## 🔄 Migration from IAM User Access Keys

### Migration Checklist

- [ ] Complete OIDC setup for all environments
- [ ] Test workflows with OIDC on feature branch
- [ ] Verify all environment workflows succeed
- [ ] Update GitHub Variables with role ARNs
- [ ] Remove old access key secrets
- [ ] Delete IAM users (after confidence period)
- [ ] Update team documentation

### Rollback Procedure

If issues occur, quickly revert:

1. Re-add access key secrets to GitHub
2. Revert workflow to use `aws-access-key-id` / `aws-secret-access-key`
3. Debug OIDC setup offline

---

## 📊 Architecture

### How OIDC Works

```
┌──────────────────┐
│ GitHub Actions   │
│   Workflow       │
└────────┬─────────┘
         │
         │ 1. Request OIDC token
         ↓
┌────────────────────────────────────────┐
│  GitHub Token Service                  │
│  - Generates signed JWT                │
│  - Includes repo, branch, environment  │
└────────┬───────────────────────────────┘
         │
         │ 2. Return JWT token
         ↓
┌──────────────────┐
│ GitHub Actions   │
│   Workflow       │
└────────┬─────────┘
         │
         │ 3. Exchange token for AWS credentials
         ↓
┌────────────────────────────────────────┐
│  AWS STS (Security Token Service)      │
│  - Validates JWT signature             │
│  - Checks trust policy conditions      │
│  - Returns temporary credentials       │
└────────┬───────────────────────────────┘
         │
         │ 4. Temporary credentials (~1 hour)
         ↓
┌──────────────────┐
│ GitHub Actions   │
│   Workflow       │
│ ✅ Authenticated  │
└──────────────────┘
```

### Multi-Account Setup

```
GitHub Repository
        │
        ├─── Branch: develop → OIDC → AWS Account A (dev)
        │                               └─ Role: github-actions-terraform-dev
        │
        ├─── Branch: release/* → OIDC → AWS Account B (qa)
        │                                └─ Role: github-actions-terraform-qa
        │
        └─── Branch: main → OIDC → AWS Account C (prod)
                                    └─ Role: github-actions-terraform-pro
```

---

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details

---

## 🔗 Related Projects

This OIDC setup is a prerequisite for:

- **[terraform-states-s3-bucket](https://github.com/YOUR_ORG/terraform-states-s3-bucket)** - Terraform state backend infrastructure

---

## 📞 Support

- 📖 Documentation: See guides in this repository
- 🐛 Issues: Open an issue on GitHub
- 💬 Discussions: Use GitHub Discussions

---

## ⭐ Show Your Support

If this project helped you, please give it a ⭐️!

---

**Built with ❤️ for secure, modern DevOps practices**
