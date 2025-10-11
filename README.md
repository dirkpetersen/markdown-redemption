# The Markdown Redemption

> *"Every document deserves a second chance"*

Transform locked documents into clean, portable Markdown using vision-language AI models. The Markdown Redemption is a Flask-based web application that liberates text from images and PDFs, converting them to beautifully formatted Markdown files.

<img width="558" height="500" alt="image" src="https://github.com/user-attachments/assets/2845ddff-117b-4f1e-951c-043e540b6986" />


## Features

- 🔓 **Liberation**: Free your text from locked PDFs and image formats
- 🤖 **AI-Powered**: Advanced vision models understand document structure
- 📝 **Clean Output**: Get properly formatted Markdown with preserved structure
- 🚀 **Batch Processing**: Convert multiple files at once
- 💾 **Easy Download**: Single files or ZIP archives for batch conversions
- 🎨 **Beautiful UI**: Modern, responsive interface with drag-and-drop support
- 🔒 **Privacy-First**: Automatic file cleanup after 24 hours

## Supported Formats

- **Images**: JPG, JPEG, PNG, GIF, BMP, WebP
- **Documents**: PDF (multi-page support)

## Quick Start

### Prerequisites

- Python 3.8+
- Vision-capable LLM API endpoint (Ollama, OpenAI, or compatible)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/markdown-redemption.git
   cd markdown-redemption
   ```

2. **Create virtual environment**
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

4. **Configure environment**
   ```bash
   cp .env.default .env
   # Edit .env with your settings (see Configuration section)
   ```

5. **Run the application**
   ```bash
   python app.py
   ```

6. **Open your browser**
   Navigate to `http://localhost:5000`

## Configuration

Copy `.env.default` to `.env` and customize the following settings:

### LLM API Configuration

```bash
# OpenAI-compatible API endpoint
LLM_ENDPOINT=http://192.168.1.100:8000/v1  # The /v1 path will be added if missing
LLM_MODEL=qwen2.5vl:latest
LLM_API_KEY=your-api-key-here  # Optional for local models
LLM_TIMEOUT=120
```

### Using with Ollama

If you're running Ollama locally:

```bash
LLM_ENDPOINT=http://localhost:11434/v1
LLM_MODEL=qwen2.5vl:latest
LLM_API_KEY=  # Leave empty for Ollama
```

### Using with OpenAI

```bash
LLM_ENDPOINT=https://api.openai.com/v1
LLM_MODEL=gpt-4-vision-preview
LLM_API_KEY=sk-your-openai-api-key
```

### Application Settings

```bash
# Flask settings
SECRET_KEY=your-secret-key-here  # Generate with: python -c "import secrets; print(secrets.token_hex(32))"
HOST=0.0.0.0
PORT=5000
DEBUG=True  # Set to False in production

# Upload limits
MAX_UPLOAD_SIZE=16777216  # 16MB in bytes
MAX_CONCURRENT_UPLOADS=10
ALLOWED_EXTENSIONS=jpg,jpeg,png,gif,bmp,webp,pdf

# Cleanup
CLEANUP_HOURS=24
ENABLE_AUTO_CLEANUP=True
```

## Usage

### Web Interface

1. **Upload Files**
   - Drag and drop files onto the upload zone
   - Or click to browse and select files
   - Maximum 10 files per batch, 16MB per file

2. **Processing**
   - Files are processed synchronously
   - Progress indicator shows current status

3. **Download Results**
   - Single file: Download Markdown or copy to clipboard
   - Multiple files: Download ZIP archive with all converted files

### API Endpoint Requirements

The application requires an OpenAI-compatible vision API endpoint. The endpoint should:

- Accept POST requests to `/v1/chat/completions`
- Support multimodal messages (text + images)
- Accept base64-encoded images with `data:` URLs
- Return responses in OpenAI chat completion format

