import os
import uuid
import time
import base64
import zipfile
from datetime import datetime, timedelta
from io import BytesIO
from pathlib import Path
from werkzeug.utils import secure_filename
from flask import Flask, render_template, request, redirect, url_for, flash, session, send_file
from flask_session import Session
from dotenv import load_dotenv
import requests
import fitz  # PyMuPDF
from PIL import Image

# Load environment variables
load_dotenv()

# Initialize Flask app
app = Flask(__name__)

# Configuration
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'change-this-to-a-random-secret-key')
app.config['MAX_CONTENT_LENGTH'] = int(os.getenv('MAX_UPLOAD_SIZE', 16777216))
app.config['UPLOAD_FOLDER'] = os.getenv('UPLOAD_FOLDER', 'uploads')
app.config['RESULT_FOLDER'] = os.getenv('RESULT_FOLDER', 'results')
app.config['SESSION_TYPE'] = os.getenv('SESSION_TYPE', 'filesystem')
app.config['SESSION_FILE_DIR'] = os.getenv('SESSION_FILE_DIR', 'flask_session')
app.config['SESSION_PERMANENT'] = os.getenv('SESSION_PERMANENT', 'False').lower() == 'true'
app.config['PERMANENT_SESSION_LIFETIME'] = int(os.getenv('PERMANENT_SESSION_LIFETIME', 86400))

# Initialize session
Session(app)

# Application settings
APP_NAME = os.getenv('APP_NAME', 'The Markdown Redemption')
APP_TAGLINE = os.getenv('APP_TAGLINE', 'Every document deserves a second chance')
THEME_COLOR = os.getenv('THEME_COLOR', '#4A90E2')
ALLOWED_EXTENSIONS = set(os.getenv('ALLOWED_EXTENSIONS', 'jpg,jpeg,png,gif,bmp,webp,pdf').split(','))
MAX_CONCURRENT_UPLOADS = int(os.getenv('MAX_CONCURRENT_UPLOADS', 10))

# LLM Configuration
LLM_ENDPOINT = os.getenv('LLM_ENDPOINT', 'http://localhost:11434/v1')
LLM_MODEL = os.getenv('LLM_MODEL', 'qwen2.5vl:latest')
LLM_API_KEY = os.getenv('LLM_API_KEY', '')
LLM_TIMEOUT = int(os.getenv('LLM_TIMEOUT', 120))

# Document processing options
PDF_DPI_SCALE = float(os.getenv('PDF_DPI_SCALE', 2.0))
PDF_PAGE_SEPARATOR = os.getenv('PDF_PAGE_SEPARATOR', '---')
ZIP_COMPRESSION_LEVEL = int(os.getenv('ZIP_COMPRESSION_LEVEL', 9))

# Cleanup configuration
CLEANUP_HOURS = int(os.getenv('CLEANUP_HOURS', 24))
ENABLE_AUTO_CLEANUP = os.getenv('ENABLE_AUTO_CLEANUP', 'True').lower() == 'true'

# Advanced options
EXTRACTION_PROMPT = os.getenv('EXTRACTION_PROMPT', '')
VERBOSE_LOGGING = os.getenv('VERBOSE_LOGGING', 'False').lower() == 'true'

# Ensure directories exist
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
os.makedirs(app.config['RESULT_FOLDER'], exist_ok=True)
os.makedirs(app.config['SESSION_FILE_DIR'], exist_ok=True)

# Normalize LLM endpoint to ensure /v1 path
def normalize_endpoint(endpoint):
    """Ensure endpoint has /v1 path"""
    endpoint = endpoint.rstrip('/')
    if not endpoint.endswith('/v1'):
        endpoint = f"{endpoint}/v1"
    return endpoint

LLM_ENDPOINT = normalize_endpoint(LLM_ENDPOINT)

# Helper functions
def allowed_file(filename):
    """Check if file extension is allowed"""
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def get_file_size_mb(size_bytes):
    """Convert bytes to human-readable format"""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size_bytes < 1024.0:
            return f"{size_bytes:.2f} {unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.2f} TB"

