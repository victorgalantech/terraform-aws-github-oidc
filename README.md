# AWS GitHub Actions OIDC Setup 🔐

[![AWS](https://img.shields.io/badge/AWS-IAM%20%7C%20OIDC-FF9900?logo=amazon-aws)](https://aws.amazon.com/)

**Secure, keyless authentication for GitHub Actions workflows on AWS using OpenID Connect (OIDC).**

This repository provides everything you need to set up OIDC authentication between GitHub Actions and AWS, eliminating the need for long-lived IAM user access keys.

---

## 📋 Table of Contents

- [What This Solves](#-what-this-solves)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Documentation](#-documentation)
- [Security Best Practices](#-security-best-practices)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)

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

## ⚠️ Prerequisites

- **AWS account(s)** - one per environment (dev, qa, prod)
- **GitHub repository** with Actions enabled
- **AWS CLI** installed and configured
- **Admin access** to AWS console (for initial `dev-admin` user creation)
- **Permissions** to create IAM users, identity providers, and roles

---

## 🚀 Quick Start

### Setup using AWS Console + CLI

**Time:** ~20 minutes per AWS account

👉 **Follow [OIDC_SETUP_GUIDE.md](OIDC_SETUP_GUIDE.md) for complete step-by-step instructions**

**Summary:**
1. **Create dev-admin IAM user** with OIDC and role management permissions
2. **Create OIDC identity provider** in AWS
3. **Create IAM role** with trust policy for GitHub Actions
4. **Attach TerraformDeploymentPolicy** (organization-wide deployment policy)
5. **Configure GitHub Variables** with role ARN
6. **Test with dev environment** before proceeding to QA/Prod

> **⚠️ Important**: Complete setup and testing in **dev** environment before replicating to QA and Prod.

## 📚 Documentation

### Complete Guides

- **[OIDC_SETUP_GUIDE.md](OIDC_SETUP_GUIDE.md)** - Complete manual setup walkthrough
- **[AWS_IAM_POLICIES.md](AWS_IAM_POLICIES.md)** - IAM policy reference and examples

**Best Practice:** Test each environment sequentially (Dev → QA → Prod) before moving to the next.

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

**Solution**: Run Step 1 of setup guide

### Error: "Access Denied" during workflow

**Cause**: IAM role lacks necessary permissions.

**Solution**: 
1. Review attached policies on the role
2. Check resource ARNs match your bucket/table names
3. See [AWS_IAM_POLICIES.md](AWS_IAM_POLICIES.md) for required permissions

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

This OIDC setup enables secure deployments for:

- **[terraform-states-s3-bucket](https://github.com/victorgalantech/terraform-states-s3-bucket)** - Terraform state backend infrastructure
- Future projects: Lambda functions, Fargate services, Glue jobs, Bedrock applications, etc.

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
