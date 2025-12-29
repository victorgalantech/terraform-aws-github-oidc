# AWS IAM Policies for GitHub Actions OIDC

This document provides IAM policy reference and examples for GitHub Actions OIDC authentication with AWS.

## 📋 Table of Contents

- [Overview](#overview)
- [Deployment Scenarios](#deployment-scenarios)
- [IAM Policy for Terraform State Backend](#iam-policy-for-terraform-state-backend)
- [IAM Policy for General AWS Deployments](#iam-policy-for-general-aws-deployments)
- [Trust Policy Examples](#trust-policy-examples)
- [Security Best Practices](#security-best-practices)

---

## Overview

When using OIDC authentication, you need two types of policies:

1. **Trust Policy** (AssumeRole Policy) - Allows GitHub Actions to assume the IAM role
2. **Permissions Policy** - Defines what AWS actions the role can perform

---

## Deployment Scenarios

### Scenario 1: Terraform State Backend Deployment

For deploying S3 buckets and DynamoDB tables for Terraform state management.

### Scenario 2: Application Deployment

For deploying applications (EC2, Lambda, ECS, etc.).

### Scenario 3: Infrastructure as Code

For general Terraform/Cloud

Formation deployments.

---

## IAM Policy for Terraform State Backend

### Permissions Policy

This policy allows creating and managing S3 buckets and DynamoDB tables for Terraform state:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3BucketManagement",
      "Effect": "Allow",
      "Action": [
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
      ],
      "Resource": "arn:aws:s3:::<COMPANY_NAME>-tfstate-*"
    },
    {
      "Sid": "S3ObjectManagement",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetObjectVersion",
        "s3:DeleteObjectVersion"
      ],
      "Resource": "arn:aws:s3:::<COMPANY_NAME>-tfstate-*/*"
    },
    {
      "Sid": "DynamoDBTableManagement",
      "Effect": "Allow",
      "Action": [
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
      ],
      "Resource": "arn:aws:dynamodb:<REGION>:*:table/terraform-state-locks"
    },
    {
      "Sid": "DynamoDBStateLocking",
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:DeleteItem",
        "dynamodb:DescribeTable"
      ],
      "Resource": "arn:aws:dynamodb:<REGION>:*:table/terraform-state-locks"
    }
  ]
}
```

**Customization:**
- Replace `<COMPANY_NAME>` with your S3 bucket prefix
- Replace `<REGION>` with your AWS region (e.g., `eu-west-1`)

---

## IAM Policy for General AWS Deployments

### Full Infrastructure Deployment

For general Terraform/IaC deployments across multiple services:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2FullAccess",
      "Effect": "Allow",
      "Action": "ec2:*",
      "Resource": "*"
    },
    {
      "Sid": "VPCFullAccess",
      "Effect": "Allow",
      "Action": "ec2:*Vpc*",
      "Resource": "*"
    },
    {
      "Sid": "LambdaFullAccess",
      "Effect": "Allow",
      "Action": "lambda:*",
      "Resource": "*"
    },
    {
      "Sid": "IAMReadAccess",
      "Effect": "Allow",
      "Action": [
        "iam:GetRole",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMRoleManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:UpdateRole",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:TagRole",
        "iam:UntagRole"
      ],
      "Resource": "arn:aws:iam::*:role/terraform-*"
    },
    {
      "Sid": "S3StateAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::<COMPANY_NAME>-tfstate-*",
        "arn:aws:s3:::<COMPANY_NAME>-tfstate-*/*"
      ]
    },
    {
      "Sid": "DynamoDBStateLocking",
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:<REGION>:*:table/terraform-state-locks"
    }
  ]
}
```

**Note:** Adjust permissions based on your specific needs. This is a broad example.

---

## Trust Policy Examples

### Basic Trust Policy

Allows any workflow in the repository:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}
```

### Branch-Restricted Trust Policy

Only allows specific branches:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/main",
            "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/develop",
            "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/release/*"
          ]
        }
      }
    }
  ]
}
```

### Environment-Restricted Trust Policy

Only allows specific GitHub environments:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:environment:production"
        }
      }
    }
  ]
}
```

### Pull Request Trust Policy

Only allows pull request workflows:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:pull_request"
        }
      }
    }
  ]
}
```

---

## Security Best Practices

### 1. Principle of Least Privilege

✅ **Grant only minimum required permissions**

```json
{
  "Sid": "S3ReadOnly",
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:ListBucket"
  ],
  "Resource": [
    "arn:aws:s3:::my-bucket",
    "arn:aws:s3:::my-bucket/*"
  ]
}
```

❌ **Avoid overly broad permissions**

```json
{
  "Sid": "TooPermissive",
  "Effect": "Allow",
  "Action": "s3:*",
  "Resource": "*"
}
```

### 2. Resource-Level Restrictions

Use specific ARNs instead of wildcards:

✅ **Good:**
```json
"Resource": "arn:aws:s3:::my-company-tfstate-*"
```

❌ **Bad:**
```json
"Resource": "*"
```

### 3. Condition Keys for Additional Security

Add conditions to restrict access further:

```json
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:myorg/myrepo:*"
    },
    "IpAddress": {
      "aws:SourceIp": ["192.0.2.0/24", "203.0.113.0/24"]
    }
  }
}
```

### 4. Separate Roles per Environment

Create dedicated roles with scoped permissions:

- **Dev Role**: Full permissions in dev account
- **QA Role**: Full permissions in qa account
- **Prod Role**: Restricted permissions, require approval workflows

### 5. Regular Audit and Rotation

```bash
# List all OIDC providers
aws iam list-open-id-connect-providers

# Check role trust relationships
aws iam get-role --role-name github-actions-terraform-dev

# Review CloudTrail logs
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity
```

### 6. Enable CloudTrail Logging

Monitor all OIDC authentication attempts:

```bash
aws cloudtrail create-trail \
  --name github-actions-audit \
  --s3-bucket-name my-cloudtrail-logs \
  --include-global-service-events \
  --is-multi-region-trail
```

---

## Policy Testing

### Test IAM Policy Simulator

Use AWS IAM Policy Simulator to test policies before deploying:

1. Go to **IAM Console** → **Policy Simulator**
2. Select your role
3. Test specific actions against resources

### CLI Testing

```bash
# Simulate policy
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:role/github-actions-terraform-dev \
  --action-names s3:PutObject \
  --resource-arns arn:aws:s3:::my-bucket/test.txt
```

---

## Common Policy Patterns

### Pattern 1: Read-Only Access

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket",
        "dynamodb:GetItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ],
      "Resource": "*"
    }
  ]
}
```

### Pattern 2: Deploy-Only Access

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "lambda:UpdateFunctionCode",
        "ecs:UpdateService"
      ],
      "Resource": "*"
    }
  ]
}
```

### Pattern 3: Full Infrastructure Management

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:*",
        "dynamodb:*",
        "lambda:*",
        "ec2:*",
        "iam:*Role*",
        "cloudformation:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "eu-west-1"
        }
      }
    }
  ]
}
```

---

## References

- [AWS IAM Policy Reference](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies.html)
- [AWS IAM Policy Examples](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_examples.html)
- [GitHub OIDC Claims](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#understanding-the-oidc-token)

---

## Summary

**Key Takeaways:**

1. Use specific resource ARNs whenever possible
2. Implement least privilege principle
3. Separate roles per environment
4. Add conditions to trust policies for additional security
5. Monitor and audit role usage regularly

🔒 Properly configured IAM policies are critical for secure OIDC authentication!