def cleanup_old_files():
    """Remove files older than CLEANUP_HOURS"""
    if not ENABLE_AUTO_CLEANUP:
        return
    
    cutoff_time = time.time() - (CLEANUP_HOURS * 3600)
    
    for folder in [app.config['UPLOAD_FOLDER'], app.config['RESULT_FOLDER']]:
        if not os.path.exists(folder):
            continue
        
        for session_dir in os.listdir(folder):
            session_path = os.path.join(folder, session_dir)
            if os.path.isdir(session_path):
                try:
                    dir_mtime = os.path.getmtime(session_path)
                    if dir_mtime < cutoff_time:
                        import shutil
                        shutil.rmtree(session_path)
                        if VERBOSE_LOGGING:
                            print(f"Cleaned up old session: {session_dir}")
                except Exception as e:
                    if VERBOSE_LOGGING:
                        print(f"Cleanup error for {session_dir}: {e}")

def image_to_base64(image_path):
    """Convert image to base64 string"""
    with open(image_path, 'rb') as img_file:
        return base64.b64encode(img_file.read()).decode('utf-8')

def extract_text_from_image(image_path):
    """Extract text from image using LLM vision API"""
    try:
        # Read and encode image
        img_base64 = image_to_base64(image_path)
        
        # Determine image format
        ext = os.path.splitext(image_path)[1].lower().lstrip('.')
        mime_map = {
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'png': 'image/png',
            'gif': 'image/gif',
            'bmp': 'image/bmp',
            'webp': 'image/webp'
        }
        mime_type = mime_map.get(ext, 'image/jpeg')
        
        # Prepare prompt
        prompt = EXTRACTION_PROMPT if EXTRACTION_PROMPT else (
            "Extract all text from this image and convert it to clean Markdown format. "
            "Preserve the document structure, headings, lists, tables, and formatting. "
            "If there are multiple columns, read left to right, top to bottom. "
            "Return only the extracted text in Markdown format, without any additional commentary."
        )
        
        # Prepare API request
        headers = {'Content-Type': 'application/json'}
        if LLM_API_KEY:
            headers['Authorization'] = f'Bearer {LLM_API_KEY}'
        
        payload = {
            "model": LLM_MODEL,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:{mime_type};base64,{img_base64}"
                            }
                        }
                    ]
                }
            ],
            "max_tokens": 4096
        }
        
        # Make API request
        response = requests.post(
            f"{LLM_ENDPOINT}/chat/completions",
            headers=headers,
            json=payload,
            timeout=LLM_TIMEOUT
        )
        response.raise_for_status()
        
        # Extract response
        result = response.json()
        markdown_text = result['choices'][0]['message']['content']

        # Remove markdown code fences if present
        markdown_text = markdown_text.strip()

        # Remove ```markdown and ``` wrapper if LLM added them
        if markdown_text.startswith('```markdown'):
            markdown_text = markdown_text[len('```markdown'):].lstrip('\n')
        elif markdown_text.startswith('```'):
            markdown_text = markdown_text[3:].lstrip('\n')

        if markdown_text.endswith('```'):
            markdown_text = markdown_text[:-3].rstrip('\n')

        return markdown_text.strip()
    
    except requests.exceptions.Timeout:
        raise Exception("API request timed out")
    except requests.exceptions.RequestException as e:
        raise Exception(f"API request failed: {str(e)}")
    except Exception as e:
        raise Exception(f"Failed to extract text: {str(e)}")

