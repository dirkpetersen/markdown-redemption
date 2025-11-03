# Rebuilding Lambda Deployment Package - Quick Reference

## Changes Made to Fix CSS/Static Assets

The following files have been modified to fix CSS not loading on Lambda:

1. **app.py**
   - Explicit static/template folder configuration
   - Debug logging for path resolution
   - Lambda environment detection moved earlier

2. **deployment/lambda_handler.py**
   - Reverted from `aws-wsgi` back to working custom WSGI adapter
   - Proper REST API event handling restored

## Build and Deploy Script

```bash
#!/bin/bash
set -e

REGION="us-west-2"
PROFILE="iam-dirk"
FUNCTION_NAME="markdown-redemption"
S3_BUCKET="markdown-redemption-usw2-1762126505"

# 1. Create fresh virtual environment
rm -rf deployment/build
mkdir -p deployment/build
cd deployment/build

# 2. Create Python 3.13 virtual environment (use Python 3.13)
python3.13 -m venv venv
source venv/bin/activate

# 3. Install dependencies
pip install --upgrade pip
pip install -r ../../requirements.txt

# 4. Build deployment package
SITE_PACKAGES="venv/lib/python*/site-packages"
mkdir -p lambda_package

# Copy Python packages
cp -r $SITE_PACKAGES/* lambda_package/

# Copy application files
cp ../../app.py lambda_package/
cp ../lambda_handler.py lambda_package/

# Copy static and template directories
cp -r ../../static lambda_package/
cp -r ../../templates lambda_package/

# 5. Create ZIP file
cd lambda_package
zip -r ../lambda-deployment-v8.zip .
cd ..

# 6. Upload to S3
aws s3 cp lambda-deployment-v8.zip \
  s3://${S3_BUCKET}/lambda-deployment-v8.zip \
  --region ${REGION} \
  --profile ${PROFILE}

# 7. Update Lambda function
aws lambda update-function-code \
  --function-name ${FUNCTION_NAME} \
  --s3-bucket ${S3_BUCKET} \
  --s3-key lambda-deployment-v8.zip \
  --region ${REGION} \
  --profile ${PROFILE}

echo "✅ Lambda function updated with new package"

# 8. Wait for update to complete
aws lambda wait function-updated \
  --function-name ${FUNCTION_NAME} \
  --region ${REGION} \
  --profile ${PROFILE}

echo "✅ Lambda function update complete"

# 9. Test the endpoint
echo ""
echo "Testing endpoint..."
curl -s https://6r1egbiq25.execute-api.us-west-2.amazonaws.com/prod/ | grep -o "<title>.*</title>" | head -1

# 10. Check logs
echo ""
echo "Lambda logs (last 10 lines):"
aws logs tail /aws/lambda/markdown-redemption \
  --max-items 10 \
  --region ${REGION} \
  --profile ${PROFILE}
```

## Manual Build Steps (if script fails)

### Step 1: Create Virtual Environment
```bash
cd deployment/build
python3.13 -m venv venv
source venv/bin/activate  # or: venv\Scripts\activate on Windows
```

### Step 2: Install Dependencies
```bash
pip install -r ../../requirements.txt
```

### Step 3: Verify Latest Code
```bash
# Make sure these files have the latest changes:
# - app.py (with explicit static/template config)
# - deployment/lambda_handler.py (with custom WSGI adapter)
```

### Step 4: Build Package
```bash
mkdir -p lambda_package

# Find Python version in venv
PYTHON_VERSION=$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
SITE_PACKAGES="venv/lib/python${PYTHON_VERSION}/site-packages"

# Copy everything
cp -r $SITE_PACKAGES/* lambda_package/
cp ../../app.py lambda_package/
cp ../lambda_handler.py lambda_package/
cp -r ../../static lambda_package/
cp -r ../../templates lambda_package/
```

### Step 5: Create ZIP
```bash
cd lambda_package
zip -r ../lambda-deployment-v8.zip .
cd ..

# Verify package size (should be ~25MB)
ls -lh lambda-deployment-v8.zip
```

### Step 6: Upload and Deploy
```bash
# Upload to S3
aws s3 cp lambda-deployment-v8.zip \
  s3://markdown-redemption-usw2-1762126505/lambda-deployment-v8.zip \
  --region us-west-2 \
  --profile iam-dirk

# Update Lambda function
aws lambda update-function-code \
  --function-name markdown-redemption \
  --s3-bucket markdown-redemption-usw2-1762126505 \
  --s3-key lambda-deployment-v8.zip \
  --region us-west-2 \
  --profile iam-dirk

# Wait for update
aws lambda wait function-updated \
  --function-name markdown-redemption \
  --region us-west-2 \
  --profile iam-dirk
```

## Verification

### 1. Check Debug Logs
```bash
aws logs tail /aws/lambda/markdown-redemption --follow --region us-west-2 --profile iam-dirk
```

Look for output like:
```
[DEBUG] Flask App Dir: /var/task
[DEBUG] Static Folder: /var/task/static
[DEBUG] Template Folder: /var/task/templates
[DEBUG] Static URL Path: /static
[DEBUG] Static folder exists: ['css', 'js', 'images']...
```

### 2. Test Static File Access
```bash
# Should return HTTP 200 with CSS content
curl -I https://6r1egbiq25.execute-api.us-west-2.amazonaws.com/prod/static/css/style.css
```

Expected response:
```
HTTP/1.1 200 OK
Content-Type: text/css
Content-Length: 12345
```

### 3. Visual Test
```bash
# Visit in browser
https://6r1egbiq25.execute-api.us-west-2.amazonaws.com/prod/
```

Should show:
- Styled header with logo and title
- Colorful upload interface (not plain text)
- Proper button styling
- Form layout with proper spacing

## Rollback

If something goes wrong, revert to previous version:

```bash
aws lambda update-function-code \
  --function-name markdown-redemption \
  --s3-bucket markdown-redemption-usw2-1762126505 \
  --s3-key lambda-deployment-v7.zip \
  --region us-west-2 \
  --profile iam-dirk
```

## Version History

- v7: Last working version before HTTP API attempt
- v8: Fixed CSS with explicit static/template config + reverted lambda_handler.py
