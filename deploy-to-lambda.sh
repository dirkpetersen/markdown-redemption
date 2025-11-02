#!/bin/bash
set -e  # Exit on error

##############################################################################
# AWS Lambda Deployment Script for The Markdown Redemption
#
# This script deploys the Flask application to AWS Lambda with:
# - Lambda Function with Function URL
# - ACM certificate for HTTPS
# - CloudFront distribution
# - Route 53 DNS configuration
#
# Usage:
#   ./deploy-to-lambda.sh [sue-lambda|iam-dirk]
#
# Environment Variables (optional):
#   AWS_PROFILE       - AWS CLI profile to use (default: sue-lambda)
#   AWS_REGION        - AWS region for Lambda (default: us-east-1)
#   DOMAIN            - Full domain name (default: markdown.osu.internetchen.de)
#   BASE_DOMAIN       - Base domain for Route53 (default: osu.internetchen.de)
#   FUNCTION_NAME     - Lambda function name (default: markdown-redemption)
#   LLM_ENDPOINT      - LLM API endpoint (required)
#   LLM_MODEL         - LLM model name (required)
#   LLM_API_KEY       - LLM API key (optional)
##############################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
AWS_PROFILE="${1:-sue-lambda}"
FALLBACK_PROFILE="iam-dirk"
AWS_REGION="${AWS_REGION:-us-east-1}"  # Must be us-east-1 for ACM certificates for CloudFront
DOMAIN="${DOMAIN:-markdown.osu.internetchen.de}"
BASE_DOMAIN="${BASE_DOMAIN:-osu.internetchen.de}"
FUNCTION_NAME="${FUNCTION_NAME:-markdown-redemption}"
LAMBDA_ROLE_NAME="${LAMBDA_ROLE_NAME:-${FUNCTION_NAME}-execution-role}"
DEPLOYMENT_PACKAGE="lambda-deployment.zip"
MISSING_PERMS_FILE="aws-missing.md"
UPDATED_POLICY_FILE="sue-lambda-updated-policy.json"

# Lambda configuration
LAMBDA_TIMEOUT=900  # 15 minutes (maximum)
LAMBDA_MEMORY=2048  # 2GB
LAMBDA_STORAGE=10240  # 10GB ephemeral storage

# Tracking variables
CURRENT_PROFILE="$AWS_PROFILE"
PERMISSION_ERRORS=()
CREATED_RESOURCES=()

##############################################################################
# Helper Functions
##############################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

track_resource() {
    CREATED_RESOURCES+=("$1")
}

record_permission_error() {
    local operation="$1"
    local error="$2"
    log_warning "Permission issue detected: $operation"
    PERMISSION_ERRORS+=("$operation: $error")
}

try_with_fallback() {
    local operation="$1"
    shift
    local cmd=("$@")

    log_info "Attempting: $operation (profile: $CURRENT_PROFILE)"

    if output=$("${cmd[@]}" 2>&1); then
        echo "$output"
        return 0
    else
        local exit_code=$?
        if echo "$output" | grep -qi "AccessDenied\|not authorized\|forbidden"; then
            record_permission_error "$operation" "$output"

            if [ "$CURRENT_PROFILE" = "$AWS_PROFILE" ] && [ -n "$FALLBACK_PROFILE" ]; then
                log_warning "Switching to fallback profile: $FALLBACK_PROFILE"
                CURRENT_PROFILE="$FALLBACK_PROFILE"

                log_info "Retrying: $operation (profile: $CURRENT_PROFILE)"
                if output=$("${cmd[@]}" 2>&1); then
                    echo "$output"
                    return 0
                else
                    log_error "Failed even with fallback profile: $operation"
                    echo "$output" >&2
                    return $exit_code
                fi
            else
                log_error "Permission denied and no fallback available: $operation"
                echo "$output" >&2
                return $exit_code
            fi
        else
            log_error "$operation failed: $output"
            echo "$output" >&2
            return $exit_code
        fi
    fi
}

aws_cmd() {
    aws --profile "$CURRENT_PROFILE" --region "$AWS_REGION" "$@"
}

