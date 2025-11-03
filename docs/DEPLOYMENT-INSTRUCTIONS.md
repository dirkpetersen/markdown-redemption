# AWS Lambda Deployment Instructions for The Markdown Redemption

## Overview

This document provides step-by-step instructions for deploying The Markdown Redemption application to AWS Lambda with proper IAM role separation.

**Key Architecture**:
- `iam-dirk`: Administrator who sets up IAM roles and permissions
- `sue-mgr`: Credential manager for the `sue` user
- `sue`: The actual deployment user who assumes the `sue-lambda` role
- `sue-lambda`: The deployment role with permissions to create Lambda functions and necessary IAM roles

---

## Prerequisites

1. AWS CLI configured with profiles:
   - `iam-dirk`: Has administrative IAM access
   - `sue` or `default`: The deployment profile (will assume sue-lambda role)

2. Required environment variables:
   ```bash
   export LLM_ENDPOINT="your-llm-endpoint-url"
   export LLM_MODEL="your-model-name"
   export LLM_API_KEY="your-api-key"  # if required
   export DOMAIN="markdown.osu.internetchen.de"
   export BASE_DOMAIN="osu.internetchen.de"
   ```

---

## Step 1: Admin Setup (iam-dirk Profile Only)

**ONLY the iam-dirk administrator should perform these steps.**

### 1.1 Create the sue-lambda Deployment Role

```bash
aws iam create-role \
  --profile iam-dirk \
  --role-name sue-lambda \
  --assume-role-policy-document file://sue-lambda-trust-policy.json \
  --description "Role for sue user to deploy Lambda applications"
```

**Verify role creation:**
```bash
aws iam get-role --profile iam-dirk --role-name sue-lambda
```

### 1.2 Attach Deployment Policy to sue-lambda Role

```bash
aws iam put-role-policy \
  --profile iam-dirk \
  --role-name sue-lambda \
  --policy-name sue-lambda-deployment-policy \
  --policy-document file://sue-lambda-deployment-policy.json
```

**This policy allows sue-lambda to:**
- Create, update, and delete Lambda functions
- Create and manage IAM roles for Lambda execution
- Manage CloudFront distributions
- Request and manage ACM certificates
- Configure Route 53 DNS records
- Write to CloudWatch Logs

### 1.3 Verify Role Setup

```bash
# Get the role ARN for use in deployment
aws iam get-role \
  --profile iam-dirk \
  --role-name sue-lambda \
  --query 'Role.Arn' \
  --output text

# Should output: arn:aws:iam::405644541454:role/sue-lambda
```

---

## Step 2: Deployment with sue User

**The sue user performs the actual deployment.**

### 2.1 Verify AWS Credentials

```bash
aws sts get-caller-identity --profile default
# Or use your configured profile name if different
```

Should show the `sue` user.

### 2.2 Assume the sue-lambda Deployment Role

```bash
# Assume the role and export credentials
CREDENTIALS=$(aws sts assume-role \
  --role-arn arn:aws:iam::405644541454:role/sue-lambda \
  --role-session-name markdown-redemption-deployment \
  --duration-seconds 3600 \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.Credentials.SessionToken')
```

**Verify assumed role:**
```bash
aws sts get-caller-identity
# Should show AssumedRoleUser with path /markdown-redemption-deployment/
```

### 2.3 Set Application Environment Variables

```bash
export LLM_ENDPOINT="http://your-llm-server:11434/v1"
export LLM_MODEL="qwen2.5vl:latest"
export LLM_API_KEY="your-api-key"
export DOMAIN="markdown.osu.internetchen.de"
export BASE_DOMAIN="osu.internetchen.de"
export FUNCTION_NAME="markdown-redemption"
export AWS_REGION="us-east-1"
```

### 2.4 Build the Deployment Package

```bash
# Create deployment directory
mkdir -p deployment
cd deployment

# Copy application files
cp ../app.py .
cp ../lambda_handler.py .
cp -r ../templates .
cp -r ../static .

# Create requirements file for Lambda
cat > requirements.txt << 'EOF'
flask>=3.1.2
python-dotenv==1.1.1
pymupdf4llm>=0.0.17
pymupdf>=1.24.0,<1.27.0
Pillow==10.3.0
requests==2.32.3
Flask-Session==0.8.0
mangum>=0.18.0
EOF

# Install dependencies to local directory
pip install -r requirements.txt -t .

# Create deployment ZIP
zip -r ../lambda-deployment.zip . -x "*.git*" "*.pyc" "__pycache__/*"

cd ..
```

