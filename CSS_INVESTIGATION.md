# CSS/Static Assets Investigation - Lambda Deployment Issue

## Problem Statement

When accessing The Markdown Redemption application via the AWS Lambda HTTPS endpoint, the website loads HTML successfully but **CSS styling is not being applied**. The page appears as plain, unstyled text. This occurs despite:
1. Static files being properly included in the Lambda deployment package
2. The application working correctly with full styling when run locally
3. HTML templates using correct `url_for('static', ...)` references

## Root Causes Identified

### Issue 1: Flask Missing Explicit Static/Template Folder Configuration ❌

**Problem**: Flask was initialized with default settings:
```python
app = Flask(__name__)  # DEFAULT BEHAVIOR
```

When Flask uses default initialization, it looks for `static` and `templates` folders relative to the file location. However, in Lambda's execution environment:
- The working directory might not be where the deployment package root is
- Python's `__file__` might resolve to a different path than expected
- The static and template folders might be packaged in site-packages

**Result**: `url_for('static', filename='css/style.css')` generates correct paths like `/static/css/style.css`, but Flask's internal static file handler can't find the actual files to serve them.

**Evidence**: No error messages in Lambda logs because Flask is generating the HTML correctly - it's just that when the browser requests `/static/css/style.css`, Flask returns 404.

### Issue 2: Lambda Handler Using aws-wsgi Adapter (Recent Change) ❌

**Problem**: The `deployment/lambda_handler.py` was changed from the working custom WSGI adapter to use the `aws-wsgi` library:
```python
import aws_wsgi
from app import app

def lambda_handler(event, context):
    return aws_wsgi.response(app, event, context)
```

This was part of the attempted HTTP API deployment that failed. The HTTP API routing issues were never resolved, but the handler remained modified.

**Result**: The lambda handler can't properly route requests to Flask, especially for static files.

**Status**: REVERTED to working custom WSGIEventAdapter that was previously successful with REST API.

## Solutions Implemented

### Solution 1: Explicit Static and Template Folder Configuration ✅

Modified `app.py` initialization to explicitly specify static and template folders:

```python
# Determine if running in Lambda environment FIRST
is_lambda = os.getenv('AWS_LAMBDA_FUNCTION_NAME') is not None

# Initialize Flask app with explicit static/template folder paths
app_dir = os.path.dirname(os.path.abspath(__file__))
static_folder = os.path.join(app_dir, 'static')
template_folder = os.path.join(app_dir, 'templates')

# If running in Lambda, static/templates might be in site-packages
if not os.path.exists(static_folder):
    import site
    for site_package in site.getsitepackages():
        alt_static = os.path.join(site_package, 'static')
        alt_template = os.path.join(site_package, 'templates')
        if os.path.exists(alt_static):
            static_folder = alt_static
            template_folder = alt_template
            break

app = Flask(__name__, static_folder=static_folder, template_folder=template_folder)
```

**How it works**:
1. Determines the absolute path of app.py
2. Looks for `static/` and `templates/` relative to app.py
3. If not found (Lambda environment), searches in Python's site-packages directories
4. Passes explicit paths to Flask initialization

**Result**: Flask now knows exactly where static and template files are, regardless of working directory.

### Solution 2: Debug Logging for Path Resolution ✅

Added debug logging to understand Flask's path resolution:

```python
# Debug logging for Lambda environment
if is_lambda or os.getenv('DEBUG_PATHS'):
    print(f"[DEBUG] Flask App Dir: {app_dir}")
    print(f"[DEBUG] Static Folder: {app.static_folder}")
    print(f"[DEBUG] Template Folder: {app.template_folder}")
    print(f"[DEBUG] Static URL Path: {app.static_url_path}")
    if os.path.exists(app.static_folder):
        print(f"[DEBUG] Static folder exists: {os.listdir(app.static_folder)[:5]}...")
```

**Purpose**: When Lambda logs appear, we can verify:
- Whether Flask found the correct static folder
- What URL path is being used for static files
- Whether the folders actually exist and are readable

### Solution 3: Restored Working Lambda Handler ✅

Reverted `deployment/lambda_handler.py` from `aws-wsgi` back to the proven custom WSGI adapter:

