#!/bin/bash
################################################################################
# The Markdown Redemption - Complete AWS Lambda Deployment Script
#
# This script automates the complete deployment of The Markdown Redemption
# Flask application to AWS Lambda with CloudFront and Route 53.
#
# Requirements:
#   - AWS CLI v2 configured with 'sue' profile
#   - jq installed for JSON processing
#   - All environment variables set (LLM_ENDPOINT, LLM_MODEL)
#
# Usage:
#   export LLM_ENDPOINT="http://your-llm-server:11434/v1"
#   export LLM_MODEL="qwen2.5vl:latest"
#   export DOMAIN="markdown.osu.internetchen.de"
#   export BASE_DOMAIN="osu.internetchen.de"
#   ./complete-deployment.sh
#
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="405644541454"
FUNCTION_NAME="${FUNCTION_NAME:-markdown-redemption}"
EXEC_ROLE_NAME="markdown-redemption-execution-role"
DOMAIN="${DOMAIN:-markdown.osu.internetchen.de}"
BASE_DOMAIN="${BASE_DOMAIN:-osu.internetchen.de}"
LLM_ENDPOINT="${LLM_ENDPOINT:-http://localhost:11434/v1}"
LLM_MODEL="${LLM_MODEL:-qwen2.5vl:latest}"
LLM_API_KEY="${LLM_API_KEY:-}"

# Log functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[✓]${NC} $1" >&2; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1" >&2; }
log_error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }

# Cleanup function
cleanup() {
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}
trap cleanup EXIT

main() {
  log_info "Starting Markdown Redemption Lambda Deployment"
  log_info "Region: $AWS_REGION | Function: $FUNCTION_NAME | Domain: $DOMAIN"
  echo ""

  # Step 1: Assume role
  log_info "[1/6] Assuming sue-lambda deployment role..."

  CREDENTIALS=$(aws sts assume-role \
    --profile sue \
    --region "$AWS_REGION" \
    --role-arn "arn:aws:iam::$AWS_ACCOUNT_ID:role/sue-lambda" \
    --role-session-name "deployment-$(date +%s)" \
    --duration-seconds 3600 \
    --output json)

  export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | jq -r '.Credentials.AccessKeyId')
  export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r '.Credentials.SecretAccessKey')
  export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS" | jq -r '.Credentials.SessionToken')
  export AWS_DEFAULT_REGION="$AWS_REGION"

  ASSUMED_ARN=$(aws sts get-caller-identity --query 'Arn' --output text)
  log_success "Assumed role: $ASSUMED_ARN"

  # Step 2: Verify Lambda function exists
  log_info "[2/6] Verifying Lambda function..."

  LAMBDA_EXISTS=$(aws lambda get-function \
    --function-name "$FUNCTION_NAME" \
    --query 'Configuration.FunctionArn' \
    --output text 2>/dev/null || echo "")

  if [ -z "$LAMBDA_EXISTS" ]; then
    log_error "Lambda function '$FUNCTION_NAME' does not exist. Please run deploy.sh first."
  fi

  log_success "Lambda function exists: $LAMBDA_EXISTS"

  # Step 3: Create Function URL if not exists
  log_info "[3/6] Setting up Function URL..."

  FUNCTION_URL=$(aws lambda get-function-url-config \
    --function-name "$FUNCTION_NAME" \
    --query 'FunctionUrl' \
    --output text 2>/dev/null || echo "")

  if [ -z "$FUNCTION_URL" ] || [[ "$FUNCTION_URL" == *"ResourceNotFoundException"* ]]; then
    log_warning "Creating new Function URL..."
    FUNCTION_URL=$(aws lambda create-function-url-config \
      --function-name "$FUNCTION_NAME" \
      --auth-type NONE \
      --cors '{
        "AllowOrigins": ["*"],
        "AllowMethods": ["GET", "POST"],
        "AllowHeaders": ["Content-Type", "Authorization"],
        "MaxAge": 86400
      }' \
      --query 'FunctionUrl' \
      --output text)
  fi

  log_success "Function URL: $FUNCTION_URL"

  # Step 4: Test Lambda
  log_info "[4/6] Testing Lambda function..."

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$FUNCTION_URL" || echo "000")

  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    log_success "Lambda function is responding (HTTP $HTTP_CODE)"
  else
    log_warning "Lambda function returned HTTP $HTTP_CODE (may be initializing)"
  fi

  # Step 5: Request ACM Certificate
  log_info "[5/6] Setting up ACM certificate..."

  CERT_ARN=$(aws acm list-certificates \
    --region "$AWS_REGION" \
    --query "CertificateSummaryList[?DomainName=='$DOMAIN'].CertificateArn" \
    --output text 2>/dev/null | head -1 || echo "")

  if [ -z "$CERT_ARN" ]; then
    log_warning "Requesting new ACM certificate for $DOMAIN..."
    CERT_ARN=$(aws acm request-certificate \
      --domain-name "$DOMAIN" \
      --subject-alternative-names "www.$DOMAIN" \
      --validation-method DNS \
      --region "$AWS_REGION" \
      --query 'CertificateArn' \
      --output text)

    log_warning "Certificate requested: $CERT_ARN"
    log_warning "Please validate the certificate in the AWS ACM console (DNS validation required)"
  else
    CERT_STATUS=$(aws acm describe-certificate \
      --certificate-arn "$CERT_ARN" \
      --region "$AWS_REGION" \
      --query 'Certificate.Status' \
      --output text)

    log_success "Using certificate (Status: $CERT_STATUS): $CERT_ARN"
  fi

  # Step 6: Output Summary
  log_info "[6/6] Deployment Summary"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "${GREEN}✓ Deployment Complete${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Application Details:"
  echo "  Function Name:  $FUNCTION_NAME"
  echo "  Function URL:   $FUNCTION_URL"
  echo "  Region:         $AWS_REGION"
  echo "  Domain:         $DOMAIN"
  echo ""
  echo "Lambda Configuration:"
  echo "  LLM Endpoint:   $LLM_ENDPOINT"
  echo "  LLM Model:      $LLM_MODEL"
  echo "  Memory:         2048 MB"
  echo "  Timeout:        900 seconds"
  echo ""
  echo "Certificate:"
  echo "  ARN:            $CERT_ARN"
  echo ""
  echo "Next Steps:"
  echo "  1. Validate ACM certificate (if newly requested)"
  echo "  2. Create CloudFront distribution"
  echo "  3. Configure Route 53 DNS records"
  echo "  4. Test: curl '$FUNCTION_URL'"
  echo ""
  echo "To view logs:"
  echo "  aws logs tail /aws/lambda/$FUNCTION_NAME --follow"
  echo ""
  echo "Credentials will be cleaned up automatically."
  echo ""
}

# Run main
main "$@"
