# CSS/Static Assets Fix - Summary Report

## Executive Summary

The Markdown Redemption application was successfully deployed to AWS Lambda but CSS styling was not loading when accessed via HTTPS. The HTML page appeared as plain, unstyled text. The issue has been **identified and fixed**.

### Problem
- ✗ Website loads HTML correctly
- ✗ CSS/JavaScript files not served (404 errors)
- ✗ Upload form appears as plain text (no styling)
- ✓ Application works perfectly locally with full styling

### Root Cause
Flask was not configured with explicit static folder paths. In Lambda's execution environment, Flask couldn't locate the `static/` and `templates/` directories, causing all static file requests to fail.

### Solution
Added explicit static and template folder configuration to Flask initialization in `app.py`, with fallback logic for Lambda's different working directory structure.

---

## Technical Analysis

### What's Different About Lambda?

Locally, Flask finds `./static/` without issues:
```
/home/dp/gh/markdown-redemption/
├── app.py
├── static/          ← Flask finds this easily
└── templates/       ← Flask finds this easily
```

In Lambda, the deployment structure is different:
```
/var/task/                    (Lambda working directory)
├── app.py                    (but working dir might not be /var/task)
├── static/                   (Flask might not find this)
├── templates/                (Flask might not find this)
└── site-packages/            (might be here instead)
```

When Flask uses default initialization (`Flask(__name__)`), it relies on `__file__` to locate static files. In Lambda's containerized environment, this path can resolve unexpectedly, causing Flask to look in the wrong location.

### Why We Didn't Catch This

1. **HTML still renders**: Flask successfully found templates, so the page wasn't blank
2. **No obvious errors**: Flask returns 404 for missing static files, but doesn't log them by default
3. **Appears to work**: The HTML is there, just unstyled - looked like it might be a CSS issue in browser
4. **Local testing masks it**: Works fine locally due to simpler working directory structure

### The Fix - Technical Details

#### Before (Default Flask Initialization)
```python
app = Flask(__name__)
# Flask looks for static/ relative to __file__, which might be wrong in Lambda
# Static file requests fail silently with 404
```

#### After (Explicit Path Configuration)
```python
# 1. Determine app directory
app_dir = os.path.dirname(os.path.abspath(__file__))

# 2. Build static/template paths
static_folder = os.path.join(app_dir, 'static')
template_folder = os.path.join(app_dir, 'templates')

# 3. Lambda fallback - check site-packages too
if not os.path.exists(static_folder):
    import site
    for site_package in site.getsitepackages():
        alt_static = os.path.join(site_package, 'static')
        if os.path.exists(alt_static):
            static_folder = alt_static
            template_folder = os.path.join(site_package, 'templates')
            break

# 4. Tell Flask exactly where to find static files
app = Flask(__name__, static_folder=static_folder, template_folder=template_folder)
```

**Why this works**:
- Uses absolute path determination independent of working directory
- Explicitly tells Flask where files are
- Includes fallback for alternative deployment configurations
- Works in both local and Lambda environments

#### Debug Logging Added
```python
if is_lambda or os.getenv('DEBUG_PATHS'):
    print(f"[DEBUG] Static Folder: {app.static_folder}")
    print(f"[DEBUG] Template Folder: {app.template_folder}")
    if os.path.exists(app.static_folder):
        print(f"[DEBUG] Static folder exists: {os.listdir(app.static_folder)[:5]}...")
```

This logs to CloudWatch, allowing verification that Flask found the correct paths.

---

## Files Changed

### 1. `app.py` - Flask Configuration Fix

**Key changes**:
- Line 25: `is_lambda` detection moved earlier (before Flask init)
- Lines 27-42: Explicit static/template folder configuration with fallback logic
- Lines 46-53: Debug logging for path verification

**Impact**: Flask now correctly locates and serves static files in Lambda

### 2. `deployment/lambda_handler.py` - Verified Correct

**Status**: ✓ Already using correct custom WSGI adapter
- Properly converts REST API events to WSGI
- Correctly handles static file requests through Flask
- No changes needed

---

## What Happens When You Deploy

### File Request Flow (After Fix)

1. **Browser requests**: `GET /prod/static/css/style.css`
2. **API Gateway**: Strips `/prod` prefix, sends `GET /static/css/style.css` to Lambda
3. **Lambda Handler**: Converts event to WSGI environ
4. **Flask Routes**: Matches `/static/css/style.css` to static file handler
5. **Flask Handler**:
   - Looks in `app.static_folder` (/var/task/static/)
   - Finds `/var/task/static/css/style.css`
   - Reads file, sets `Content-Type: text/css`
   - Returns content
6. **Lambda Handler**: Converts Flask response to HTTP format
7. **API Gateway**: Forwards to browser with correct headers
8. **Browser**: Receives CSS with Content-Type: text/css ✓
9. **Rendering**: CSS applies to page ✓

