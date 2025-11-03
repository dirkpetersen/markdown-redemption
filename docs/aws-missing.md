# AWS Lambda Deployment - Permission Issues Report

**Deployment Date**: 2025-11-02
**AWS Profile Attempted**: sue-lambda (primary), iam-dirk (fallback)
**Function Name**: markdown-redemption
**Domain**: markdown.osu.internetchen.de
**Region**: us-east-1

---

## Deployment Summary

### ✅ Successful Steps

1. **Deployment Package Created**: 33MB Lambda deployment package built successfully
   - Location: `lambda-deployment.zip`
   - Method: pip with platform targeting (Docker not available)
   - All Python dependencies installed successfully

2. **IAM Role Created**: `markdown-redemption-execution-role`
   - ARN: `arn:aws:iam::405644541454:role/markdown-redemption-execution-role`
   - Trust policy configured for lambda.amazonaws.com
   - AWSLambdaBasicExecutionRole policy attached

### ❌ Failed Steps

3. **Lambda Function Creation**: BLOCKED
   - Error: `AccessDeniedException`
   - User: `arn:aws:iam::405644541454:user/iam-dirk`
   - Missing Permission: `lambda:CreateFunction`
   - Both sue-lambda and iam-dirk profiles lack this permission

### ⏸️ Not Attempted

4. Lambda Function URL configuration
5. ACM certificate request
6. CloudFront distribution creation
7. Route 53 DNS configuration

---

## Permission Issues Discovered

### Issue 1: sue-lambda Profile - AssumeRole Failure

**Error**: User `arn:aws:iam::405644541454:user/sue-mgr` is not authorized to perform `sts:AssumeRole` on resource `arn:aws:iam::405644541454:role/iam-sorry-sue-lambda`

**Impact**: Cannot use sue-lambda profile at all

**Required Fix**: Grant sue-mgr user permission to assume the role, OR fix the profile configuration to use direct credentials

### Issue 2: iam-dirk Profile - Missing Lambda Permissions

**Error**: User `arn:aws:iam::405644541454:user/iam-dirk` is not authorized to perform `lambda:CreateFunction`

**Impact**: Cannot create Lambda functions despite having IAM permissions

**Required Fix**: Add Lambda permissions to iam-dirk user's policy

---

## Missing Permissions for sue-lambda Policy

The current sue-lambda policy (`iam-sorry-sue-lambda` role) appears to be correctly configured based on the policy JSON provided, which includes:

```json
{
  "Sid": "LambdaFunctionManagement",
  "Action": [
    "lambda:CreateFunction",
    ...
  ]
}
```

**However**, the sue-mgr user cannot assume this role. The issue is with the **trust relationship** or the **user's permissions to assume roles**.

### Required Fix for sue-mgr User

Add this policy to the sue-mgr user:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AssumeDeploymentRole",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::405644541454:role/iam-sorry-sue-lambda"
    }
  ]
}
```

---

## Required Permissions for iam-dirk User

The iam-dirk user needs a comprehensive IAM policy for Lambda deployments:

### Complete IAM Policy for iam-dirk

**Policy Name**: `lambda-deployment-full-access`

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
        "lambda:ListVersionsByFunction",
        "lambda:PublishVersion",
        "lambda:CreateAlias",
        "lambda:UpdateAlias",
        "lambda:DeleteAlias",
        "lambda:GetAlias",
        "lambda:ListAliases",
        "lambda:AddPermission",
        "lambda:RemovePermission",
        "lambda:GetPolicy",
        "lambda:PutFunctionConcurrency",
        "lambda:DeleteFunctionConcurrency",
        "lambda:TagResource",
        "lambda:UntagResource",
        "lambda:ListTags",
        "lambda:CreateFunctionUrlConfig",
        "lambda:DeleteFunctionUrlConfig",
        "lambda:UpdateFunctionUrlConfig",
        "lambda:GetFunctionUrlConfig"
      ],
      "Resource": "arn:aws:lambda:*:405644541454:function:*"
    },
    {
      "Sid": "LambdaServiceOperations",
      "Effect": "Allow",
      "Action": [
        "lambda:ListFunctions"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMRoleManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:GetRole",
        "iam:AttachRolePolicy",
        "iam:PassRole",
        "iam:ListRoles",
        "iam:ListRolePolicies",
        "iam:GetRolePolicy"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudFrontManagement",
      "Effect": "Allow",
      "Action": [
        "cloudfront:CreateDistribution",
        "cloudfront:UpdateDistribution",
        "cloudfront:DeleteDistribution",
        "cloudfront:GetDistribution",
        "cloudfront:GetDistributionConfig",
        "cloudfront:ListDistributions",
        "cloudfront:CreateInvalidation",
        "cloudfront:GetInvalidation",
        "cloudfront:ListInvalidations",
        "cloudfront:TagResource",
        "cloudfront:UntagResource",
        "cloudfront:ListTagsForResource",
        "cloudfront:CreateOriginAccessControl",
        "cloudfront:GetOriginAccessControl",
        "cloudfront:DeleteOriginAccessControl",
        "cloudfront:UpdateOriginAccessControl"
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
        "acm:ListTagsForCertificate",
        "acm:RemoveTagsFromCertificate"
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
        "route53:GetChange"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogsAccess",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "arn:aws:logs:*:405644541454:log-group:/aws/lambda/*"
    }
  ]
}
```