##############################################################################
# Pre-flight Checks
##############################################################################

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Docker (optional, but recommended)
    if ! command -v docker &> /dev/null; then
        log_warning "Docker is not installed. Will use pip with platform targeting."
        log_info "For best compatibility, install Docker: https://docs.docker.com/engine/install/"
    fi

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi

    # Check pip
    if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
        log_error "pip is not installed. Please install Python and pip first."
        exit 1
    fi

    # Check zip command
    if ! command -v zip &> /dev/null; then
        log_error "zip command is not installed. Please install it first (apt install zip)."
        exit 1
    fi

    # Check AWS profiles exist
    if ! aws configure list --profile "$AWS_PROFILE" &> /dev/null; then
        log_error "AWS profile '$AWS_PROFILE' not found."
        exit 1
    fi

    if ! aws configure list --profile "$FALLBACK_PROFILE" &> /dev/null; then
        log_warning "Fallback profile '$FALLBACK_PROFILE' not found. Continuing without fallback."
        FALLBACK_PROFILE=""
    fi

    # Check for required environment variables
    if [ -z "$LLM_ENDPOINT" ]; then
        log_error "LLM_ENDPOINT environment variable is required."
        log_info "Example: export LLM_ENDPOINT='https://api.openai.com/v1'"
        exit 1
    fi

    if [ -z "$LLM_MODEL" ]; then
        log_error "LLM_MODEL environment variable is required."
        log_info "Example: export LLM_MODEL='gpt-4-vision-preview'"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

##############################################################################
# Build Deployment Package
##############################################################################

build_deployment_package() {
    log_info "Building Lambda deployment package..."

    # Create temporary directory for package contents
    rm -rf lambda_package
    mkdir -p lambda_package

    # Check if Docker is available
    if command -v docker &> /dev/null; then
        log_info "Docker detected - using Docker build method..."

        # Build Docker image
        log_info "Building Docker image with Lambda-compatible dependencies..."
        docker build -f Dockerfile.lambda -t markdown-redemption-lambda:latest .

        # Extract deployment package from Docker container
        log_info "Extracting deployment package from Docker container..."
        container_id=$(docker create markdown-redemption-lambda:latest)
        docker cp "$container_id:/var/task/." lambda_package/
        docker rm "$container_id"
    else
        log_warning "Docker not available - using pip with platform targeting..."
        log_info "Installing Lambda-compatible dependencies..."

        # Install dependencies for Lambda runtime (Amazon Linux 2023 / Python 3.12)
        # Try with binary-only first, fallback to allowing source builds
        pip install \
            --platform manylinux2014_x86_64 \
            --target lambda_package \
            --implementation cp \
            --python-version 3.12 \
            --upgrade \
            -r requirements.txt || \
        pip install \
            --target lambda_package \
            --upgrade \
            -r requirements.txt

        # Copy application files
        cp app.py lambda_package/
        cp lambda_handler.py lambda_package/
        cp -r templates lambda_package/
        cp -r static lambda_package/
        [ -f .env.default ] && cp .env.default lambda_package/ || true
    fi

    # Create ZIP file
    log_info "Creating deployment ZIP file..."
    cd lambda_package

    # Create ZIP with optimal compression
    zip -r -q -9 "../$DEPLOYMENT_PACKAGE" .
    cd ..

    # Check package size
    package_size=$(du -h "$DEPLOYMENT_PACKAGE" | cut -f1)
    package_bytes=$(stat -f%z "$DEPLOYMENT_PACKAGE" 2>/dev/null || stat -c%s "$DEPLOYMENT_PACKAGE")

    log_success "Deployment package created: $DEPLOYMENT_PACKAGE ($package_size)"

    # Warn if package is large
    if [ "$package_bytes" -gt 52428800 ]; then  # 50MB
        log_warning "Package size is $package_size (> 50MB)."

        if [ "$package_bytes" -gt 262144000 ]; then  # 250MB
            log_error "Package exceeds Lambda's 250MB limit. Consider using Lambda layers."
            exit 1
        fi
    fi

    # Cleanup
    rm -rf lambda_package
}

##############################################################################
# Lambda Function Setup
##############################################################################

