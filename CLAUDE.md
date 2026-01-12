# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**The Markdown Redemption** is a Flask-based web application that converts documents (images, PDFs, DOCX) to Markdown format using vision-language AI models. The application has two deployment targets: traditional servers (with Gunicorn) and AWS Lambda.

## Development Quick Start

### Setup
```bash
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.default .env
# Edit .env with your LLM API endpoint
```

### Run Local Server
```bash
python app.py                    # Development mode (debug enabled)
gunicorn -c gunicorn_config.py app:app  # Production-like mode
```

### Access Application
- Development: http://localhost:5000
- The app requires an OpenAI-compatible vision API endpoint (Ollama, OpenAI, etc.)

## Key Architecture

### Single-File Application
All Flask routes and business logic are in **app.py** (~750 lines):
- Route handlers: `index()`, `upload_files()`, `process_documents()`, `download_file()`
- File processors: `extract_text_from_image()`, `extract_text_from_pdf()`, `extract_text_from_docx()`
- PDF handling: Dual-mode (native text extraction vs. OCR via LLM vision)
- Session management: Uses Flask sessions (cookie-based or filesystem)

### Core Data Flow
1. **Upload** → User uploads files via POST `/upload`
2. **Session Storage** → Files saved in `uploads/{session_id}/`
3. **Processing** → GET `/process` converts each file to Markdown
4. **Result Output** → Single `.md` or ZIP archive in `results/{session_id}/`
5. **Download** → GET `/download` streams the file
6. **Cleanup** → Automatic deletion after `CLEANUP_HOURS` (default: 24h)

### File Processing Modes
- **Images** (JPG, PNG, GIF, BMP, WebP): Sent as base64 to LLM vision API
- **PDFs**: Smart auto-detection (native text extraction vs OCR):
  - `analyze_page_complexity()` checks for tables/images/text density
  - If complex → convert to images and use LLM OCR
  - If simple → use PyMuPDF native extraction
  - Can force mode via `conversion_mode` form parameter
- **DOCX**: Converted via pandoc to GitHub-flavored Markdown

### API Communication
All LLM API calls use **OpenAI-compatible chat completions format**:
- Endpoint: `LLM_ENDPOINT/chat/completions` (normalized to include `/v1` path)
- Image encoding: Base64 data URLs
- Supports auth via `Authorization: Bearer {LLM_API_KEY}` header
- Timeout: Configurable via `LLM_TIMEOUT` env var
- Tested with: Ollama (local), OpenAI (cloud)

### Deployment Variants
- **Local/Server**: `python app.py` or `gunicorn`
- **AWS Lambda**: `lambda_handler.py` uses Mangum adapter; stores temp files in `/tmp/`
- **Container**: `Dockerfile.lambda` for Lambda deployment packaging

## Configuration

All settings via environment variables in `.env` (copy from `.env.default`):

### Critical Settings
- `LLM_ENDPOINT`: Vision API URL (e.g., `http://localhost:11434/v1`)
- `LLM_MODEL`: Model name (e.g., `qwen2.5vl:latest`)
- `LLM_API_KEY`: Auth token (optional for local models)
- `SECRET_KEY`: Session signing key (MUST change in production)

### Storage
- `UPLOAD_FOLDER`: Temp upload location (uses `/tmp` in Lambda)
- `RESULT_FOLDER`: Temp result location (uses `/tmp` in Lambda)
- `CLEANUP_HOURS`: Auto-delete threshold

### Limits
- `MAX_UPLOAD_SIZE`: Max file size in bytes (default: 100MB)
- `MAX_CONCURRENT_UPLOADS`: Max files per batch (default: 100)
- `ALLOWED_EXTENSIONS`: Comma-separated file types

### PDF Processing
- `PDF_DPI_SCALE`: Rendering quality (2.0 = ~144 DPI, higher = better OCR but slower)
- `PDF_PAGE_SEPARATOR`: Markdown separator between pages (default: `---`)
- `EXTRACTION_PROMPT`: Custom LLM prompt (leave empty for default)

## Directory Structure

```
.
├── app.py                    # Main Flask application (all routes + logic)
├── lambda_handler.py         # AWS Lambda ASGI adapter
├── gunicorn_config.py        # Production server config
├── requirements.txt          # Python dependencies
├── .env.default             # Configuration template (commit this)
├── .env                     # Actual config (gitignored)
│
├── templates/               # Jinja2 HTML templates
│   ├── base.html           # Header, footer, layout wrapper
│   ├── index.html          # Upload page with drag-and-drop
│   └── result.html         # Results & download page
│
├── static/                 # Client assets
│   ├── css/style.css       # All styling (responsive, theming)
│   ├── js/upload.js        # Optional: drag-drop enhancements
│   └── images/             # Logo, favicon, UI icons
│
├── uploads/                # Temp storage for uploaded files (gitignored)
├── results/                # Temp storage for converted MD (gitignored)
├── flask_session/          # Server-side session storage (gitignored)
│
├── docs/                   # Deployment & troubleshooting guides
├── deployment/             # Lambda packaging & vendored dependencies
└── tests/                  # Test directory (currently empty)
```