---

## Recommended Actions

### Option 1: Fix sue-lambda Profile (Preferred)

1. Add AssumeRole permission to sue-mgr user (policy above)
2. Verify trust relationship on iam-sorry-sue-lambda role allows sue-mgr to assume it
3. Re-run deployment: `./deploy-to-lambda.sh sue-lambda`

### Option 2: Grant Permissions to iam-dirk User

1. Attach the complete policy above to iam-dirk user
2. Re-run deployment: `./deploy-to-lambda.sh iam-dirk`

### Option 3: Create New Deployment User

1. Create a new IAM user specifically for Lambda deployments
2. Attach the complete policy above
3. Configure AWS CLI profile
4. Run deployment with new profile

---

## Resources Already Created

These resources were successfully created and don't need to be recreated:

1. **IAM Role**: `markdown-redemption-execution-role`
   - Can be reused by future deployment attempts
   - Has correct permissions for Lambda execution

2. **Deployment Package**: `lambda-deployment.zip` (33MB)
   - Ready for Lambda upload
   - Contains all application code and dependencies

---

## Next Steps to Complete Deployment

Once permissions are fixed, the deployment script will:

1. ✅ Create Lambda function with deployment package
2. ⏭️ Configure Lambda Function URL with CORS
3. ⏭️ Request ACM certificate for markdown.osu.internetchen.de
4. ⏭️ Create Route 53 CNAME records for certificate validation
5. ⏭️ Wait for certificate validation (~5-30 minutes)
6. ⏭️ Create CloudFront distribution with custom domain
7. ⏭️ Create Route 53 A/AAAA records pointing to CloudFront
8. ⏭️ Wait for CloudFront deployment (~10-15 minutes)
9. ⏭️ Test HTTPS endpoint at https://markdown.osu.internetchen.de

**Estimated Total Time**: 15-45 minutes after permissions are fixed

---

## Manual Completion (Alternative)

If you prefer to complete the deployment manually via AWS Console:

1. **Upload Lambda Function**:
   - Go to Lambda console → Create function
   - Name: markdown-redemption
   - Runtime: Python 3.12
   - Role: markdown-redemption-execution-role (existing)
   - Upload lambda-deployment.zip
   - Set timeout: 900 seconds (15 min)
   - Set memory: 2048 MB
   - Set ephemeral storage: 10240 MB

2. **Configure Function URL**:
   - Function → Configuration → Function URL
   - Auth type: NONE
   - Enable CORS

3. **Request ACM Certificate**:
   - ACM console (us-east-1 region) → Request certificate
   - Domain: markdown.osu.internetchen.de
   - Validation: DNS
   - Add CNAME record to Route 53 hosted zone

4. **Create CloudFront Distribution**:
   - Origin: Lambda Function URL
   - Alternate domain: markdown.osu.internetchen.de
   - SSL certificate: Select ACM certificate from above
   - Cache behavior: Allow all HTTP methods
   - Forward all headers

5. **Create Route 53 Records**:
   - Type: A (Alias to CloudFront)
   - Name: markdown.osu.internetchen.de
   - Also create AAAA record for IPv6

---

## Contact & Support

For issues with this deployment:
- Review deployment log: `deploy.log`
- Check AWS CloudWatch Logs: `/aws/lambda/markdown-redemption`
- Verify IAM policies in AWS Console
