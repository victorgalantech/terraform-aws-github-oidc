# CloudTrail Setup for OIDC Monitoring

This guide walks you through setting up AWS CloudTrail to monitor and audit GitHub Actions OIDC authentication and activities.

## 📋 Table of Contents

- [Why CloudTrail?](#why-cloudtrail)
- [Prerequisites](#prerequisites)
- [Step 1: Create S3 Bucket for CloudTrail Logs](#step-1-create-s3-bucket-for-cloudtrail-logs)
- [Step 2: Create CloudTrail](#step-2-create-cloudtrail)
- [Step 3: Verify CloudTrail Logging](#step-3-verify-cloudtrail-logging)
- [Step 4: Query OIDC Events](#step-4-query-oidc-events)
- [CloudWatch Logs Integration](#cloudwatch-logs-integration)
- [Troubleshooting](#troubleshooting)

---

## Why CloudTrail?

CloudTrail provides comprehensive audit logging for all OIDC authentication attempts and AWS API calls made by GitHub Actions workflows.

### Benefits

- ✅ **Full audit trail** of all AssumeRoleWithWebIdentity calls
- ✅ **Security monitoring** - detect unauthorized access attempts
- ✅ **Compliance** - meet regulatory requirements for access logging
- ✅ **Debugging** - troubleshoot OIDC authentication issues
- ✅ **Cost tracking** - identify which workflows are using AWS resources

### What CloudTrail Captures

When GitHub Actions uses OIDC to access AWS, CloudTrail logs:
- **AssumeRoleWithWebIdentity** events with GitHub repo/branch/workflow details
- All subsequent AWS API calls made by the workflow
- Source IP addresses
- Timestamps and session durations
- Success/failure status

---

## Prerequisites

- Completed [OIDC_SETUP_GUIDE.md](OIDC_SETUP_GUIDE.md) Step 1 (bootstrap-dev user with CloudTrail permissions)
- AWS CLI configured with `bootstrap-dev` profile
- S3 bucket naming convention decided (e.g., `cloudtrail-logs-<account-id>-<region>`)

---

## Step 1: Create S3 Bucket for CloudTrail Logs

CloudTrail requires an S3 bucket to store log files.

### Option 1: AWS Console

1. Go to **S3 Console** → **Create bucket**
2. Bucket name: `cloudtrail-logs-<your-account-id>-<region>`
   - Example: `cloudtrail-logs-002332700133-eu-west-1`
3. Region: Select your primary region (e.g., `eu-west-1`)
4. **Block Public Access**: Keep all settings **enabled** (recommended)
5. **Bucket Versioning**: Enable (optional, for additional protection)
6. **Encryption**: Enable with SSE-S3 or SSE-KMS
7. Click **Create bucket**

### Option 2: AWS CLI

```bash
# Set variables
export AWS_PROFILE=bootstrap-dev
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="eu-west-1"
BUCKET_NAME="cloudtrail-logs-${ACCOUNT_ID}-${REGION}"

echo "Creating bucket: $BUCKET_NAME"

# Create bucket
aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region $REGION \
  --create-bucket-configuration LocationConstraint=$REGION

# Enable versioning (optional)
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# Block public access
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

### Set Bucket Policy for CloudTrail

CloudTrail needs permission to write to the S3 bucket:

```bash
# Create bucket policy file
cat > cloudtrail-bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSCloudTrailAclCheck",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}"
    },
    {
      "Sid": "AWSCloudTrailWrite",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/AWSLogs/${ACCOUNT_ID}/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control"
        }
      }
    }
  ]
}
EOF

# Apply bucket policy
aws s3api put-bucket-policy \
  --bucket $BUCKET_NAME \
  --policy file://cloudtrail-bucket-policy.json
```

---

## Step 2: Create CloudTrail

### Option 1: AWS Console

1. Go to **CloudTrail Console** → **Create trail**
2. Trail name: `github-actions-oidc-audit`
3. **Storage location**:
   - Select **Use existing S3 bucket**
   - Choose the bucket created in Step 1
4. **Log file SSE-KMS encryption**: Optional (leave disabled for simplicity)
5. **CloudWatch Logs**: Optional (see [CloudWatch Integration](#cloudwatch-logs-integration))
6. **Management events**: Enable **Read** and **Write**
7. Click **Next** → **Create trail**

### Option 2: AWS CLI

```bash
# Create CloudTrail
aws cloudtrail create-trail \
  --name github-actions-oidc-audit \
  --s3-bucket-name $BUCKET_NAME \
  --is-multi-region-trail \
  --include-global-service-events \
  --enable-log-file-validation

# Start logging
aws cloudtrail start-logging \
  --name github-actions-oidc-audit

# Verify trail status
aws cloudtrail get-trail-status \
  --name github-actions-oidc-audit
```

**Expected output:**
```json
{
    "IsLogging": true,
    "LatestDeliveryTime": 1234567890.0,
    "StartLoggingTime": 1234567890.0
}
```

---

## Step 3: Verify CloudTrail Logging

Wait 5-15 minutes for CloudTrail to start logging, then verify:

### Check S3 Bucket

```bash
# List CloudTrail logs
aws s3 ls s3://$BUCKET_NAME/AWSLogs/$ACCOUNT_ID/CloudTrail/ --recursive

# Example output:
# 2026-01-07 20:00:00  12345 AWSLogs/123456789012/CloudTrail/eu-west-1/2026/01/07/...
```

### Check CloudTrail Console

1. Go to **CloudTrail Console** → **Trails**
2. Click on `github-actions-oidc-audit`
3. Verify **Logging** status is **ON**
4. Check **Latest delivery** timestamp

---

## Step 4: Query OIDC Events

### View AssumeRoleWithWebIdentity Events

These events occur when GitHub Actions uses OIDC to authenticate:

```bash
# Query last 5 OIDC authentication events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --region us-east-1 \
  --profile bootstrap-dev \
  --max-results 5 \
  --query 'Events[*].[EventTime,Username,EventName]' \
  --output table
```

### View Detailed Event Information

```bash
# Get full details of the most recent OIDC event
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --region us-east-1 \
  --profile bootstrap-dev \
  --max-results 1 \
  --query 'Events[0].CloudTrailEvent' \
  --output text | jq .
```

**Example output:**
```json
{
  "eventVersion": "1.08",
  "userIdentity": {
    "type": "WebIdentityUser",
    "principalId": "arn:aws:sts::123456789012:assumed-role/github-actions-terraform-dev/GitHubActions-123456",
    "userName": "GitHubActions-123456",
    "identityProvider": "token.actions.githubusercontent.com"
  },
  "eventTime": "2026-01-07T20:30:00Z",
  "eventName": "AssumeRoleWithWebIdentity",
  "sourceIPAddress": "192.0.2.1",
  "userAgent": "aws-actions/configure-aws-credentials",
  "requestParameters": {
    "roleArn": "arn:aws:iam::123456789012:role/github-actions-terraform-dev",
    "roleSessionName": "GitHubActions-123456"
  },
  "responseElements": {
    "credentials": {
      "sessionToken": "REDACTED",
      "expiration": "Jan 7, 2026, 9:30:00 PM"
    }
  }
}
```

### Filter Events by Time Range

```bash
# Query events from last 7 days
START_TIME=$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S)
echo "Querying events since: $START_TIME"

aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --start-time $START_TIME \
  --region us-east-1 \
  --profile bootstrap-dev \
  --max-results 50
```

### Query All Events by GitHub Actions Role

```bash
# View all API calls made by GitHub Actions
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=github-actions-terraform-dev \
  --region us-east-1 \
  --profile bootstrap-dev \
  --max-results 20 \
  --query 'Events[*].[EventTime,EventName,Resources[0].ResourceName]' \
  --output table
```

---

## CloudWatch Logs Integration

For real-time monitoring and alerting, send CloudTrail logs to CloudWatch:

### Enable CloudWatch Logs

```bash
# Create CloudWatch log group
aws logs create-log-group \
  --log-group-name /aws/cloudtrail/github-actions-oidc \
  --profile bootstrap-dev

# Create IAM role for CloudTrail to write to CloudWatch
cat > cloudtrail-cloudwatch-role.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name CloudTrailToCloudWatchLogsRole \
  --assume-role-policy-document file://cloudtrail-cloudwatch-role.json \
  --profile bootstrap-dev

# Attach policy to role
cat > cloudtrail-cloudwatch-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:/aws/cloudtrail/github-actions-oidc:*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name CloudTrailToCloudWatchLogsRole \
  --policy-name CloudTrailToCloudWatchLogsPolicy \
  --policy-document file://cloudtrail-cloudwatch-policy.json \
  --profile bootstrap-dev

# Update CloudTrail to use CloudWatch Logs
ROLE_ARN=$(aws iam get-role --role-name CloudTrailToCloudWatchLogsRole --query 'Role.Arn' --output text --profile bootstrap-dev)

aws cloudtrail update-trail \
  --name github-actions-oidc-audit \
  --cloud-watch-logs-log-group-arn "arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:/aws/cloudtrail/github-actions-oidc:*" \
  --cloud-watch-logs-role-arn $ROLE_ARN \
  --profile bootstrap-dev
```

### Create CloudWatch Alarm for Failed OIDC Attempts

```bash
# Create metric filter for failed AssumeRole attempts
aws logs put-metric-filter \
  --log-group-name /aws/cloudtrail/github-actions-oidc \
  --filter-name FailedOIDCAuthentication \
  --filter-pattern '{ $.eventName = "AssumeRoleWithWebIdentity" && $.errorCode = "*" }' \
  --metric-transformations \
    metricName=FailedOIDCAttempts,metricNamespace=GitHubActions,metricValue=1 \
  --profile bootstrap-dev

# Create alarm
aws cloudwatch put-metric-alarm \
  --alarm-name github-actions-oidc-failures \
  --alarm-description "Alert on failed OIDC authentication attempts" \
  --metric-name FailedOIDCAttempts \
  --namespace GitHubActions \
  --statistic Sum \
  --period 300 \
  --threshold 3 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --profile bootstrap-dev
```

---

## Troubleshooting

### CloudTrail Not Logging

**Issue**: No logs appearing in S3 bucket

**Solutions:**
1. Verify trail is logging:
   ```bash
   aws cloudtrail get-trail-status --name github-actions-oidc-audit
   ```
2. Check S3 bucket policy allows CloudTrail writes
3. Wait 15 minutes - CloudTrail can have delays
4. Verify trail is in the correct region

### Cannot Find OIDC Events

**Issue**: `lookup-events` returns no AssumeRoleWithWebIdentity events

**Solutions:**
1. Ensure you're querying **us-east-1** region (global events):
   ```bash
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
     --region us-east-1
   ```
2. Verify GitHub Actions workflow has run recently
3. Check if OIDC authentication succeeded in GitHub Actions logs

### Access Denied When Querying

**Issue**: `AccessDenied` when running CloudTrail commands

**Solution**: Verify `bootstrap-dev` user has CloudTrail permissions (see [OIDC_SETUP_GUIDE.md](OIDC_SETUP_GUIDE.md) Step 1)

---

## Security Best Practices

### 1. Enable Log File Validation

Prevents tampering with CloudTrail logs:

```bash
aws cloudtrail update-trail \
  --name github-actions-oidc-audit \
  --enable-log-file-validation
```

### 2. Restrict S3 Bucket Access

Ensure only CloudTrail and authorized users can access logs:

```bash
# Review bucket policy
aws s3api get-bucket-policy --bucket $BUCKET_NAME
```

### 3. Enable MFA Delete

Prevent accidental or malicious deletion of logs:

```bash
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled,MFADelete=Enabled \
  --mfa "arn:aws:iam::123456789012:mfa/root-account-mfa-device XXXXXX"
```

### 4. Set S3 Lifecycle Rules

Archive old logs to Glacier to reduce costs:

```bash
cat > lifecycle-policy.json <<EOF
{
  "Rules": [
    {
      "Id": "ArchiveOldLogs",
      "Status": "Enabled",
      "Transitions": [
        {
          "Days": 90,
          "StorageClass": "GLACIER"
        }
      ],
      "Expiration": {
        "Days": 2555
      }
    }
  ]
}
EOF

aws s3api put-bucket-lifecycle-configuration \
  --bucket $BUCKET_NAME \
  --lifecycle-configuration file://lifecycle-policy.json
```

### 5. Regular Audit Reviews

Schedule monthly reviews of CloudTrail logs:

```bash
# Create script for monthly audit
cat > monthly-audit.sh <<'EOF'
#!/bin/bash
MONTH_AGO=$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%S)

echo "=== OIDC Authentication Summary (Last 30 Days) ==="
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --start-time $MONTH_AGO \
  --region us-east-1 \
  --query 'length(Events)' \
  --output text

echo "=== Failed Attempts ==="
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --start-time $MONTH_AGO \
  --region us-east-1 \
  --query 'Events[?errorCode!=`null`].[EventTime,errorCode,errorMessage]' \
  --output table
EOF

chmod +x monthly-audit.sh
```

---

## Cost Optimization

CloudTrail costs are based on:
- **Data events**: Charged per event (optional, not covered in this guide)
- **S3 storage**: Standard S3 pricing
- **CloudWatch Logs**: Ingestion and storage costs

### Estimated Costs (Per Month)

| Component | Usage | Estimated Cost |
|-----------|-------|----------------|
| CloudTrail (management events) | First trail free | $0 |
| S3 storage (10 GB) | ~10 GB logs | ~$0.23 |
| CloudWatch Logs (optional) | 5 GB ingestion | ~$2.50 |
| **Total** | | **~$2.73/month** |

### Cost Reduction Tips

1. **Archive to Glacier** after 90 days (90% cost reduction)
2. **Skip CloudWatch Logs** if not needed for real-time monitoring
3. **Filter events** to only log critical actions (advanced setup)

---

## References

- [AWS CloudTrail Documentation](https://docs.aws.amazon.com/cloudtrail/)
- [CloudTrail Log File Examples](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-log-file-examples.html)
- [Monitoring CloudTrail with CloudWatch](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/monitor-cloudtrail-log-files-with-cloudwatch-logs.html)

---

## Summary

**You now have:**
- ✅ CloudTrail logging all OIDC authentication attempts
- ✅ Audit trail of all GitHub Actions AWS API calls
- ✅ Ability to query and investigate security events
- ✅ Optional real-time monitoring with CloudWatch

**Next Steps:**
1. Return to [OIDC_SETUP_GUIDE.md](OIDC_SETUP_GUIDE.md) to continue OIDC setup
2. Test your setup by triggering a GitHub Actions workflow
3. Query CloudTrail to verify OIDC events are logged

🔒 **Your GitHub Actions OIDC authentication is now fully auditable!**