```python
class WSGIEventAdapter:
    """Converts AWS Lambda/API Gateway events to WSGI environ dicts"""
    # Handles both REST API and HTTP API event formats
    # Properly converts requests to WSGI environ and responses back to HTTP format
```

**Why**: The custom adapter was working correctly with REST API. It properly:
1. Converts REST API event format to WSGI environ
2. Calls Flask WSGI app
3. Converts Flask response back to API Gateway HTTP format
4. Handles base64 encoding for binary responses

## Technical Details

### How Flask Static File Serving Works

When a browser requests `/static/css/style.css`:

1. **Request arrives at Lambda**
   - Event contains: `path: /prod/static/css/style.css` (API Gateway stage prefix)
   - Custom adapter converts to: `PATH_INFO: /static/css/style.css`

2. **Flask routes the request**
   - Flask has built-in `@app.route('/static/<path:filename>')` route
   - Checks if file exists at `app.static_folder + '/' + filename`
   - Returns file with appropriate Content-Type, or 404

3. **Response returns to browser**
   - Adapter converts Flask response to API Gateway HTTP format
   - Browser receives CSS with `Content-Type: text/css`

**Critical Point**: All of this fails if Flask can't find `app.static_folder`. Default Flask initialization can't locate it in Lambda.

### Path Resolution in Lambda Environment

Lambda execution environment:
```
/var/task/           (Lambda deployment package root - contains app.py)
├── app.py
├── lambda_handler.py
├── static/           (must be found and configured)
├── templates/        (must be found and configured)
└── site-packages/    (optional location if files are there)
```

When app.py runs:
- `os.path.abspath(__file__)` = `/var/task/app.py`
- `app_dir` = `/var/task/`
- `static_folder` = `/var/task/static/`

## Files Modified

1. **app.py**
   - Added early `is_lambda` detection
   - Added explicit static/template folder configuration with fallback to site-packages
   - Added debug logging for path resolution

2. **deployment/lambda_handler.py**
   - Reverted from `aws-wsgi` back to custom WSGIEventAdapter
   - Restored proper REST API event handling

## Deployment Package Requirements

When building `lambda-deployment-*.zip`, ensure:

```
lambda-deployment-*.zip (must include)
├── app.py                    # WITH explicit static/template config
├── lambda_handler.py         # WITH custom WSGI adapter
├── static/                   # REQUIRED - all CSS/JS/images
│   ├── css/style.css
│   ├── js/upload.js
│   └── images/logo.svg
├── templates/                # REQUIRED - all HTML templates
│   ├── base.html
│   ├── index.html
│   ├── processing.html
│   └── result.html
└── site-packages/            # Python dependencies
```

## Testing Steps

After deploying updated package to Lambda:

1. **Check Lambda logs for debug output**
   ```bash
   aws logs tail /aws/lambda/markdown-redemption --follow --region us-west-2
   ```
   Should show `[DEBUG]` lines with correct paths.

2. **Test CSS file directly**
   ```bash
   curl -v https://6r1egbiq25.execute-api.us-west-2.amazonaws.com/prod/static/css/style.css
   ```
   Should return HTTP 200 with `Content-Type: text/css`

3. **Test homepage HTML**
   ```bash
   curl https://6r1egbiq25.execute-api.us-west-2.amazonaws.com/prod/ | head -30
   ```
   Should show `<link rel="stylesheet" href="/static/css/style.css">` in source

4. **Visual inspection in browser**
   - CSS should load and apply styling
   - Upload form should be styled with proper layout
   - Colors and fonts should match local version

## Why This Wasn't Caught Earlier

1. **HTML still loaded**: Flask was successfully rendering templates, so the page appeared to work
2. **No 404s visible**: CSS requests returned before being logged (Flask static handler runs before app logging)
3. **Local testing masked the issue**: Locally, Flask finds `./static/` without issue
4. **Lambda deployment packaging**: Files were included in ZIP but Flask wasn't configured to find them

## Related Files

- **DEPLOYMENT_COMPLETE.md** - Overall deployment documentation
- **ENABLE_CUSTOM_DOMAIN.md** - Custom domain setup (separate issue)
- **IAM_PERMISSIONS_GUIDE.md** - IAM permissions requirements
