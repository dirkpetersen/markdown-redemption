# Markdown Redemption Lambda Deployment State

## Completed Steps

### 1. IAM Setup (Completed)
- **Date**: 2025-11-02
- **Administrator**: iam-dirk
- **Tasks Completed**:
  - Created `sue-lambda` role
  - Applied deployment policy with Lambda, IAM, CloudFront, ACM, Route53, and Logs permissions
  - Updated trust policy to allow sue-mgr, sue, and dirkcli users to assume the role
  - ✓ Verified: sue profile can successfully assume sue-lambda role

### 2. Deployment Package (Completed)
- **S3 Bucket**: markdown-redemption-1762111769
- **Package**: lambda-deployment.zip (62 MB)
- **Location**: s3://markdown-redemption-1762111769/lambda-deployment.zip
- **Status**: ✓ Uploaded successfully

## Next Steps

### 3. Create Lambda Execution Role
Use assumed role credentials to create the execution role:
```bash
aws iam create-role \
  --role-name markdown-redemption-execution-role \
  --assume-role-policy-document '{...}'
```

### 4. Create Lambda Function
Reference the S3 object:
```bash
aws lambda create-function \
  --function-name markdown-redemption \
  --s3-bucket markdown-redemption-1762111769 \
  --s3-key lambda-deployment.zip \
  --role <EXEC_ROLE_ARN> \
  ...
```

### 5. Configure Function URL
```bash
aws lambda create-function-url-config ...
```

### 6. ACM Certificate
```bash
aws acm request-certificate ...
```

### 7. CloudFront Distribution
```bash
aws cloudfront create-distribution ...
```

### 8. Route 53 DNS
```bash
aws route53 change-resource-record-sets ...
```

## AWS Account Information
- **Account ID**: 405644541454
- **Region**: us-east-1
- **Roles Created**:
  - `sue-lambda`: Deployment role for sue user/sue-mgr credential manager
  - `markdown-redemption-execution-role`: (To be created) Lambda function execution role

## Credentials
**IMPORTANT**: Always use assumed role credentials with session tokens. Never commit AWS credentials to version control.

To assume the deployment role:
```bash
CREDENTIALS=$(aws sts assume-role \
  --profile sue \
  --role-arn arn:aws:iam::405644541454:role/sue-lambda \
  --role-session-name deployment \
  --duration-seconds 3600 \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.Credentials.SessionToken')
```

When done:
```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```