def analyze_page_complexity(page):
    """Analyze if a page needs AI/OCR or can use native extraction"""
    page_rect = page.rect
    page_area = page_rect.width * page_rect.height

    # Check for tables
    tables = page.find_tables()
    if tables and len(tables.tables) > 0:
        return True, "tables detected"

    # Check for images
    images = page.get_images()
    meaningful_images = 0

    for img in images:
        try:
            # Get image dimensions
            xref = img[0]
            bbox = page.get_image_bbox(img)
            if bbox:
                img_area = abs((bbox.x1 - bbox.x0) * (bbox.y1 - bbox.y0))
                img_percent = (img_area / page_area) * 100

                # Check if image is in header/footer zone (top/bottom 5%)
                page_height = page_rect.height
                in_header = bbox.y0 < (page_height * 0.05)
                in_footer = bbox.y1 > (page_height * 0.95)

                # Skip small images or header/footer images
                if img_percent > 10 and not (in_header or in_footer):
                    meaningful_images += 1
        except:
            pass

    if meaningful_images > 0:
        return True, f"{meaningful_images} meaningful image(s)"

    # Try to extract text to check if it's readable
    text = page.get_text()
    if not text or len(text.strip()) < 50:
        return True, "minimal text (possibly scanned)"

    return False, "simple text document"

def extract_text_from_pdf_native(pdf_path):
    """Extract text from PDF using PyMuPDF's native markdown extraction"""
    try:
        doc = fitz.open(pdf_path)
        markdown_pages = []

        for page_num in range(len(doc)):
            page = doc[page_num]
            # Use PyMuPDF's built-in markdown extraction
            page_markdown = page.get_text("markdown")
            markdown_pages.append(page_markdown)

        doc.close()

        # Combine pages with separator
        result = []
        for i, page_content in enumerate(markdown_pages):
            if i > 0:
                result.append(f"\n\n---------- Page {i + 1} ----------\n\n")
            result.append(page_content)

        return ''.join(result)

    except Exception as e:
        raise Exception(f"Failed to extract text with PyMuPDF: {str(e)}")

def extract_text_from_pdf_ocr(pdf_path):
    """Extract text from PDF by converting pages to images and processing with LLM"""
    try:
        doc = fitz.open(pdf_path)
        markdown_pages = []

        for page_num in range(len(doc)):
            page = doc[page_num]

            # Render page to image
            mat = fitz.Matrix(PDF_DPI_SCALE, PDF_DPI_SCALE)
            pix = page.get_pixmap(matrix=mat)

            # Save temporary image
            temp_image_path = os.path.join(
                app.config['UPLOAD_FOLDER'],
                f'temp_page_{uuid.uuid4()}.png'
            )
            pix.save(temp_image_path)

            try:
                # Extract text from image
                page_markdown = extract_text_from_image(temp_image_path)
                markdown_pages.append(page_markdown)
            finally:
                # Clean up temp image
                if os.path.exists(temp_image_path):
                    os.remove(temp_image_path)

        doc.close()

        # Combine pages with separator (skip separator before first page)
        result = []
        for i, page_content in enumerate(markdown_pages):
            if i > 0:  # Add separator before page 2 and onwards
                result.append(f"\n\n---------- Page {i + 1} ----------\n\n")
            result.append(page_content)

        return ''.join(result)

    except Exception as e:
        raise Exception(f"Failed to process PDF with OCR: {str(e)}")

def extract_text_from_pdf(pdf_path, mode='auto'):
    """
    Extract text from PDF with smart mode selection

    mode: 'auto' (detect best method), 'ocr' (force AI/OCR), 'native' (force PyMuPDF)
    """
    if mode == 'ocr':
        return extract_text_from_pdf_ocr(pdf_path)
    elif mode == 'native':
        return extract_text_from_pdf_native(pdf_path)
    else:  # auto mode
        try:
            doc = fitz.open(pdf_path)

            # Analyze first few pages to determine method
            use_ocr = False
            reasons = []
            pages_to_check = min(3, len(doc))  # Check first 3 pages

            for page_num in range(pages_to_check):
                page = doc[page_num]
                needs_ocr, reason = analyze_page_complexity(page)
                if needs_ocr:
                    use_ocr = True
                    reasons.append(f"Page {page_num + 1}: {reason}")

            doc.close()

            if use_ocr:
                if VERBOSE_LOGGING:
                    print(f"Using OCR mode for {pdf_path}: {', '.join(reasons)}")
                return extract_text_from_pdf_ocr(pdf_path)
            else:
                if VERBOSE_LOGGING:
                    print(f"Using native extraction for {pdf_path}: simple text document")
                return extract_text_from_pdf_native(pdf_path)

        except Exception as e:
            # Fallback to OCR if analysis fails
            if VERBOSE_LOGGING:
                print(f"Analysis failed, falling back to OCR: {str(e)}")
            return extract_text_from_pdf_ocr(pdf_path)
    
    except Exception as e:
        raise Exception(f"Failed to process PDF: {str(e)}")