create_or_get_execution_role() {
    log_info "Checking for Lambda execution role: $LAMBDA_ROLE_NAME"

    # Try to get existing role
    local role_arn
    if aws_cmd iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
        role_arn=$(aws_cmd iam get-role --role-name "$LAMBDA_ROLE_NAME" --query 'Role.Arn' --output text 2>/dev/null)
        log_success "Using existing role: $role_arn"
        echo "$role_arn"
        return 0
    fi

    # Create new role
    log_info "Creating new Lambda execution role..."

    trust_policy='{
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

    role_arn=$(aws_cmd iam create-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --assume-role-policy-document "$trust_policy" \
        --query 'Role.Arn' \
        --output text 2>/dev/null)

    track_resource "IAM Role: $LAMBDA_ROLE_NAME"

    # Attach CloudWatch Logs policy
    log_info "Attaching CloudWatch Logs policy..."
    aws_cmd iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" &>/dev/null

    log_success "Lambda execution role created: $role_arn"
    log_info "Waiting 10 seconds for role to propagate..."
    sleep 10

    echo "$role_arn"
}

create_or_update_lambda_function() {
    local role_arn="$1"

    log_info "Checking if Lambda function exists: $FUNCTION_NAME"

    # Check if function exists
    if try_with_fallback "Get Lambda function" \
        aws_cmd lambda get-function --function-name "$FUNCTION_NAME" &>/dev/null; then

        log_info "Updating existing Lambda function..."
        try_with_fallback "Update Lambda function code" \
            aws_cmd lambda update-function-code \
                --function-name "$FUNCTION_NAME" \
                --zip-file "fileb://$DEPLOYMENT_PACKAGE"

        log_info "Waiting for function update to complete..."
        aws_cmd lambda wait function-updated --function-name "$FUNCTION_NAME"

        # Update configuration
        log_info "Updating function configuration..."
        try_with_fallback "Update Lambda function configuration" \
            aws_cmd lambda update-function-configuration \
                --function-name "$FUNCTION_NAME" \
                --timeout "$LAMBDA_TIMEOUT" \
                --memory-size "$LAMBDA_MEMORY" \
                --ephemeral-storage "Size=$LAMBDA_STORAGE" \
                --environment "Variables={
                    LLM_ENDPOINT=$LLM_ENDPOINT,
                    LLM_MODEL=$LLM_MODEL,
                    LLM_API_KEY=$LLM_API_KEY,
                    SECRET_KEY=$(openssl rand -hex 32),
                    VERBOSE_LOGGING=True
                }"

        log_success "Lambda function updated"
    else
        log_info "Creating new Lambda function..."
        try_with_fallback "Create Lambda function" \
            aws_cmd lambda create-function \
                --function-name "$FUNCTION_NAME" \
                --runtime python3.12 \
                --role "$role_arn" \
                --handler lambda_handler.lambda_handler \
                --zip-file "fileb://$DEPLOYMENT_PACKAGE" \
                --timeout "$LAMBDA_TIMEOUT" \
                --memory-size "$LAMBDA_MEMORY" \
                --ephemeral-storage "Size=$LAMBDA_STORAGE" \
                --environment "Variables={
                    LLM_ENDPOINT=$LLM_ENDPOINT,
                    LLM_MODEL=$LLM_MODEL,
                    LLM_API_KEY=$LLM_API_KEY,
                    SECRET_KEY=$(openssl rand -hex 32),
                    VERBOSE_LOGGING=True
                }"

        track_resource "Lambda Function: $FUNCTION_NAME"
        log_success "Lambda function created"
    fi
}

create_function_url() {
    log_info "Configuring Lambda Function URL..."

    # Check if function URL already exists
    if function_url=$(try_with_fallback "Get Lambda Function URL" \
        aws_cmd lambda get-function-url-config \
            --function-name "$FUNCTION_NAME" \
            --query 'FunctionUrl' \
            --output text 2>/dev/null); then
        log_success "Function URL already exists: $function_url"
        echo "$function_url"
        return 0
    fi

    # Create function URL
    function_url=$(try_with_fallback "Create Lambda Function URL" \
        aws_cmd lambda create-function-url-config \
            --function-name "$FUNCTION_NAME" \
            --auth-type NONE \
            --cors "AllowOrigins=*,AllowMethods=*,AllowHeaders=*,MaxAge=86400" \
            --query 'FunctionUrl' \
            --output text)

    track_resource "Lambda Function URL: $function_url"
    log_success "Function URL created: $function_url"

    # Add resource-based policy to allow public access
    log_info "Adding public access policy to Function URL..."
    try_with_fallback "Add Lambda permission" \
        aws_cmd lambda add-permission \
            --function-name "$FUNCTION_NAME" \
            --statement-id FunctionURLAllowPublicAccess \
            --action lambda:InvokeFunctionUrl \
            --principal "*" \
            --function-url-auth-type NONE \
            2>/dev/null || true  # Ignore error if permission already exists

    echo "$function_url"
}