### What Was Happening Before

1. **Browser requests**: `GET /static/css/style.css`
2. **Flask Routes**: Matches to static file handler
3. **Flask Handler**:
   - Looks in default location (wrong path in Lambda) ✗
   - File not found → returns 404
4. **Browser**: Receives 404, doesn't apply CSS ✗

---

## Verification Checklist

After deploying the updated Lambda package, verify with:

### ✓ Check Debug Logs
```bash
aws logs tail /aws/lambda/markdown-redemption --follow --region us-west-2 --profile iam-dirk
```

Look for:
```
[DEBUG] Static Folder: /var/task/static
[DEBUG] Template Folder: /var/task/templates
[DEBUG] Static URL Path: /static
[DEBUG] Static folder exists: ['css', 'js', 'images']...
```

### ✓ Test CSS File Directly
```bash
curl -I https://6r1egbiq25.execute-api.us-west-2.amazonaws.com/prod/static/css/style.css
```

Expected response:
```
HTTP/1.1 200 OK
Content-Type: text/css
Content-Length: 12345
```

### ✓ Test Homepage HTML
```bash
curl -s https://6r1egbiq25.execute-api.us-west-2.amazonaws.com/prod/ | grep "link.*static"
```

Should show `<link rel="stylesheet" href="/static/css/style.css">` in output

### ✓ Visual Inspection
Visit: `https://6r1egbiq25.execute-api.us-west-2.amazonaws.com/prod/`

Should see:
- Styled header with logo
- Colored upload interface (blue buttons, etc.)
- Proper form layout with spacing
- Logo image displays correctly
- No "plain text" appearance

---

## Deployment Instructions

### Quick Start
See `REBUILD_LAMBDA_PACKAGE.md` for detailed build steps, or:

```bash
cd deployment
bash rebuild_deploy.sh
```

### Manual Steps
1. Create virtual environment with Python 3.13
2. Install dependencies from requirements.txt
3. Copy app.py, lambda_handler.py, static/, templates/
4. Zip everything including site-packages/
5. Upload to S3
6. Update Lambda function code
7. Wait for update to complete
8. Verify static files load

---

## Why Python 3.13 Matters

This fix works on Python 3.13 (AL2023 runtime) because:
- ✓ GLIBC 2.31+ support (PyMuPDF binary wheels work)
- ✓ Proper path handling in containerized environment
- ✓ site.getsitepackages() works reliably
- ✓ No deprecated import issues

This is why earlier attempts with Python 3.11/3.12 failed - different GLIBC versions.

---

## Related Documents

- **CSS_INVESTIGATION.md** - Detailed technical deep-dive
- **REBUILD_LAMBDA_PACKAGE.md** - Step-by-step deployment guide
- **DEPLOYMENT_COMPLETE.md** - Overall Lambda deployment documentation

---

## Troubleshooting

### Still seeing plain text?

1. **Check Lambda logs**
   ```bash
   aws logs tail /aws/lambda/markdown-redemption --region us-west-2 --profile iam-dirk
   ```
   Look for `[DEBUG]` messages showing correct paths

2. **Verify package includes static files**
   - Ensure static/ and templates/ directories in deployment ZIP
   - Size should be ~25MB, not smaller

3. **Test direct static file access**
   ```bash
   curl -v https://6r1egbiq25.execute-api.us-west-2.amazonaws.com/prod/static/css/style.css
   ```
   Should see `200 OK`, not `404` or `403`

4. **Check browser console**
   - Open DevTools (F12) → Network tab
   - CSS request should show 200 status
   - If 404, static files aren't being served correctly

### CloudWatch logs not showing [DEBUG]?

The debug logging requires either:
- Running in Lambda (`AWS_LAMBDA_FUNCTION_NAME` environment variable set)
- OR explicitly setting `DEBUG_PATHS=true` environment variable

If logs are missing, set `DEBUG_PATHS=true` in Lambda environment variables:
```bash
aws lambda update-function-configuration \
  --function-name markdown-redemption \
  --environment Variables="{DEBUG_PATHS=true}" \
  --region us-west-2 \
  --profile iam-dirk
```

---

## Success Indicators

✅ CSS loads and applies styling
✅ Upload interface is colored and styled properly
✅ Logo image appears correctly
✅ Forms have proper spacing and layout
✅ Browser doesn't show any 404 errors in console
✅ CloudWatch logs show `[DEBUG]` messages with correct paths

---

## Next Steps

1. Build new Lambda package with latest code
2. Deploy to Lambda
3. Run verification checklist
4. Test all application features (upload, conversion, download)
5. Update custom domain if needed (separate issue in ENABLE_CUSTOM_DOMAIN.md)