**Verify package size:**
```bash
ls -lh lambda-deployment.zip
# Should be under 50MB (Lambda size limit is 50MB for direct upload)
```

### 2.5 Create Lambda Execution Role

The deployment role can create this role as needed:

```bash
# Create the Lambda execution role (assumes Lambda service)
aws iam create-role \
  --role-name markdown-redemption-execution-role \
  --assume-role-policy-document '{
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
  }'

# Attach basic execution policy
aws iam attach-role-policy \
  --role-name markdown-redemption-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Get the role ARN
EXEC_ROLE_ARN=$(aws iam get-role \
  --role-name markdown-redemption-execution-role \
  --query 'Role.Arn' \
  --output text)

echo "Execution Role ARN: $EXEC_ROLE_ARN"
```

### 2.6 Create Lambda Function

```bash
EXEC_ROLE_ARN=$(aws iam get-role \
  --role-name markdown-redemption-execution-role \
  --query 'Role.Arn' \
  --output text)

aws lambda create-function \
  --function-name markdown-redemption \
  --runtime python3.11 \
  --role "$EXEC_ROLE_ARN" \
  --handler lambda_handler.lambda_handler \
  --zip-file fileb://lambda-deployment.zip \
  --timeout 900 \
  --memory-size 2048 \
  --ephemeral-storage Size=10240 \
  --environment "Variables={
    LLM_ENDPOINT=$LLM_ENDPOINT,
    LLM_MODEL=$LLM_MODEL,
    LLM_API_KEY=$LLM_API_KEY,
    FLASK_ENV=production,
    DEBUG=False,
    MAX_UPLOAD_SIZE=104857600,
    CLEANUP_HOURS=24
  }"
```

**If function already exists, update it:**
```bash
aws lambda update-function-code \
  --function-name markdown-redemption \
  --zip-file fileb://lambda-deployment.zip

aws lambda update-function-configuration \
  --function-name markdown-redemption \
  --timeout 900 \
  --memory-size 2048 \
  --environment "Variables={
    LLM_ENDPOINT=$LLM_ENDPOINT,
    LLM_MODEL=$LLM_MODEL,
    LLM_API_KEY=$LLM_API_KEY,
    FLASK_ENV=production,
    DEBUG=False
  }"
```

### 2.7 Create Function URL

```bash
aws lambda create-function-url-config \
  --function-name markdown-redemption \
  --auth-type NONE \
  --cors '{
    "AllowOrigins": ["*"],
    "AllowMethods": ["GET", "POST"],
    "AllowHeaders": ["Content-Type"],
    "MaxAge": 86400
  }'

# Get the Function URL
FUNCTION_URL=$(aws lambda get-function-url-config \
  --function-name markdown-redemption \
  --query 'FunctionUrl' \
  --output text)

echo "Lambda Function URL: $FUNCTION_URL"
```

### 2.8 Request ACM Certificate

```bash
# Request certificate for your domain
CERT_ARN=$(aws acm request-certificate \
  --domain-name "$DOMAIN" \
  --subject-alternative-names "www.$DOMAIN" \
  --validation-method DNS \
  --query 'CertificateArn' \
  --output text)

echo "Certificate ARN: $CERT_ARN"

# Wait for certificate validation (must be done manually in ACM console or via DNS)
# This typically takes 5-15 minutes
aws acm describe-certificate --certificate-arn "$CERT_ARN"
```

### 2.9 Create CloudFront Distribution

```bash
# Create CloudFront distribution pointing to Lambda Function URL
LAMBDA_DOMAIN=$(echo $FUNCTION_URL | sed 's|https://||' | sed 's|/||g')

aws cloudfront create-distribution \
  --origin-domain-name "$LAMBDA_DOMAIN" \
  --default-root-object index.html \
  --certificate-arn "$CERT_ARN" \
  --domain-name "$DOMAIN" \
  --query 'Distribution.Id' \
  --output text

# Get distribution ID
DISTRIBUTION_ID=$(aws cloudfront list-distributions \
  --query "Distributions[?DomainName=='$DOMAIN'].Id" \
  --output text)

echo "CloudFront Distribution ID: $DISTRIBUTION_ID"
```