Example request format:
```json
{
  "model": "qwen2.5vl:latest",
  "messages": [
    {
      "role": "user",
      "content": [
        {"type": "text", "text": "Extract text from this image..."},
        {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,..."}}
      ]
    }
  ],
  "max_tokens": 4096
}
```

## Project Structure

```
markdown-redemption/
├── app.py                 # Main Flask application
├── gunicorn_config.py     # Gunicorn configuration with timeout handling
├── requirements.txt       # Python dependencies
├── .env.default          # Configuration template
├── .env                  # Your configuration (gitignored)
├── .gitignore
├── README.md
├── CLAUDE.md            # Full specification document
├── templates/
│   ├── base.html        # Base template with header/footer
│   ├── index.html       # Upload page
│   └── result.html      # Results/download page
├── static/
│   ├── css/
│   │   └── style.css    # Application styles
│   ├── js/
│   │   └── upload.js    # Drag-and-drop functionality
│   └── images/
│       ├── logo.svg     # Application logo
│       └── favicon.ico
├── uploads/             # Temporary upload storage (auto-created)
├── results/             # Temporary results storage (auto-created)
└── flask_session/       # Session storage (auto-created)
```

## Deployment

### Production Settings

Update your `.env` file:

```bash
FLASK_ENV=production
DEBUG=False
SECRET_KEY=generate-a-strong-random-key
ENABLE_AUTO_CLEANUP=True
```

### Using Gunicorn

```bash
gunicorn -w 4 -b 0.0.0.0:5000 app:app
```

### Systemd Service Example

Create `/etc/systemd/system/markdown-redemption.service`:

```ini
[Unit]
Description=The Markdown Redemption
After=network.target

[Service]
User=www-data
WorkingDirectory=/path/to/markdown-redemption
Environment="PATH=/path/to/markdown-redemption/venv/bin"
ExecStart=/path/to/markdown-redemption/venv/bin/gunicorn -w 4 -b 127.0.0.1:5000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
```

### Nginx Reverse Proxy

```nginx
server {
    listen 80;
    server_name your-domain.com;

    client_max_body_size 20M;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /static {
        alias /path/to/markdown-redemption/static;
        expires 30d;
    }
}
```

## Troubleshooting

### API Connection Issues

```bash
# Test your LLM endpoint
curl -X POST http://your-endpoint/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"your-model","messages":[{"role":"user","content":"Hello"}]}'
```

### File Upload Errors

- Check `MAX_UPLOAD_SIZE` in `.env`
- Ensure `uploads/` and `results/` directories are writable
- Verify file extensions are in `ALLOWED_EXTENSIONS`

### Session Issues

- Ensure `flask_session/` directory exists and is writable
- Check `SESSION_TYPE=filesystem` in config
- Clear old sessions: `rm -rf flask_session/*`

### Cleanup Not Working

- Verify `ENABLE_AUTO_CLEANUP=True`
- Check directory permissions
- Manually trigger: `python -c "from app import cleanup_old_files; cleanup_old_files()"`

## Development

### Running Tests

```bash
# Tests coming soon
pytest tests/
```

### Code Structure

- `app.py`: All application logic (routes, processing, utilities)
- Session-based file tracking with automatic cleanup
- Synchronous processing for simplicity
- Server-side sessions to avoid cookie size limits

## Privacy & Security

- Files are stored temporarily with UUID-based session identifiers
- Automatic cleanup removes files after 24 hours (configurable)
- No database or permanent storage
- Session cookies are HTTP-only and signed
- File extensions and MIME types are validated
- Secure filename handling prevents path traversal

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - see LICENSE file for details

## Acknowledgments

- Built with Flask, PyMuPDF, and PIL
- Inspired by the desire to free text from proprietary formats
- Named after "The Shawshank Redemption" - because documents deserve freedom too

## Support

- Issues: [GitHub Issues](https://github.com/yourusername/markdown-redemption/issues)
- Documentation: See `CLAUDE.md` for complete specification

---

*"Hope is a good thing, maybe the best of formats, and no good format ever dies."*
