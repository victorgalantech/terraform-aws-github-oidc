# Terraform AWS OIDC Bootstrap 🔐

[![AWS](https://img.shields.io/badge/AWS-IAM%20%7C%20OIDC-FF9900?logo=amazon-aws)](https://aws.amazon.com/)
[![Terraform](https://img.shields.io/badge/Terraform-1.6%2B-7B42BC?logo=terraform)](https://www.terraform.io/)

**Complete Terraform bootstrap for GitHub Actions on AWS using OpenID Connect (OIDC), AWS CloudTrail to monitor and audit GitHub Actions OIDC authentication and activities, including automated S3 state backend and DynamoDB locking.**

This repository provides everything you need to bootstrap your AWS CI/CD infrastructure with secure, keyless authentication and proper Terraform state management - all in one place.

---

## 📋 Table of Contents

- [What This Solves](#-what-this-solves)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Documentation](#-documentation)
- [Architecture](#-architecture)
- [Contributing](#-contributing)

---

## 🎯 What This Solves

### The Problem

Setting up GitHub Actions with AWS traditionally requires:
- ❌ Creating IAM users with access keys
- ❌ Storing long-lived credentials in GitHub Secrets
- ❌ Manual S3 state backend setup
- ❌ Separate DynamoDB table creation for locking
- ❌ Manual credential rotation
- ❌ Security risk if credentials are leaked

### The Solution (This Repository)

- ✅ **No stored credentials** - OIDC generates temporary tokens per workflow run
- ✅ **Automatic state backend** - S3 bucket and DynamoDB table created automatically
- ✅ **State migration included** - Seamlessly moves from local to S3 backend
- ✅ **Complete bootstrap** - Everything needed for Terraform CI/CD in one place
- ✅ **Better security** - Tokens expire after ~1 hour, encrypted state storage
- ✅ **Enhanced auditing** - CloudTrail integration ready
- ✅ **Modern best practice** - Recommended by AWS and GitHub


---

## ⚠️ Prerequisites

- **AWS account(s)** - one per environment (dev, qa, prod)
- **GitHub repository** with Actions enabled
- **AWS CLI** installed and configured
- **Admin access** to AWS console (for initial `bootstrap-dev` user creation)
- **Permissions** to create IAM users, identity providers, and roles

---

## 🚀 Quick Start

### Option 1: Terraform Bootstrap (Recommended) 🏗️

**Time:** ~10 minutes per AWS account

👉 **Follow [TERRAFORM_BOOTSTRAP_GUIDE.md](TERRAFORM_BOOTSTRAP_GUIDE.md) for complete instructions**

**Summary:**
1. **Create bootstrap-dev IAM user** (one-time manual setup)
2. **Configure Terraform variables** (`terraform.tfvars`)
3. **Run Terraform** to create OIDC provider, CloudtTrial, IAM roles, S3 backend, and DynamoDB table
4. **Migrate state** to S3 backend automatically
5. **Configure GitHub Variables** with role ARN
6. **Test workflow** - done!

**Benefits:**
- ✅ Fully automated infrastructure creation
- ✅ Automatic S3 state backend setup and migration
- ✅ Repeatable across environments
- ✅ Infrastructure as Code - version controlled
- ✅ Idempotent - safe to run multiple times

### Option 2: Manual Setup (AWS Console + CLI)

**Time:** ~20 minutes per AWS account

👉 **Follow [OIDC_SETUP_GUIDE.md](OIDC_SETUP_GUIDE.md) for step-by-step instructions**

**When to use manual setup:**
- Learning how OIDC works under the hood
- Organizational policy requires manual infrastructure review
- Terraform not available in your environment

> **⚠️ Important**: Complete setup and testing in **dev** environment before replicating to QA and Prod.

## 📚 Documentation

### Complete Guides

- **[TERRAFORM_BOOTSTRAP_GUIDE.md](TERRAFORM_BOOTSTRAP_GUIDE.md)** - 🏗️ Automated Terraform bootstrap with state migration (recommended)
- **[OIDC_SETUP_GUIDE.md](OIDC_SETUP_GUIDE.md)** - Manual setup walkthrough (alternative)
- **[AWS_IAM_POLICIES.md](AWS_IAM_POLICIES.md)** - IAM policy reference and examples
- **[CLOUDTRAIL_SETUP.md](CLOUDTRAIL_SETUP.md)** - CloudTrail logging and monitoring setup (recommended for security and compliance)

**Best Practice:** Test each environment sequentially (Dev → QA → Prod) before moving to the next.

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
│  - Validates JWT signature             │◄─────┐
│  - Checks trust policy conditions      │      │
│  - Returns temporary credentials       │      │
└────────┬───────────────────────────────┘      │
         │                                       │
         │ 4. Temporary credentials (~1 hour)    │
         ↓                                       │
┌──────────────────┐                            │
│ GitHub Actions   │                            │
│   Workflow       │                            │
│ ✅ Authenticated  │                            │
└────────┬─────────┘                            │
         │                                       │
         │ 5. AWS API calls                      │
         ↓                                       │
┌────────────────────────────────────────┐      │
│  AWS Services                          │      │
│  (S3, DynamoDB, Lambda, etc.)          │      │
└────────────────────────────────────────┘      │
                                                 │
         ┌───────────────────────────────────────┘
         │ All events logged
         ↓
┌────────────────────────────────────────┐
│  AWS CloudTrail                        │
│  - AssumeRoleWithWebIdentity events    │
│  - All API calls with session details  │
│  - Stored in S3 for audit/compliance   │
└────────────────────────────────────────┘
```

### Complete Bootstrap Architecture

```
terraform-aws-oidc-bootstrap Repository
        │
        ├─── bootstrap/ (Terraform code)
        │    ├─── bootstrap.tf (OIDC + IAM + S3 + DynamoDB)
        │    ├─── variables.tf (Configuration)
        │    └─── outputs.tf (Role ARNs, backend config)
        │
        └─── Documentation
             ├─── TERRAFORM_BOOTSTRAP_GUIDE.md (Primary guide)
             ├─── OIDC_SETUP_GUIDE.md (Manual alternative)
             ├─── AWS_IAM_POLICIES.md (Policy reference)
             └─── CLOUDTRAIL_SETUP.md (Audit logging)

Bootstrap Creates (per environment):
┌─────────────────────────────────────────────────┐
│  AWS Account (dev/qa/prod)                      │
│                                                  │
│  ┌────────────────────────────────────────┐    │
│  │ OIDC Provider                           │    │
│  │ token.actions.githubusercontent.com     │    │
│  └─────────────┬──────────────────────────┘    │
│                │                                 │
│  ┌─────────────▼──────────────────────────┐    │
│  │ IAM Role                                │    │
│  │ github-actions-terraform-{env}          │    │
│  └─────────────┬──────────────────────────┘    │
│                │                                 │
│  ┌─────────────▼──────────────────────────┐    │
│  │ TerraformDeploymentPolicy               │    │
│  │ - S3 bucket management                  │    │
│  │ - DynamoDB table management             │    │
│  │ - Expandable for Lambda, ECS, etc.      │    │
│  └──────────────────────────────────────────┘   │
│                                                  │
│  ┌────────────────────────────────────────┐    │
│  │ S3 Bucket                               │    │
│  │ {company}-tfstate-{env}-{account-id}    │    │
│  │ - Versioning enabled                    │    │
│  │ - Encryption enabled (AES256)           │    │
│  │ - Public access blocked                 │    │
│  └──────────────────────────────────────────┘   │
│                                                  │
│  ┌────────────────────────────────────────┐    │
│  │ DynamoDB Table                          │    │
│  │ terraform-state-locks-{env}             │    │
│  │ - Point-in-time recovery enabled        │    │
│  │ - Pay-per-request billing               │    │
│  └──────────────────────────────────────────┘   │
│                                                  │
│  ┌────────────────────────────────────────┐    │
│  │ CloudTrail (optional)                   │    │
│  │ - Logs all OIDC authentications         │    │
│  │ - Audit trail for compliance            │    │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘

GitHub Actions Workflow Uses:
        │
        ├─── Branch: develop → OIDC → AWS Account A (dev)
        │                               └─ Role ARN from bootstrap
        │
        ├─── Branch: release/* → OIDC → AWS Account B (qa)
        │                                └─ Role ARN from bootstrap
        │
        └─── Branch: main → OIDC → AWS Account C (prod)
                                    └─ Role ARN from bootstrap
```

---

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## � What You Get

This repository provides the **complete foundation** for your AWS CI/CD infrastructure:

### Infrastructure Created
- ✅ **OIDC Identity Provider** - Secure GitHub Actions authentication
- ✅ **IAM Roles & Policies** - Scoped permissions per environment
- ✅ **S3 State Backend** - Versioned, encrypted Terraform state storage
- ✅ **DynamoDB Lock Table** - State locking with point-in-time recovery
- ✅ **Automated Migration** - Seamless local-to-S3 state transition

### Ready for Your Projects
Once bootstrapped, use this foundation for deploying:
- 🚀 Lambda functions
- 🚀 Fargate services and ECS clusters
- 🚀 Glue data pipelines
- 🚀 Bedrock AI applications
- 🚀 Any AWS infrastructure managed by Terraform

### No Separate Repositories Needed
Everything you need is in this single repository - no external dependencies for state management.

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