### 2.10 Configure Route 53 DNS

```bash
# Get hosted zone ID
ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name "$BASE_DOMAIN" \
  --query 'HostedZones[0].Id' \
  --output text)

# Get CloudFront distribution domain
DISTRIBUTION_DOMAIN=$(aws cloudfront get-distribution \
  --id "$DISTRIBUTION_ID" \
  --query 'Distribution.DomainName' \
  --output text)

# Create Route 53 record
aws route53 change-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --change-batch '{
    "Changes": [
      {
        "Action": "UPSERT",
        "ResourceRecordSet": {
          "Name": "'$DOMAIN'",
          "Type": "CNAME",
          "TTL": 300,
          "ResourceRecords": [
            {
              "Value": "'$DISTRIBUTION_DOMAIN'"
            }
          ]
        }
      }
    ]
  }'

echo "DNS Record Created: $DOMAIN -> $DISTRIBUTION_DOMAIN"
```

---

## Step 3: Verify Deployment

### 3.1 Test Lambda Function

```bash
aws lambda invoke \
  --function-name markdown-redemption \
  --payload '{"requestContext": {"http": {"method": "GET", "path": "/"}}}' \
  response.json

cat response.json
```

### 3.2 Check Function Logs

```bash
aws logs tail /aws/lambda/markdown-redemption --follow --since 5m
```

### 3.3 Test via Function URL

```bash
curl "$FUNCTION_URL"
```

### 3.4 Test via CloudFront Domain

```bash
curl "https://$DOMAIN"
```

---

## Troubleshooting

### Permission Denied Errors

1. Verify sue user can assume sue-lambda role:
   ```bash
   aws sts assume-role --role-arn arn:aws:iam::405644541454:role/sue-lambda --role-session-name test
   ```

2. Check sue-lambda role has correct policy:
   ```bash
   aws iam get-role-policy --role-name sue-lambda --policy-name sue-lambda-deployment-policy
   ```

3. Verify trust relationship:
   ```bash
   aws iam get-role --role-name sue-lambda
   ```

### Lambda Timeout Issues

If conversions are timing out:

1. Increase timeout to 900 seconds (15 minutes - maximum):
   ```bash
   aws lambda update-function-configuration \
     --function-name markdown-redemption \
     --timeout 900
   ```

2. Increase memory to improve CPU:
   ```bash
   aws lambda update-function-configuration \
     --function-name markdown-redemption \
     --memory-size 3008
   ```

3. Check logs for specific errors:
   ```bash
   aws logs tail /aws/lambda/markdown-redemption --follow
   ```

### Function URL Not Responding

1. Verify function URL is created and active:
   ```bash
   aws lambda get-function-url-config --function-name markdown-redemption
   ```

2. Test Lambda function directly:
   ```bash
   aws lambda invoke --function-name markdown-redemption --cli-binary-format raw-in-base64-out response.json
   cat response.json
   ```

### ACM Certificate Issues

1. Manually validate certificate in ACM console (DNS or email validation)
2. Wait for certificate status to be "Issued" before creating CloudFront distribution
3. For DNS validation, add CNAME records shown in ACM console to Route 53

---

## Security Best Practices

1. **Temporary Credentials**: Use role assumption with temporary credentials, not long-term access keys
2. **Session Duration**: Use reasonable session durations (3600 seconds = 1 hour shown in examples)
3. **Least Privilege**: Only attach permissions needed for deployment
4. **Environment Variables**: Never commit .env with sensitive data
5. **CloudTrail Logging**: All actions are logged under the iam-dirk and sue identities
6. **Session Tokens**: Always include AWS_SESSION_TOKEN when using assumed roles

---

## Credential Cleanup

After deployment is complete, clear assumed role credentials:

```bash
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
```

---

## Questions or Issues?

- For IAM role modifications: Contact iam-dirk administrator
- For deployment issues: Check CloudWatch logs with: `aws logs tail /aws/lambda/markdown-redemption --follow`
- For configuration changes: Update environment variables and run `aws lambda update-function-configuration`