def process_file(file_path, original_filename, conversion_mode='auto'):
    """Process a single file and return markdown text"""
    ext = os.path.splitext(original_filename)[1].lower().lstrip('.')

    if ext == 'pdf':
        return extract_text_from_pdf(file_path, mode=conversion_mode)
    else:
        return extract_text_from_image(file_path)

# Routes
@app.route('/')
def index():
    """Display upload page"""
    cleanup_old_files()
    
    return render_template(
        'index.html',
        app_name=APP_NAME,
        app_tagline=APP_TAGLINE,
        theme_color=THEME_COLOR,
        max_size_mb=app.config['MAX_CONTENT_LENGTH'] // (1024 * 1024),
        max_files=MAX_CONCURRENT_UPLOADS,
        allowed_extensions=', '.join(sorted(ALLOWED_EXTENSIONS))
    )

@app.route('/upload', methods=['POST'])
def upload_files():
    """Handle file upload"""
    try:
        # Check if files were provided
        if 'files[]' not in request.files and 'files' not in request.files:
            flash('No files selected', 'error')
            return redirect(url_for('index'))
        
        files = request.files.getlist('files[]') or request.files.getlist('files')
        
        if not files or all(f.filename == '' for f in files):
            flash('No files selected', 'error')
            return redirect(url_for('index'))
        
        # Validate file count
        if len(files) > MAX_CONCURRENT_UPLOADS:
            flash(f'Maximum {MAX_CONCURRENT_UPLOADS} files allowed per upload', 'error')
            return redirect(url_for('index'))

        # Get conversion mode from form
        conversion_mode = request.form.get('conversion_mode', 'auto')
        if conversion_mode not in ['auto', 'ocr', 'native']:
            conversion_mode = 'auto'

        # Generate session ID
        session_id = str(uuid.uuid4())
        session_dir = os.path.join(app.config['UPLOAD_FOLDER'], session_id)
        os.makedirs(session_dir, exist_ok=True)
        
        # Process and save files
        saved_files = []
        for file in files:
            if file.filename == '':
                continue
            
            if not allowed_file(file.filename):
                flash(f'File type not allowed: {file.filename}', 'warning')
                continue
            
            # Secure filename and save
            original_filename = secure_filename(file.filename)
            saved_filename = f"{uuid.uuid4()}_{original_filename}"
            file_path = os.path.join(session_dir, saved_filename)
            
            try:
                file.save(file_path)
                file_size = os.path.getsize(file_path)
                
                saved_files.append({
                    'original_name': original_filename,
                    'saved_name': saved_filename,
                    'size': file_size
                })
            except Exception as e:
                flash(f'Failed to save file: {original_filename}', 'error')
                if VERBOSE_LOGGING:
                    print(f"File save error: {e}")
        
        if not saved_files:
            flash('No valid files were uploaded', 'error')
            return redirect(url_for('index'))
        
        # Store session data
        session['session_id'] = session_id
        session['files'] = saved_files
        session['conversion_mode'] = conversion_mode
        session['upload_timestamp'] = datetime.now().isoformat()
        
        return redirect(url_for('process_documents'))
    
    except Exception as e:
        flash('An error occurred during upload', 'error')
        if VERBOSE_LOGGING:
            print(f"Upload error: {e}")
        return redirect(url_for('index'))

