#!/bin/bash
set -e

# Configuration
REGION="us-west-2"
PROFILE="iam-dirk"
FUNCTION_NAME="markdown-redemption"
S3_BUCKET="markdown-redemption-usw2-1762126505"
PACKAGE_VERSION="v8"

echo "=========================================="
echo "Building Lambda Package - v${PACKAGE_VERSION}"
echo "=========================================="

# Navigate to deployment directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 1. Clean up old build
echo ""
echo "Step 1: Cleaning up old build..."
rm -rf build
mkdir -p build
cd build

# 2. Create Python 3.13 virtual environment
echo ""
echo "Step 2: Creating Python 3.13 virtual environment..."
python3.13 -m venv venv || python3 -m venv venv
source venv/bin/activate

# 3. Install dependencies
echo ""
echo "Step 3: Installing dependencies..."
pip install --upgrade pip setuptools wheel > /dev/null 2>&1
pip install -r ../../requirements.txt

# 4. Find site-packages directory
echo ""
echo "Step 4: Finding site-packages..."
PYTHON_VERSION=$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
SITE_PACKAGES=$(python -c "import site; print(site.getsitepackages()[0])")
echo "   Site-packages: $SITE_PACKAGES"

# 5. Build deployment package
echo ""
echo "Step 5: Building deployment package..."
mkdir -p lambda_package

# Copy all packages
echo "   Copying packages..."
cp -r "$SITE_PACKAGES"/* lambda_package/ 2>/dev/null || true

# Copy application files
echo "   Copying application files..."
cp ../../app.py lambda_package/
cp ../lambda_handler.py lambda_package/

# Copy static and template directories
echo "   Copying static and template directories..."
cp -r ../../static lambda_package/
cp -r ../../templates lambda_package/

# 6. Create ZIP file
echo ""
echo "Step 6: Creating ZIP archive..."
cd lambda_package
zip -r -q ../lambda-deployment-${PACKAGE_VERSION}.zip .
cd ..

# Check package size
PACKAGE_SIZE=$(ls -lh lambda-deployment-${PACKAGE_VERSION}.zip | awk '{print $5}')
echo "   Package size: $PACKAGE_SIZE"

# 7. Upload to S3
echo ""
echo "Step 7: Uploading to S3..."
aws s3 cp lambda-deployment-${PACKAGE_VERSION}.zip \
  s3://${S3_BUCKET}/lambda-deployment-${PACKAGE_VERSION}.zip \
  --region ${REGION} \
  --profile ${PROFILE} \
  --no-progress

echo "   ✓ Uploaded to s3://${S3_BUCKET}/lambda-deployment-${PACKAGE_VERSION}.zip"

# 8. Update Lambda function
echo ""
echo "Step 8: Updating Lambda function code..."
aws lambda update-function-code \
  --function-name ${FUNCTION_NAME} \
  --s3-bucket ${S3_BUCKET} \
  --s3-key lambda-deployment-${PACKAGE_VERSION}.zip \
  --region ${REGION} \
  --profile ${PROFILE} \
  > /dev/null

# 9. Wait for update to complete
echo ""
echo "Step 9: Waiting for Lambda update to complete (this may take 30-60 seconds)..."
aws lambda wait function-updated \
  --function-name ${FUNCTION_NAME} \
  --region ${REGION} \
  --profile ${PROFILE}

echo "   ✓ Lambda function updated successfully"

# 10. Get function info
echo ""
echo "Step 10: Verifying Lambda configuration..."
aws lambda get-function \
  --function-name ${FUNCTION_NAME} \
  --region ${REGION} \
  --profile ${PROFILE} \
  --query 'Configuration | {Runtime, MemorySize, Timeout, LastModified, CodeSize}' \
  --output table

# 11. Test the endpoint
echo ""
echo "Step 11: Testing endpoint..."
ENDPOINT="https://6r1egbiq25.execute-api.us-west-2.amazonaws.com/prod"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$ENDPOINT/")
echo "   Endpoint: $ENDPOINT"
echo "   HTTP Status: $HTTP_CODE"

if [ "$HTTP_CODE" == "200" ]; then
    echo "   ✓ Endpoint responding"
else
    echo "   ⚠ Unexpected status code: $HTTP_CODE"
fi

# 12. Check for debug logs
echo ""
echo "Step 12: Checking Lambda logs (last 30 seconds)..."
sleep 2  # Give Lambda time to write logs
aws logs tail /aws/lambda/markdown-redemption \
  --since 30s \
  --region ${REGION} \
  --profile ${PROFILE} \
  2>/dev/null || echo "   (No new logs yet - may appear shortly)"

# Cleanup
cd "$SCRIPT_DIR"
echo ""
echo "=========================================="
echo "✅ Deployment Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Visit: $ENDPOINT"
echo "2. Verify CSS is loading (not plain text)"
echo "3. Test file upload"
echo ""
echo "View logs:"
echo "aws logs tail /aws/lambda/markdown-redemption --follow --region $REGION --profile $PROFILE"
echo ""
