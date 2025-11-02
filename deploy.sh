#!/bin/bash
set -e

##############################################################################
# AWS Lambda Deployment Script for The Markdown Redemption
#
# This script automates the deployment of the Flask application to AWS Lambda
# with CloudFront and Route 53 DNS configuration.
#
# Prerequisites:
#   - AWS CLI configured with sue profile
#   - sue user has permissions to assume sue-lambda role
#   - All environment variables set (see below)
#
# Usage:
#   ./deploy.sh
#
# Environment Variables (required):
#   LLM_ENDPOINT      - URL to LLM API endpoint
#   LLM_MODEL         - LLM model name
#   AWS_REGION        - AWS region (default: us-east-1)
#   DOMAIN            - Full domain name (default: markdown.osu.internetchen.de)
#   BASE_DOMAIN       - Base domain for Route53 (default: osu.internetchen.de)
#
# Optional Environment Variables:
#   LLM_API_KEY       - LLM API key if required
#   FUNCTION_NAME     - Lambda function name (default: markdown-redemption)
#   AWS_PROFILE       - AWS profile to use (default: default)
##############################################################################

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
DOMAIN="${DOMAIN:-markdown.osu.internetchen.de}"
BASE_DOMAIN="${BASE_DOMAIN:-osu.internetchen.de}"
FUNCTION_NAME="${FUNCTION_NAME:-markdown-redemption}"
LAMBDA_ROLE_NAME="${FUNCTION_NAME}-execution-role"
DEPLOYMENT_PACKAGE="lambda-deployment.zip"
DEPLOYMENT_DIR="deployment"
AWS_PROFILE="${AWS_PROFILE:-default}"
AWS_ACCOUNT_ID="405644541454"

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" >&2
    exit 1
}

# Verify prerequisites
log_info "Verifying prerequisites..."

if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found. Please install AWS CLI."
fi

if ! command -v jq &> /dev/null; then
    log_warning "jq not found. Some features may not work. Install with: sudo apt-get install jq"
fi

if [ -z "$LLM_ENDPOINT" ]; then
    log_error "LLM_ENDPOINT environment variable is required"
fi

if [ -z "$LLM_MODEL" ]; then
    log_error "LLM_MODEL environment variable is required"
fi

log_success "Prerequisites verified"

# Step 1: Assume the sue-lambda role
log_info "Assuming sue-lambda role..."

CREDENTIALS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/sue-lambda \
  --role-session-name markdown-redemption-deployment-$(date +%s) \
  --duration-seconds 3600 \
  --output json 2>/dev/null || {
    log_error "Failed to assume sue-lambda role. Verify sue user has permission to assume this role."
  })

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.Credentials.SessionToken')

ASSUMED_ROLE=$(aws sts get-caller-identity --query 'Arn' --output text)
log_success "Assumed role: $ASSUMED_ROLE"

# Step 2: Build deployment package
log_info "Building deployment package..."

# Create deployment directory
rm -rf "$DEPLOYMENT_DIR"
mkdir -p "$DEPLOYMENT_DIR"
cd "$DEPLOYMENT_DIR"

# Copy application files
cp ../app.py .
cp ../lambda_handler.py .
cp -r ../templates .
cp -r ../static .

# Create requirements file
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

# Install dependencies
log_info "Installing Python dependencies..."
pip install -q -r requirements.txt -t . 2>/dev/null

# Create deployment ZIP
log_info "Creating deployment ZIP..."
zip -qr "../$DEPLOYMENT_PACKAGE" . -x "*.git*" "*.pyc" "__pycache__/*"

cd ..
log_success "Deployment package created: $DEPLOYMENT_PACKAGE"

# Verify package size
PACKAGE_SIZE=$(du -h "$DEPLOYMENT_PACKAGE" | cut -f1)
log_info "Package size: $PACKAGE_SIZE"

if [ $(stat -f%z "$DEPLOYMENT_PACKAGE" 2>/dev/null || stat -c%s "$DEPLOYMENT_PACKAGE" 2>/dev/null) -gt 52428800 ]; then
    log_warning "Deployment package exceeds 50MB. Lambda has a 50MB upload limit."
fi

# Step 3: Create or update Lambda execution role
log_info "Setting up Lambda execution role..."