@app.route('/process')
def process_documents():
    """Process uploaded documents"""
    # Validate session
    if 'session_id' not in session or 'files' not in session:
        flash('No files to process', 'error')
        return redirect(url_for('index'))
    
    session_id = session['session_id']
    files = session['files']
    conversion_mode = session.get('conversion_mode', 'auto')
    session_dir = os.path.join(app.config['UPLOAD_FOLDER'], session_id)
    result_dir = os.path.join(app.config['RESULT_FOLDER'], session_id)
    os.makedirs(result_dir, exist_ok=True)

    results = []
    errors = []

    # Process each file
    for file_info in files:
        file_path = os.path.join(session_dir, file_info['saved_name'])
        original_name = file_info['original_name']

        try:
            markdown_text = process_file(file_path, original_name, conversion_mode)
            
            # Save markdown file
            md_filename = os.path.splitext(original_name)[0] + '.md'
            md_path = os.path.join(result_dir, md_filename)
            
            with open(md_path, 'w', encoding='utf-8') as f:
                f.write(markdown_text)
            
            results.append({
                'original_name': original_name,
                'md_filename': md_filename,
                'content': markdown_text
            })
        
        except Exception as e:
            error_msg = str(e)
            errors.append({
                'filename': original_name,
                'error': error_msg
            })
            if VERBOSE_LOGGING:
                print(f"Processing error for {original_name}: {error_msg}")
    
    # Clean up upload directory
    try:
        import shutil
        shutil.rmtree(session_dir)
    except:
        pass
    
    if not results:
        flash('All files failed to process', 'error')
        return redirect(url_for('index'))
    
    # Create output file(s)
    if len(results) == 1:
        # Single file - serve markdown directly
        result_type = 'single'
        result_filename = results[0]['md_filename']
        markdown_preview = results[0]['content'][:500] + ('...' if len(results[0]['content']) > 500 else '')
    else:
        # Multiple files - create ZIP
        result_type = 'zip'
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        result_filename = f'converted_{timestamp}.zip'
        zip_path = os.path.join(result_dir, result_filename)
        
        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=ZIP_COMPRESSION_LEVEL) as zipf:
            for result in results:
                md_path = os.path.join(result_dir, result['md_filename'])
                zipf.write(md_path, result['md_filename'])
        
        markdown_preview = None
    
    # Store result info in session
    session['result_type'] = result_type
    session['result_filename'] = result_filename
    session['success_count'] = len(results)
    session['error_count'] = len(errors)
    session['errors'] = errors
    session['processed_files'] = [r['md_filename'] for r in results]
    
    if result_type == 'single':
        session['markdown_preview'] = markdown_preview
        session['full_content'] = results[0]['content']
    
    # Calculate file size
    if result_type == 'single':
        result_path = os.path.join(result_dir, result_filename)
    else:
        result_path = zip_path
    
    file_size = os.path.getsize(result_path)
    session['download_size'] = get_file_size_mb(file_size)
    
    return render_template(
        'result.html',
        app_name=APP_NAME,
        result_type=result_type,
        result_filename=result_filename,
        success_count=len(results),
        error_count=len(errors),
        errors=errors,
        markdown_preview=markdown_preview if result_type == 'single' else None,
        full_content=results[0]['content'] if result_type == 'single' else None,
        file_list=[r['md_filename'] for r in results],
        download_size=get_file_size_mb(file_size)
    )

@app.route('/download')
def download_file():
    """Serve converted file for download"""
    # Validate session
    if 'session_id' not in session or 'result_filename' not in session:
        flash('Download not available', 'error')
        return redirect(url_for('index'))
    
    session_id = session['session_id']
    result_filename = session['result_filename']
    result_type = session.get('result_type', 'single')
    result_dir = os.path.join(app.config['RESULT_FOLDER'], session_id)
    
    file_path = os.path.join(result_dir, result_filename)
    
    if not os.path.exists(file_path):
        flash('File not found or has been cleaned up', 'error')
        return redirect(url_for('index'))
    
    # Set appropriate MIME type
    if result_type == 'zip':
        mimetype = 'application/zip'
    else:
        mimetype = 'text/markdown'
    
    return send_file(
        file_path,
        mimetype=mimetype,
        as_attachment=True,
        download_name=result_filename
    )

if __name__ == '__main__':
    host = os.getenv('HOST', '0.0.0.0')
    port = int(os.getenv('PORT', 5000))
    debug = os.getenv('DEBUG', 'True').lower() == 'true'
    
    app.run(host=host, port=port, debug=debug)
