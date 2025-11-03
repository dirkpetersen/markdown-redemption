# IAM Permissions Guide - The Markdown Redemption

---

## Overview

This document provides complete IAM permission configurations for:
1. **Administrators** - Full deployment and infrastructure management
2. **Deployment Users** - Regular deployments and updates
3. **Lambda Execution** - Runtime permissions for the function

---

## Administrator User: `iam-dirk`

### Purpose
Full AWS account management including creating roles, policies, and deploying infrastructure.

### Attached Policies
1. **AWS Managed Policies**
   - `AdministratorAccess`
   - `IAMFullAccess`

2. **Custom Inline Policies** (see below)

### Inline Policy: `lambda-apigateway-deployment`
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LambdaFunctionManagement",
      "Effect": "Allow",
      "Action": [
        "lambda:CreateFunction",
        "lambda:DeleteFunction",
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:GetFunction",
        "lambda:GetFunctionConfiguration",
        "lambda:ListFunctions",
        "lambda:TagResource",
        "lambda:UntagResource",
        "lambda:ListTags"
      ],
      "Resource": "arn:aws:lambda:us-west-2:405644541454:function:*"
    },
    {
      "Sid": "IAMRoleManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:GetRole",
        "iam:PassRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListRoles",
        "iam:ListRolePolicies",
        "iam:GetRolePolicy",
        "iam:CreateUser",
        "iam:GetUser",
        "iam:ListUsers",
        "iam:AttachUserPolicy",
        "iam:DetachUserPolicy",
        "iam:CreateAccessKey",
        "iam:ListAccessKeys",
        "iam:DeleteAccessKey",
        "iam:ListUserPolicies"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Route53Management",
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:GetHostedZone",
        "route53:ListResourceRecordSets",
        "route53:ChangeResourceRecordSets",
        "route53:GetChange",
        "route53:ListHostedZonesByName"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ACMCertificateManagement",
      "Effect": "Allow",
      "Action": [
        "acm:RequestCertificate",
        "acm:DescribeCertificate",
        "acm:ListCertificates",
        "acm:GetCertificate",
        "acm:DeleteCertificate",
        "acm:AddTagsToCertificate",
        "acm:ListTagsForCertificate"
      ],
      "Resource": "*"
    },
    {
      "Sid": "APIGatewayManagement",
      "Effect": "Allow",
      "Action": [
        "apigateway:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "arn:aws:logs:*:405644541454:log-group:*"
    }
  ]
}
```

### Inline Policy: `s3-lambda-deploy`
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3BucketAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:CreateBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "*"
    }
  ]
}
```

### Inline Policy: `assume-role-policy`
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AssumeRoles",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::405644541454:role/*"
    }
  ]
}
```

---

## Deployment User: `markdown-deployer` (Template)

### Purpose
Regular deployments and updates without full administrative access. Create this user for CI/CD pipelines.

### Creation Commands
```bash
# Create user
aws iam create-user --user-name markdown-deployer

# Create access key
aws iam create-access-key --user-name markdown-deployer

# Save credentials in secure location
```

### Attached Policy: `markdown-deployment-only`
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LambdaUpdateCode",
      "Effect": "Allow",
      "Action": [
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:GetFunction",
        "lambda:GetFunctionConfiguration"
      ],
      "Resource": "arn:aws:lambda:us-west-2:405644541454:function:markdown-redemption"
    },
    {
      "Sid": "S3DeploymentBucket",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::markdown-redemption-usw2-*",
        "arn:aws:s3:::markdown-redemption-usw2-*/*"
      ]
    },
    {
      "Sid": "ViewCloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:GetLogEvents",
        "logs:FilterLogEvents",
        "logs:DescribeLogStreams",
        "logs:DescribeLogGroups"
      ],
      "Resource": "arn:aws:logs:us-west-2:405644541454:log-group:/aws/lambda/markdown-redemption:*"
    },
    {
      "Sid": "GetAPIGatewayInfo",
      "Effect": "Allow",
      "Action": [
        "apigateway:GET"
      ],
      "Resource": "arn:aws:apigateway:us-west-2::/restapis/*"
    }
  ]
}
```

#### AWS CLI Setup for Deployment User
```bash
# Install CLI
aws configure --profile markdown-deployer

# Use for deployments
./deploy.sh --profile markdown-deployer
```

---

## Lambda Execution Role: `markdown-redemption-exec-usw2`

### Purpose
Permissions for the Lambda function itself while executing.

### Trust Relationship (AssumeRole Policy)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### Attached Policies
1. **AWS Managed Policy**: `AWSLambdaBasicExecutionRole`
   - Provides CloudWatch Logs write permissions

### Additional Permissions for Extended Functionality

#### If Using S3 for File Storage
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3FileStorage",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::markdown-results-bucket/*"
    }
  ]
}
```

#### If Using Secrets Manager for LLM API Key
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SecretsManager",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:us-west-2:405644541454:secret:markdown/llm-api-key*"
    }
  ]
}
```

---

## CI/CD Pipeline User: `markdown-ci` (Template)

### Purpose
Automated deployments from GitHub Actions, GitLab CI, or similar.