EXEC_ROLE_ARN=$(aws iam get-role \
  --role-name "$LAMBDA_ROLE_NAME" \
  --query 'Role.Arn' \
  --output text 2>/dev/null) || {
    log_info "Creating Lambda execution role: $LAMBDA_ROLE_NAME"
    EXEC_ROLE_ARN=$(aws iam create-role \
      --role-name "$LAMBDA_ROLE_NAME" \
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
      }' \
      --query 'Role.Arn' \
      --output text)

    # Attach basic execution policy
    aws iam attach-role-policy \
      --role-name "$LAMBDA_ROLE_NAME" \
      --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

    # Wait for role to propagate
    sleep 5
}

log_success "Lambda execution role: $EXEC_ROLE_ARN"

# Step 4: Create or update Lambda function
log_info "Deploying Lambda function..."

FUNCTION_EXISTS=$(aws lambda get-function \
  --function-name "$FUNCTION_NAME" \
  --query 'Configuration.FunctionName' \
  --output text 2>/dev/null) || {
    FUNCTION_EXISTS=""
  }

if [ -z "$FUNCTION_EXISTS" ]; then
    log_info "Creating Lambda function: $FUNCTION_NAME"
    aws lambda create-function \
      --function-name "$FUNCTION_NAME" \
      --runtime python3.11 \
      --role "$EXEC_ROLE_ARN" \
      --handler lambda_handler.lambda_handler \
      --zip-file "fileb://$DEPLOYMENT_PACKAGE" \
      --timeout 900 \
      --memory-size 2048 \
      --ephemeral-storage Size=10240 \
      --environment "Variables={
        LLM_ENDPOINT=$LLM_ENDPOINT,
        LLM_MODEL=$LLM_MODEL,
        LLM_API_KEY=${LLM_API_KEY:-},
        FLASK_ENV=production,
        DEBUG=False,
        MAX_UPLOAD_SIZE=104857600,
        CLEANUP_HOURS=24
      }" \
      --query 'FunctionArn' \
      --output text > /dev/null
else
    log_info "Updating Lambda function code..."
    aws lambda update-function-code \
      --function-name "$FUNCTION_NAME" \
      --zip-file "fileb://$DEPLOYMENT_PACKAGE" > /dev/null

    log_info "Updating Lambda function configuration..."
    aws lambda update-function-configuration \
      --function-name "$FUNCTION_NAME" \
      --timeout 900 \
      --memory-size 2048 \
      --environment "Variables={
        LLM_ENDPOINT=$LLM_ENDPOINT,
        LLM_MODEL=$LLM_MODEL,
        LLM_API_KEY=${LLM_API_KEY:-},
        FLASK_ENV=production,
        DEBUG=False,
        MAX_UPLOAD_SIZE=104857600,
        CLEANUP_HOURS=24
      }" > /dev/null
fi

log_success "Lambda function deployed: $FUNCTION_NAME"

# Step 5: Create Function URL
log_info "Configuring Lambda Function URL..."

FUNCTION_URL=$(aws lambda get-function-url-config \
  --function-name "$FUNCTION_NAME" \
  --query 'FunctionUrl' \
  --output text 2>/dev/null) || {
    log_info "Creating Lambda Function URL..."
    FUNCTION_URL=$(aws lambda create-function-url-config \
      --function-name "$FUNCTION_NAME" \
      --auth-type NONE \
      --cors '{
        "AllowOrigins": ["*"],
        "AllowMethods": ["GET", "POST"],
        "AllowHeaders": ["Content-Type"],
        "MaxAge": 86400
      }' \
      --query 'FunctionUrl' \
      --output text)
  }

log_success "Function URL: $FUNCTION_URL"

# Step 6: Test Lambda function
log_info "Testing Lambda function..."

TEST_RESULT=$(aws lambda invoke \
  --function-name "$FUNCTION_NAME" \
  --payload '{"requestContext": {"http": {"method": "GET", "path": "/"}}}' \
  /tmp/lambda-test-response.json 2>&1)

if grep -q "200" /tmp/lambda-test-response.json 2>/dev/null || grep -q "statusCode" /tmp/lambda-test-response.json 2>/dev/null; then
    log_success "Lambda function test passed"
else
    log_warning "Lambda function test result: $(cat /tmp/lambda-test-response.json | head -c 200)"
fi

# Step 7: Request ACM Certificate
log_info "Setting up ACM certificate for HTTPS..."

CERT_ARN=$(aws acm list-certificates \
  --query "CertificateSummaryList[?DomainName=='$DOMAIN'].CertificateArn" \
  --output text 2>/dev/null | head -1) || {
    CERT_ARN=""
  }