##############################################################################
# SSL Certificate Setup
##############################################################################

request_or_get_certificate() {
    log_info "Checking for existing ACM certificate for $DOMAIN..."

    # List certificates and find matching domain
    cert_arn=$(try_with_fallback "List ACM certificates" \
        aws_cmd acm list-certificates \
            --query "CertificateSummaryList[?DomainName=='$DOMAIN'].CertificateArn | [0]" \
            --output text)

    if [ "$cert_arn" != "None" ] && [ -n "$cert_arn" ]; then
        # Check certificate status
        cert_status=$(aws_cmd acm describe-certificate \
            --certificate-arn "$cert_arn" \
            --query 'Certificate.Status' \
            --output text)

        if [ "$cert_status" = "ISSUED" ]; then
            log_success "Using existing certificate: $cert_arn"
            echo "$cert_arn"
            return 0
        else
            log_warning "Certificate exists but status is: $cert_status"
        fi
    fi

    # Request new certificate
    log_info "Requesting new ACM certificate for $DOMAIN..."
    cert_arn=$(try_with_fallback "Request ACM certificate" \
        aws_cmd acm request-certificate \
            --domain-name "$DOMAIN" \
            --validation-method DNS \
            --query 'CertificateArn' \
            --output text)

    track_resource "ACM Certificate: $cert_arn"
    log_success "Certificate requested: $cert_arn"

    echo "$cert_arn"
}

get_certificate_validation_records() {
    local cert_arn="$1"

    log_info "Retrieving certificate validation records..."

    # Wait for validation records to be available
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        validation_records=$(aws_cmd acm describe-certificate \
            --certificate-arn "$cert_arn" \
            --query 'Certificate.DomainValidationOptions[0].ResourceRecord' \
            --output json)

        if [ "$validation_records" != "null" ] && [ -n "$validation_records" ]; then
            log_success "Validation records retrieved"
            echo "$validation_records"
            return 0
        fi

        attempt=$((attempt + 1))
        log_info "Waiting for validation records... (attempt $attempt/$max_attempts)"
        sleep 2
    done

    log_error "Timeout waiting for certificate validation records"
    exit 1
}

create_dns_validation_record() {
    local validation_records="$1"

    log_info "Finding Route 53 hosted zone for $BASE_DOMAIN..."

    # Get hosted zone ID
    hosted_zone_id=$(try_with_fallback "List Route 53 hosted zones" \
        aws_cmd route53 list-hosted-zones \
            --query "HostedZones[?Name=='${BASE_DOMAIN}.'].Id | [0]" \
            --output text)

    if [ "$hosted_zone_id" = "None" ] || [ -z "$hosted_zone_id" ]; then
        log_error "Hosted zone not found for $BASE_DOMAIN"
        log_info "Available hosted zones:"
        aws_cmd route53 list-hosted-zones --query 'HostedZones[*].Name' --output text
        exit 1
    fi

    log_success "Found hosted zone: $hosted_zone_id"

    # Extract validation record details
    record_name=$(echo "$validation_records" | jq -r '.Name')
    record_value=$(echo "$validation_records" | jq -r '.Value')
    record_type=$(echo "$validation_records" | jq -r '.Type')

    log_info "Creating DNS validation record: $record_name"

    # Create Route 53 change batch
    change_batch=$(cat <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$record_name",
        "Type": "$record_type",
        "TTL": 300,
        "ResourceRecords": [
          {
            "Value": "$record_value"
          }
        ]
      }
    }
  ]
}
EOF
    )

    change_id=$(try_with_fallback "Create Route 53 record set" \
        aws_cmd route53 change-resource-record-sets \
            --hosted-zone-id "$hosted_zone_id" \
            --change-batch "$change_batch" \
            --query 'ChangeInfo.Id' \
            --output text)

    log_success "DNS validation record created"
    echo "$change_id"
}