## Typical Development Tasks

### Add a New File Format
1. Add extension to `ALLOWED_EXTENSIONS` in `.env.default`
2. Create `extract_text_from_{format}()` function in `app.py`
3. Update `process_file()` to route to your handler
4. Update template allowed extensions display

### Modify Processing Logic
1. Edit conversion functions in `app.py` (lines ~170-477)
2. Test with `VERBOSE_LOGGING=True` to see debug output
3. PDF/OCR changes: Check `analyze_page_complexity()` and both extraction paths

### Adjust UI Styling
1. Edit `static/css/style.css` (all styling in one file)
2. Theme colors configurable via `THEME_COLOR` env var
3. Template structure in `templates/` uses Jinja2 inheritance from `base.html`

### Configure for Production
1. Set `DEBUG=False` in `.env`
2. Generate new `SECRET_KEY`: `python -c "import secrets; print(secrets.token_hex(32))"`
3. Configure `LLM_ENDPOINT` to point to production API
4. Set `ENABLE_AUTO_CLEANUP=True` to enable file cleanup
5. Run with Gunicorn: `gunicorn -c gunicorn_config.py app:app`

## Error Handling Patterns

### File Upload Errors
- Invalid extension: Flash warning, skip file, continue with others
- Size violation: Flash error, reject file
- Save failure: Flash error, skip file

### Processing Errors
- LLM API unreachable: Show friendly error with troubleshooting hint
- PDF corrupted: Try OCR, if fails show specific error
- Timeout: Suggest increasing `LLM_TIMEOUT` in .env

### Implementation Detail
- Each file processed independently so batch doesn't fail if one file errors
- Errors collected in `errors[]` list and displayed on results page
- Full tracebacks only logged when `VERBOSE_LOGGING=True`

## Deployment Notes

### Local Development
- Run `python app.py` (Flask development server, auto-reloads)
- Session type defaults to `filesystem` (stores in `flask_session/`)
- Logs to stdout/stderr

### Production Server
- Use Gunicorn: `gunicorn -c gunicorn_config.py app:app`
- Configure reverse proxy (nginx) to handle static files
- Set `MAX_CONTENT_LENGTH` in nginx to match or exceed `MAX_UPLOAD_SIZE`
- Session type can be `filesystem` (default) or integrate Redis

### AWS Lambda
- Entry point: `lambda_handler.py::lambda_handler`
- Uses Mangum adapter for WSGI→ASGI conversion
- Temp files stored in `/tmp/` (Lambda scratch space)
- Max execution time: Configure timeout for long PDF processing
- Package: See `deployment/` directory and `Dockerfile.lambda`

## Common Issues & Debugging

### "Cannot connect to LLM API"
- Check `LLM_ENDPOINT` in `.env` is correct and reachable
- Verify API server is running (e.g., `ollama serve`)
- Ensure endpoint includes `/v1` path (app normalizes this automatically)

### PDF Processing Slow
- Reduce `PDF_DPI_SCALE` from 2.0 to 1.5 or 1.0 for faster rendering
- Use simpler LLM model for OCR
- Increase `LLM_TIMEOUT` if API is slow

### Session Lost After Reload
- If using `SESSION_TYPE=filesystem`, files stored in `flask_session/`
- If using Lambda, session must fit in cookies (default Flask behavior)
- Increase `PERMANENT_SESSION_LIFETIME` if session expires too quickly

### Memory Issues in Lambda
- Large PDFs use significant memory during rendering
- Consider splitting large PDFs before upload
- Monitor `/tmp/` disk usage (Lambda allocates 10GB ephemeral storage)

## Testing

No test suite currently exists. To add tests:
1. Create `tests/test_app.py` with pytest fixtures
2. Test routes with Flask test client
3. Test file conversions with sample fixtures in `tests/fixtures/`
4. Mock LLM API responses for unit testing

## Dependencies

Key packages (see `requirements.txt`):
- **flask**: Web framework
- **python-dotenv**: Environment config
- **requests**: HTTP for LLM API calls
- **pymupdf4llm**: PDF processing optimized for LLM
- **pymupdf-layout**: PDF layout analysis
- **markitdown**: Markdown conversion utilities
- **gunicorn**: Production WSGI server
- **mangum**: Lambda ASGI adapter
- **Flask-Session**: Server-side session storage

## Environment Troubleshooting

When debugging environment/configuration issues:
1. Verify `.env` file exists and is readable
2. App logs config at startup if `DEBUG_PATHS=true` in env
3. Check `VERBOSE_LOGGING=True` for detailed execution logs
4. Use `DEBUG=True` for Flask debug toolbar and detailed error pages

## Key Code Locations

- Flash messages & error display: `templates/base.html` (renders Flask flash queue)
- Upload form validation: `templates/index.html` (client-side + server-side in `upload_files()`)
- Results display: `templates/result.html` (handles single file vs ZIP modes)
- API call construction: `extract_text_from_image()` lines 200-217 (chat completions format)
- PDF complexity analysis: `analyze_page_complexity()` lines 259-301 (determines OCR vs native)
- Session management: Flask session dict throughout `app.py` (stored in cookies or filesystem)