if [ -z "$CERT_ARN" ]; then
    log_info "Requesting ACM certificate for $DOMAIN..."
    CERT_ARN=$(aws acm request-certificate \
      --domain-name "$DOMAIN" \
      --subject-alternative-names "www.$DOMAIN" \
      --validation-method DNS \
      --query 'CertificateArn' \
      --output text)

    log_warning "Certificate requested. Status: pending validation"
    log_warning "Check ACM console to validate certificate: $CERT_ARN"
else
    CERT_STATUS=$(aws acm describe-certificate \
      --certificate-arn "$CERT_ARN" \
      --query 'Certificate.Status' \
      --output text)
    log_info "Using existing certificate (Status: $CERT_STATUS)"
fi

log_success "Certificate ARN: $CERT_ARN"

# Step 8: Create CloudFront distribution
log_info "Setting up CloudFront distribution..."

# Extract Lambda domain from Function URL
LAMBDA_DOMAIN=$(echo "$FUNCTION_URL" | sed 's|https://||' | sed 's|/||g')

# Check if distribution already exists
DIST_ID=$(aws cloudfront list-distributions \
  --query "Distributions[?Aliases.Items[?contains(@, '$DOMAIN')]].Id" \
  --output text 2>/dev/null | head -1) || {
    DIST_ID=""
  }

if [ -z "$DIST_ID" ]; then
    log_info "Creating CloudFront distribution..."

    DIST_ID=$(aws cloudfront create-distribution \
      --origin-domain-name "$LAMBDA_DOMAIN" \
      --default-cache-behavior '{
        "TargetOriginId": "LambdaOrigin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
        "CachedMethods": ["GET", "HEAD"],
        "Compress": true,
        "ForwardedValues": {
          "QueryString": true,
          "Headers": {
            "Quantity": 0
          },
          "Cookies": {
            "Forward": "all"
          }
        },
        "MinTTL": 0,
        "DefaultTTL": 0,
        "MaxTTL": 0
      }' \
      --query 'Distribution.Id' \
      --output text)

    log_warning "CloudFront distribution created. Please wait for deployment (typically 10-15 minutes)"
else
    log_info "Using existing CloudFront distribution: $DIST_ID"
fi

log_success "CloudFront Distribution ID: $DIST_ID"

# Step 9: Configure Route 53
log_info "Configuring Route 53 DNS..."

# Get hosted zone ID
ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name "$BASE_DOMAIN" \
  --query 'HostedZones[0].Id' \
  --output text 2>/dev/null | cut -d/ -f3) || {
    log_warning "Could not find hosted zone for $BASE_DOMAIN"
    ZONE_ID=""
  }

if [ -n "$ZONE_ID" ]; then
    # Get CloudFront distribution domain
    DIST_DOMAIN=$(aws cloudfront get-distribution \
      --id "$DIST_ID" \
      --query 'Distribution.DomainName' \
      --output text)

    log_info "Creating Route 53 CNAME record: $DOMAIN -> $DIST_DOMAIN"

    aws route53 change-resource-record-sets \
      --hosted-zone-id "$ZONE_ID" \
      --change-batch "{
        \"Changes\": [
          {
            \"Action\": \"UPSERT\",
            \"ResourceRecordSet\": {
              \"Name\": \"$DOMAIN\",
              \"Type\": \"CNAME\",
              \"TTL\": 300,
              \"ResourceRecords\": [
                {
                  \"Value\": \"$DIST_DOMAIN\"
                }
              ]
            }
          }
        ]
      }" > /dev/null

    log_success "DNS record configured"
else
    log_warning "Skipping Route 53 configuration - hosted zone not found"
fi

# Step 10: Cleanup and summary
log_info "Cleaning up..."
rm -rf "$DEPLOYMENT_DIR"

log_success "Deployment complete!"
echo ""
echo -e "${GREEN}=== Deployment Summary ===${NC}"
echo "Function Name: $FUNCTION_NAME"
echo "Function URL: $FUNCTION_URL"
echo "CloudFront Distribution: $DIST_ID"
echo "Domain: $DOMAIN"
echo "Region: $AWS_REGION"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Validate ACM certificate (if not already validated)"
echo "2. Wait for CloudFront deployment to complete (~10-15 minutes)"
echo "3. Test the application at: https://$DOMAIN"
echo "4. Monitor logs with: aws logs tail /aws/lambda/$FUNCTION_NAME --follow"
echo ""
echo -e "${BLUE}To clear session credentials when done:${NC}"
echo "  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN"
echo ""

# Cleanup credentials on exit
trap "unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN" EXIT