wait_for_certificate_validation() {
    local cert_arn="$1"

    log_info "Waiting for certificate validation (this may take several minutes)..."

    local max_attempts=60
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        cert_status=$(aws_cmd acm describe-certificate \
            --certificate-arn "$cert_arn" \
            --query 'Certificate.Status' \
            --output text)

        if [ "$cert_status" = "ISSUED" ]; then
            log_success "Certificate validated and issued!"
            return 0
        fi

        attempt=$((attempt + 1))
        log_info "Certificate status: $cert_status (attempt $attempt/$max_attempts)"
        sleep 10
    done

    log_error "Timeout waiting for certificate validation"
    log_info "Check AWS console for certificate status: $cert_arn"
    exit 1
}

##############################################################################
# CloudFront Distribution Setup
##############################################################################

create_cloudfront_distribution() {
    local function_url="$1"
    local cert_arn="$2"

    log_info "Creating CloudFront distribution..."

    # Extract origin domain from function URL (remove https:// and trailing /)
    origin_domain=$(echo "$function_url" | sed -e 's|https://||' -e 's|/$||')

    # Create distribution config
    dist_config=$(cat <<EOF
{
  "CallerReference": "$(date +%s)",
  "Comment": "The Markdown Redemption - $DOMAIN",
  "Enabled": true,
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "lambda-function-url",
        "DomainName": "$origin_domain",
        "CustomOriginConfig": {
          "HTTPPort": 80,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "https-only",
          "OriginSSLProtocols": {
            "Quantity": 1,
            "Items": ["TLSv1.2"]
          }
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "lambda-function-url",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 7,
      "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["GET", "HEAD"]
      }
    },
    "ForwardedValues": {
      "QueryString": true,
      "Cookies": {
        "Forward": "all"
      },
      "Headers": {
        "Quantity": 1,
        "Items": ["*"]
      }
    },
    "MinTTL": 0,
    "DefaultTTL": 0,
    "MaxTTL": 0,
    "Compress": true
  },
  "Aliases": {
    "Quantity": 1,
    "Items": ["$DOMAIN"]
  },
  "ViewerCertificate": {
    "ACMCertificateArn": "$cert_arn",
    "SSLSupportMethod": "sni-only",
    "MinimumProtocolVersion": "TLSv1.2_2021"
  }
}
EOF
    )

    # Create distribution
    dist_id=$(try_with_fallback "Create CloudFront distribution" \
        aws_cmd cloudfront create-distribution \
            --distribution-config "$dist_config" \
            --query 'Distribution.Id' \
            --output text)

    track_resource "CloudFront Distribution: $dist_id"

    # Get distribution domain name
    dist_domain=$(aws_cmd cloudfront get-distribution \
        --id "$dist_id" \
        --query 'Distribution.DomainName' \
        --output text)

    log_success "CloudFront distribution created: $dist_id"
    log_info "Distribution domain: $dist_domain"

    echo "$dist_domain"
}

##############################################################################
# Route 53 DNS Setup
##############################################################################

create_dns_records() {
    local dist_domain="$1"

    log_info "Creating Route 53 DNS records for $DOMAIN..."

    # Get hosted zone ID
    hosted_zone_id=$(aws_cmd route53 list-hosted-zones \
        --query "HostedZones[?Name=='${BASE_DOMAIN}.'].Id | [0]" \
        --output text)

    # Get CloudFront hosted zone ID (constant for CloudFront)
    cf_hosted_zone_id="Z2FDTNDATAQYW2"

    # Create change batch for A and AAAA records
    change_batch=$(cat <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$DOMAIN",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "$cf_hosted_zone_id",
          "DNSName": "$dist_domain",
          "EvaluateTargetHealth": false
        }
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$DOMAIN",
        "Type": "AAAA",
        "AliasTarget": {
          "HostedZoneId": "$cf_hosted_zone_id",
          "DNSName": "$dist_domain",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
EOF
    )

    try_with_fallback "Create Route 53 DNS records" \
        aws_cmd route53 change-resource-record-sets \
            --hosted-zone-id "$hosted_zone_id" \
            --change-batch "$change_batch"

    log_success "DNS records created for $DOMAIN → $dist_domain"
}

##############################################################################
# Testing and Documentation
##############################################################################

wait_for_cloudfront_deployment() {
    log_info "Waiting for CloudFront deployment (this can take 10-15 minutes)..."
    log_info "You can check status at: https://console.aws.amazon.com/cloudfront/"
    log_warning "The deployment will continue in the background. Proceeding to next steps..."
}