### Permissions
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LambdaDeployment",
      "Effect": "Allow",
      "Action": [
        "lambda:UpdateFunctionCode",
        "lambda:GetFunction"
      ],
      "Resource": "arn:aws:lambda:us-west-2:405644541454:function:markdown-redemption"
    },
    {
      "Sid": "S3Deployment",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::markdown-redemption-usw2-*",
        "arn:aws:s3:::markdown-redemption-usw2-*/*"
      ]
    }
  ]
}
```

### GitHub Actions Setup
```yaml
# .github/workflows/deploy.yml
name: Deploy to Lambda

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Deploy to Lambda
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-west-2
      - run: bash deploy.sh
```

---

## Permission Audit Checklist

Use this checklist to audit existing permissions:

### Administrator (`iam-dirk`)
- [ ] Can create Lambda functions
- [ ] Can create IAM roles
- [ ] Can manage Route 53 DNS
- [ ] Can request ACM certificates
- [ ] Can create API Gateway endpoints
- [ ] Can upload to S3

### Deployment User (`markdown-deployer`)
- [ ] Can update Lambda function code
- [ ] Can update Lambda configuration
- [ ] Can view CloudWatch Logs
- [ ] Can upload deployment packages to S3
- [ ] Cannot create new resources
- [ ] Cannot delete resources

### Lambda Execution Role (`markdown-redemption-exec-usw2`)
- [ ] Can write to CloudWatch Logs
- [ ] Can access Secrets Manager (if configured)
- [ ] Can read/write to S3 (if configured)
- [ ] Cannot modify Lambda configuration
- [ ] Cannot assume other roles

---

## Minimal Permissions for Development

For local development without AWS access:

```bash
# No AWS permissions needed
# Run locally with:
pip install -r requirements.txt
python app.py
# Access at http://127.0.0.1:5000
```

---

## Permission Update Procedures

### Adding Permissions to Existing User
```bash
# View current policies
aws iam list-user-policies --user-name markdown-deployer

# Create new inline policy
aws iam put-user-policy \
  --user-name markdown-deployer \
  --policy-name additional-permissions \
  --policy-document file://policy.json

# Attach managed policy
aws iam attach-user-policy \
  --user-name markdown-deployer \
  --policy-arn arn:aws:iam::aws:policy/SERVICE-ROLE
```

### Removing Permissions
```bash
# Delete inline policy
aws iam delete-user-policy \
  --user-name markdown-deployer \
  --policy-name policy-name

# Detach managed policy
aws iam detach-user-policy \
  --user-name markdown-deployer \
  --policy-arn arn:aws:iam::aws:policy/POLICY-NAME
```

---

## Troubleshooting Permission Errors

### "Not authorized to perform"
**Solution**: User lacks required action in a policy. Check:
1. Attached managed policies
2. Attached inline policies
3. Resource ARN restrictions
4. Condition statements

```bash
# Check user policies
aws iam list-user-policies --user-name USERNAME
aws iam get-user-policy --user-name USERNAME --policy-name POLICY-NAME

# Check role policies
aws iam list-role-policies --role-name ROLE-NAME
aws iam get-role-policy --role-name ROLE-NAME --policy-name POLICY-NAME
```

### "User is not authorized to perform: sts:AssumeRole"
**Solution**: User needs AssumeRole permission. Add to user policy:
```json
{
  "Effect": "Allow",
  "Action": "sts:AssumeRole",
  "Resource": "arn:aws:iam::ACCOUNT-ID:role/TARGET-ROLE"
}
```

### Access Denied on S3
**Solution**: Check bucket policy AND user policy. User policy must allow action AND bucket policy must not deny it.

---

## Security Best Practices

1. **Use IAM Roles over Long-Term Keys**
   - Prefer temporary credentials via STS AssumeRole
   - Never commit access keys to version control

2. **Follow Least Privilege**
   - Grant only necessary permissions
   - Use resource ARNs to restrict scope
   - Use conditions to further restrict access

3. **Regular Audits**
   - Review permissions quarterly
   - Remove unused users
   - Remove unnecessary policies

4. **Use MFA**
   - Enable MFA for all users
   - Especially for users with deployment permissions

5. **Rotate Credentials**
   - Rotate access keys every 90 days
   - Update GitHub Secrets when rotating

---

## Quick Reference Commands

```bash
# List all users
aws iam list-users

# List policies for a user
aws iam list-user-policies --user-name USERNAME

# View inline policy
aws iam get-user-policy --user-name USERNAME --policy-name POLICY-NAME

# List attached managed policies
aws iam list-attached-user-policies --user-name USERNAME

# Create new user
aws iam create-user --user-name NEW-USER

# Attach policy to user
aws iam attach-user-policy --user-name USERNAME --policy-arn POLICY-ARN

# Create access key
aws iam create-access-key --user-name USERNAME

# List access keys
aws iam list-access-keys --user-name USERNAME

# Delete access key
aws iam delete-access-key --user-name USERNAME --access-key-id AKID
```

---

## Support

For permission issues:
1. Check CloudTrail for specific denied actions
2. Review the error message for missing actions/resources
3. Use IAM Policy Simulator: https://policysim.aws.amazon.com/
4. Consult this guide for complete policy examples

