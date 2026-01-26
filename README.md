# Terraform AWS OIDC Bootstrap 🔐

[![AWS](https://img.shields.io/badge/AWS-IAM%20%7C%20OIDC-FF9900?logo=amazon-aws)](https://aws.amazon.com/)
[![Terraform](https://img.shields.io/badge/Terraform-1.6%2B-7B42BC?logo=terraform)](https://www.terraform.io/)
[![Security](https://img.shields.io/badge/Security-ABAC%20%7C%20Defense--in--Depth-green)](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction_attribute-based-access-control.html)

**Enterprise-grade Terraform bootstrap for GitHub Actions on AWS with Attribute-Based Access Control (ABAC), immutable audit logging, and defense-in-depth security.**

This repository provides everything you need to bootstrap your AWS CI/CD infrastructure with:
- 🔐 **Keyless authentication** - OpenID Connect (OIDC) with no stored credentials
- 🏷️ **ABAC isolation** - Project-level access control using session tags
- 🔒 **Immutable audit trail** - CloudTrail with Object Lock COMPLIANCE mode
- 🛡️ **Defense-in-depth** - 7 layers of security controls
- 📦 **Automated state backend** - S3 and DynamoDB with encryption and versioning
- ✅ **Compliance ready** - SOC 2, ISO 27001, PCI-DSS, GDPR aligned

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
- ❌ No project isolation in multi-project environments
- ❌ Risk of cross-project state tampering
- ❌ Mutable audit logs that can be deleted

### The Solution (This Repository)

#### **Security & Access Control**
- ✅ **No stored credentials** - OIDC generates temporary tokens per workflow run
- ✅ **ABAC (Attribute-Based Access Control)** - Project isolation using session tags
- ✅ **Project isolation** - Each project can only access their own state files
- ✅ **Environment separation** - Dev/QA/Prod completely isolated
- ✅ **Bootstrap-only destructive ops** - Only infrastructure project can delete shared resources
- ✅ **Immutable audit trail** - CloudTrail with Object Lock (90-day tamper-proof logs)
- ✅ **Transport security** - TLS 1.2+ enforcement on all S3/DynamoDB access

#### **Infrastructure & Automation**
- ✅ **Automatic state backend** - S3 bucket and DynamoDB table created automatically
- ✅ **State migration included** - Seamlessly moves from local to S3 backend
- ✅ **S3 versioning** - State recovery from accidental deletions
- ✅ **Encryption at rest** - AES-256 encryption for state files and audit logs
- ✅ **Complete bootstrap** - Everything needed for Terraform CI/CD in one place

#### **Compliance & Best Practices**
- ✅ **Defense-in-depth** - 7 security layers protecting your infrastructure
- ✅ **AWS Well-Architected** - Security, reliability, and operational excellence
- ✅ **Compliance ready** - SOC 2, ISO 27001, PCI-DSS, GDPR mappings included
- ✅ **Modern best practice** - Recommended by AWS and GitHub

---

## ⚠️ Prerequisites

- **AWS account(s)** - one per environment (dev, qa, prod)
- **GitHub repository** with Actions enabled
- **AWS CLI** installed and configured
- **Admin access** to AWS console (for initial `bootstrap-{env}` user creation) *Explain in [TERRAFORM_BOOTSTRAP_GUIDE.md](TERRAFORM_BOOTSTRAP_GUIDE.md)
- **Permissions** to create IAM users, identity providers, and roles

---

## 🚀 Quick Start

### Terraform Bootstrap 🏗️

**Time:** ~10 minutes per AWS account

👉 **Follow [TERRAFORM_BOOTSTRAP_GUIDE.md](TERRAFORM_BOOTSTRAP_GUIDE.md) for complete instructions**

**Summary:**
1. **Create bootstrap-{env} IAM user** (one-time manual setup per account)
2. **Configure Terraform variables** (`terraform.tfvars`) - including ABAC settings
3. **Run Terraform** to create OIDC provider, ABAC policies, CloudTrail, S3 backend, and DynamoDB table
4. **Migrate state** to S3 backend automatically
5. **Configure GitHub Variables** with role ARN
6. **Test workflow with ABAC** - done!
7. **Delete bootstrap-{env} IAM user** Optional but recommended

**What Gets Created:**
- ✅ OIDC provider with session tagging support
- ✅ IAM roles with ABAC conditions (projectID + environment isolation)
- ✅ S3 state bucket (versioned, encrypted, public access blocked, TLS 1.2+ enforced)
- ✅ DynamoDB lock table (point-in-time recovery)
- ✅ CloudTrail with Object Lock (immutable 90-day audit logs)
- ✅ Defense-in-depth security with 7 protection layers

**Benefits:**
- ✅ Fully automated infrastructure creation
- ✅ Project isolation via ABAC - no cross-project access
- ✅ Immutable audit trail for compliance
- ✅ Repeatable across environments
- ✅ Infrastructure as Code - version controlled
- ✅ Idempotent - safe to run multiple times

> **⚠️ Important**: Complete setup and testing in **dev** environment before replicating to QA and Prod.

## 📚 Documentation

### Complete Guides

- **[TERRAFORM_BOOTSTRAP_GUIDE.md](TERRAFORM_BOOTSTRAP_GUIDE.md)** - 🏗️ Automated Terraform bootstrap with ABAC and state migration

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
│  │ + sts:TagSession support                │    │
│  └─────────────┬──────────────────────────┘    │
│                │                                 │
│  ┌─────────────▼──────────────────────────┐    │
│  │ IAM Role (ABAC-enabled)                 │    │
│  │ github-actions-terraform-{env}          │    │
│  │ + Session tags: projectID, environment  │    │
│  └─────────────┬──────────────────────────┘    │
│                │                                 │
│  ┌─────────────▼──────────────────────────┐    │
│  │ TerraformDeploymentPolicy (ABAC)        │    │
│  │ - Project isolation (${projectID})      │    │
│  │ - Environment isolation                 │    │
│  │ - Bootstrap-only destructive ops        │    │
│  │ - Expandable for Lambda, ECS, etc.      │    │
│  └──────────────────────────────────────────┘   │
│                                                  │
│  ┌────────────────────────────────────────┐    │
│  │ S3 State Bucket (Shared, ABAC-isolated) │    │
│  │ {company}-tfstate-{env}-{account-id}    │    │
│  │ - Versioning enabled                    │    │
│  │ - Encryption (AES-256)                  │    │
│  │ - Public access blocked                 │    │
│  │ - TLS 1.2+ enforced                     │    │
│  │ - Key prefix isolation per project      │    │
│  └──────────────────────────────────────────┘   │
│                                                  │
│  ┌────────────────────────────────────────┐    │
│  │ DynamoDB Lock Table (Shared, isolated)  │    │
│  │ terraform-state-locks-{env}             │    │
│  │ - Point-in-time recovery enabled        │    │
│  │ - Pay-per-request billing               │    │
│  │ - LeadingKeys isolation per project     │    │
│  └──────────────────────────────────────────┘   │
│                                                  │
│  ┌────────────────────────────────────────┐    │
│  │ CloudTrail (Immutable)                  │    │
│  │ - Object Lock COMPLIANCE (90 days)      │    │
│  │ - All OIDC authentications logged       │    │
│  │ - Data events (S3, DynamoDB, Lambda)    │    │
│  │ - CloudTrail Insights (anomalies)       │    │
│  │ - Log validation (SHA-256)              │    │
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

## 🔒 Security Highlights

### Defense-in-Depth (7 Layers)

1. **Bootstrap-Only Destructive Ops** - Only infrastructure project can delete shared resources
2. **S3 Key Prefix Isolation** - Projects can only access `s3://bucket/{projectID}/*`
3. **DynamoDB LeadingKeys Isolation** - Lock records restricted to `{projectID}/*` pattern
4. **CloudTrail Immutable Logs** - Object Lock prevents deletion for 90 days
5. **S3 Versioning** - State recovery from accidental deletions
6. **Environment Isolation** - Dev/QA/Prod completely separated
7. **Transport Security** - TLS 1.2+ enforced on all connections

### ABAC in Action

**Scenario:** Marketing-AI project attempts to access Dataplatform state file

```yaml
# GitHub Actions passes session tags
role-session-tags: |
  projectID=marketing-ai
  environment=dev
```

**IAM Evaluation:**
```json
{
  "Resource": "arn:aws:s3:::bucket/${aws:PrincipalTag/projectID}/*"
}
// Resolves to: arn:aws:s3:::bucket/marketing-ai/*
// Request for: s3://bucket/dataplatform/terraform.tfstate
// Result: ACCESS DENIED ❌
```

**Result:** Complete isolation between projects with single policy.

### Threat Protection

| Threat | Defense | Result |
|--------|---------|--------|
| **Insider deletes state bucket** | Bootstrap-only DeleteBucket | ❌ Denied |
| **Cross-project state tampering** | S3 key prefix isolation | ❌ Denied |
| **Lock record manipulation** | DynamoDB LeadingKeys | ❌ Denied |
| **Audit log deletion** | Object Lock COMPLIANCE | ❌ Denied |
| **State file deletion** | S3 versioning | ✅ Recoverable |

See [SECURITY_ARCHITECTURE.md](SECURITY_ARCHITECTURE.md) for complete threat model and testing procedures.

---

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## 🎁 What You Get

This repository provides the **complete foundation** for your AWS CI/CD infrastructure:

### Infrastructure Created
- ✅ **OIDC Identity Provider** - Secure GitHub Actions authentication with session tagging
- ✅ **IAM Roles & Policies (ABAC)** - Dynamic permissions with project isolation
- ✅ **S3 State Backend** - Versioned, encrypted, TLS 1.2+ enforced, project-isolated
- ✅ **DynamoDB Lock Table** - State locking with point-in-time recovery, project-isolated
- ✅ **CloudTrail with Object Lock** - Immutable 90-day audit trail
- ✅ **Automated Migration** - Seamless local-to-S3 state transition
- ✅ **Defense-in-Depth Security** - 7 layers of protection

### Security & Compliance
- 🛡️ **ABAC** - Attribute-Based Access Control for multi-project environments
- 🔒 **Immutable Audit Trail** - Tamper-proof CloudTrail logs
- ✅ **Compliance Ready** - SOC 2, ISO 27001, PCI-DSS, GDPR aligned
- 🔐 **Project Isolation** - Complete separation between projects
- 🚨 **Threat Protection** - Guards against insider threats and cross-project attacks

### Ready for Your Projects
Once bootstrapped, deploy with ABAC isolation:
- 🚀 **Lambda functions** (project-isolated)
- 🚀 **Fargate/ECS** (project-isolated)
- 🚀 **Glue data pipelines** (project-isolated)
- 🚀 **Bedrock AI applications** (project-isolated)
- 🚀 **Any AWS infrastructure** managed by Terraform

**Each project gets:**
- Own state file path: `s3://bucket/{projectID}/terraform.tfstate`
- Own lock records: `{projectID}/*`
- Complete isolation from other projects
- Same IAM role, different access based on session tags

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