test_deployment() {
    log_info "Testing deployment at https://$DOMAIN..."

    # Wait a bit for DNS propagation
    log_info "Waiting 30 seconds for DNS propagation..."
    sleep 30

    # Test with curl
    if command -v curl &> /dev/null; then
        log_info "Testing HTTPS endpoint..."
        if curl -sSf -m 30 "https://$DOMAIN" > /dev/null 2>&1; then
            log_success "✓ HTTPS endpoint is responding"
        else
            log_warning "HTTPS endpoint not yet responding (may need more time for CloudFront deployment)"
        fi
    fi
}

generate_documentation() {
    log_info "Generating deployment documentation..."

    # Create aws-missing.md
    cat > "$MISSING_PERMS_FILE" <<EOF
# AWS Lambda Deployment - Permission Issues

## Deployment Summary

- **Deployment Date**: $(date)
- **AWS Profile Used**: $CURRENT_PROFILE
- **Function Name**: $FUNCTION_NAME
- **Domain**: $DOMAIN
- **Region**: $AWS_REGION

## Resources Created

EOF

    for resource in "${CREATED_RESOURCES[@]}"; do
        echo "- $resource" >> "$MISSING_PERMS_FILE"
    done

    if [ ${#PERMISSION_ERRORS[@]} -eq 0 ]; then
        cat >> "$MISSING_PERMS_FILE" <<EOF

## Permission Issues

✅ **No permission issues detected!** All operations completed successfully with the '$CURRENT_PROFILE' profile.

The existing IAM policy is sufficient for this deployment.
EOF
    else
        cat >> "$MISSING_PERMS_FILE" <<EOF

## Permission Issues Detected

The following operations encountered permission issues:

EOF

        for error in "${PERMISSION_ERRORS[@]}"; do
            echo "### $error" >> "$MISSING_PERMS_FILE"
            echo "" >> "$MISSING_PERMS_FILE"
        done

        cat >> "$MISSING_PERMS_FILE" <<EOF

## Required Additional Permissions

Based on the errors above, the following permissions may be needed:

\`\`\`json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CloudWatchLogsAccess",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/aws/lambda/*"
    }
  ]
}
\`\`\`

## Recommended Action

Review the permission errors above and update the IAM policy to include the necessary permissions.
EOF

        # Generate updated policy
        log_info "Generating updated IAM policy..."
        # This would merge existing policy with new permissions
        # For now, just documenting what's needed
    fi

    log_success "Documentation generated: $MISSING_PERMS_FILE"
}

##############################################################################
# Main Deployment Flow
##############################################################################

main() {
    log_info "=== AWS Lambda Deployment for The Markdown Redemption ==="
    log_info "Profile: $AWS_PROFILE (fallback: $FALLBACK_PROFILE)"
    log_info "Region: $AWS_REGION"
    log_info "Domain: $DOMAIN"
    log_info ""

    # Pre-flight checks
    check_prerequisites

    # Build deployment package
    build_deployment_package

    # Setup Lambda
    role_arn=$(create_or_get_execution_role)
    create_or_update_lambda_function "$role_arn"
    function_url=$(create_function_url)

    # Setup SSL Certificate
    cert_arn=$(request_or_get_certificate)
    validation_records=$(get_certificate_validation_records "$cert_arn")
    create_dns_validation_record "$validation_records"
    wait_for_certificate_validation "$cert_arn"

    # Setup CloudFront
    dist_domain=$(create_cloudfront_distribution "$function_url" "$cert_arn")

    # Setup DNS
    create_dns_records "$dist_domain"

    # Wait and test
    wait_for_cloudfront_deployment
    test_deployment

    # Generate documentation
    generate_documentation

    # Summary
    log_success "=== Deployment Complete! ==="
    log_info ""
    log_info "🌐 Application URL: https://$DOMAIN"
    log_info "⚡ Lambda Function: $FUNCTION_NAME"
    log_info "📋 Function URL: $function_url"
    log_info "🔒 Certificate: $cert_arn"
    log_info "☁️  CloudFront: $dist_domain"
    log_info ""
    log_info "📝 Documentation: $MISSING_PERMS_FILE"
    log_info ""
    log_warning "Note: CloudFront deployment may take 10-15 minutes to fully propagate."
    log_info "Monitor status: https://console.aws.amazon.com/cloudfront/"
    log_info ""
    log_success "Deployment script finished successfully!"
}

# Run main function
main "$@"
