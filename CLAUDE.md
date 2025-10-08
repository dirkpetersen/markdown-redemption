
# The Markdown Redemption - Complete Requirements Specification

## Project Identity

**Application Name**: The Markdown Redemption  
**Repository Name**: `markdown-redemption`  
**Tagline**: "Every document deserves a second chance"  
**Mission**: Transform locked documents into clean, portable Markdown using vision-language AI models

## Executive Summary

The Markdown Redemption is a Flask-based web application that liberates text from images and PDFs by converting them to Markdown format. Users upload one or multiple documents, the application processes them through a vision-capable language model, and returns clean Markdown files ready for download. Single files are offered as direct downloads; multiple files are bundled into a ZIP archive.

This application transforms the existing CLI tool into a user-friendly web interface while maintaining the same core conversion capabilities. Configuration is handled entirely through environment variables, and the system automatically cleans up temporary files to prevent disk bloat.

---

## Table of Contents

1. [Technology Stack](#technology-stack)
2. [Repository Structure](#repository-structure)
3. [Environment Configuration](#environment-configuration)
4. [Branding & Visual Identity](#branding--visual-identity)
5. [User Interface Specifications](#user-interface-specifications)
6. [Application Routes & Flow](#application-routes--flow)
7. [Core Functionality](#core-functionality)
8. [File Processing Logic](#file-processing-logic)
9. [Error Handling Strategy](#error-handling-strategy)
10. [Security Requirements](#security-requirements)
11. [Performance Requirements](#performance-requirements)
12. [Deployment Specifications](#deployment-specifications)
13. [Testing Strategy](#testing-strategy)
14. [Documentation Requirements](#documentation-requirements)
15. [Future Enhancements](#future-enhancements)

---

## Technology Stack

### Backend Framework
**Flask 3.0+** serves as the web framework, chosen for its simplicity, extensive documentation, and suitability for this application's scope.

### Configuration Management
**python-dotenv** replaces tomllib for environment variable management, providing Python version independence and industry-standard configuration practices.

### File Processing Libraries
- **PyMuPDF (fitz)**: PDF rendering and page extraction
- **Pillow (PIL)**: Image validation and manipulation
- **zipfile**: Standard library for ZIP archive creation

### HTTP & API Communication
**requests** library handles all communication with vision-language model APIs, supporting both local (Ollama) and cloud (OpenAI) endpoints.

### Template Engine
**Jinja2** (included with Flask) for server-side HTML rendering with template inheritance.

### Session Management
**Flask sessions** with secure cookie-based storage for tracking user upload batches.

### Production Server
**Gunicorn** as the WSGI HTTP server for production deployments.

---

## Repository Structure

### Root Directory Files

**app.py**: Main Flask application file containing all routes, processing logic, and utility functions.

**.env.default**: Template configuration file with all settings documented. Users copy this to `.env` and customize.

**.env**: User's actual configuration (must be gitignored). Contains secrets like API keys.

**.gitignore**: Excludes `.env`, `uploads/`, `results/`, `__pycache__/`, `*.pyc`, `.DS_Store`, and other development artifacts.

**requirements.txt**: Python package dependencies with pinned versions for reproducibility.

**README.md**: Comprehensive setup and usage guide, API configuration instructions, troubleshooting, and deployment notes.

**LICENSE**: Open source license (recommend MIT or Apache 2.0).

### Directory Structure

**templates/**: Jinja2 HTML templates
- `base.html`: Master template with header, footer, navigation, and flash message display
- `index.html`: Upload page with drag-and-drop zone and file selection
- `processing.html`: Optional intermediate page showing processing status
- `result.html`: Results page with download buttons and file lists

**static/**: Client-side assets served directly
- `css/style.css`: All application styles, responsive breakpoints, and theme colors
- `js/upload.js`: Optional client-side file validation and drag-and-drop enhancements
- `images/logo.svg`: The Markdown Redemption logo
- `images/favicon.ico`: Browser icon
- `images/icons/`: UI icons (upload, download, success, error, etc.)

**uploads/**: Temporary storage for uploaded files, organized by session ID subdirectories. Automatically cleaned after configured time period. Must be gitignored.

**results/**: Temporary storage for converted Markdown files and ZIP archives, organized by session ID. Automatically cleaned. Must be gitignored.

**tests/**: Future test suite directory
- `test_app.py`: Flask route and integration tests
- `test_conversion.py`: Document processing unit tests
- `fixtures/`: Sample documents for testing

---

## Environment Configuration

### Configuration File Strategy

Create `.env.default` as a committed template containing every configuration option with safe default values and detailed comments. Users copy this to `.env` and customize sensitive values.

### Required Configuration Sections

#### Flask Application Settings

**FLASK_ENV**: Environment mode - `development` or `production`. Controls debug features and error verbosity.

**SECRET_KEY**: Cryptographically secure random string for session signing. Must be changed from default in production. Generate with Python's `secrets.token_hex(32)`.

**HOST**: IP address to bind to. Use `0.0.0.0` to accept connections on all interfaces, or `127.0.0.1` for localhost only.

**PORT**: TCP port number for the application, typically `5000` for development.

**DEBUG**: Boolean flag enabling Flask debug mode with auto-reload and detailed error pages. Must be `False` in production.

#### Application Identity

**APP_NAME**: Display name shown in header and page titles. Default: "The Markdown Redemption"

**APP_TAGLINE**: Subtitle text shown below the application name. Default: "Every document deserves a second chance"

**THEME_COLOR**: Primary brand color in hex format. Default: "#4A90E2" (Hope Blue)

#### File Upload Configuration

**MAX_UPLOAD_SIZE**: Maximum file size in bytes. Default: `16777216` (16MB). Also configure this in nginx/Apache if using reverse proxy.

**UPLOAD_FOLDER**: Directory path for temporary uploaded files. Default: `uploads`

**RESULT_FOLDER**: Directory path for converted output files. Default: `results`

**ALLOWED_EXTENSIONS**: Comma-separated list of allowed file extensions. Default: `jpg,jpeg,png,gif,bmp,webp,pdf`

**MAX_CONCURRENT_UPLOADS**: Maximum number of files accepted in a single batch. Default: `10`

#### LLM API Configuration

**LLM_ENDPOINT**: Full URL to OpenAI-compatible chat completions API. Default: `http://localhost:11434/v1/chat/completions` (Ollama)

**LLM_MODEL**: Model identifier to use for conversions. Default: `qwen2.5vl:latest`

**LLM_API_KEY**: Bearer token for API authentication. Leave empty for local models that don't require authentication.

**LLM_TIMEOUT**: Request timeout in seconds before considering API call failed. Default: `120`

#### Alternative OpenAI Settings

**OPENAI_API_KEY**: OpenAI API key (starts with `sk-`). Used as fallback if `LLM_API_KEY` is empty.

**OPENAI_MODEL**: OpenAI model name. Example: `gpt-4-vision-preview`

**OPENAI_ENDPOINT**: OpenAI API endpoint URL. Default: `https://api.openai.com/v1/chat/completions`

#### Automatic Cleanup Configuration

**CLEANUP_HOURS**: Number of hours after which temporary files are automatically deleted. Default: `24`

**ENABLE_AUTO_CLEANUP**: Boolean flag to enable/disable automatic cleanup. Set to `false` if managing cleanup externally.

#### Document Processing Options

**PDF_DPI_SCALE**: Scaling factor for PDF rendering quality. Default: `2.0` equals approximately 144 DPI. Higher values produce better OCR but larger files.

**PDF_PAGE_SEPARATOR**: Markdown text inserted between PDF pages. Default: `---` (horizontal rule)

**ZIP_COMPRESSION_LEVEL**: ZIP compression level from 0 (none) to 9 (maximum). Default: `9`

#### Advanced Customization

**EXTRACTION_PROMPT**: Full text of the prompt sent to the LLM for text extraction. Allows customization of conversion instructions without code changes.

**VERBOSE_LOGGING**: Boolean flag enabling detailed application logs for debugging.

**SAVE_DEBUG_IMAGES**: Boolean flag to save intermediate rendered images for troubleshooting PDF conversion issues.

### Environment Variable Precedence

The application checks for configuration values in this order:
1. Environment variables set in the shell or `.env` file
2. Default values hard-coded in `app.py` as fallbacks

API key resolution specifically follows:
1. `LLM_API_KEY` environment variable
2. `OPENAI_API_KEY` environment variable  
3. No authentication (for local models)

---

## Branding & Visual Identity

### Application Naming & Messaging

#### Primary Branding
The application name "The Markdown Redemption" is a playful reference to "The Shawshank Redemption," symbolizing the liberation of text from proprietary, locked formats into the freedom of plain text Markdown.

#### Tagline Options
Primary: "Every document deserves a second chance"

Alternatives for variety:
- "Transform documents into Markdown with AI"
- "Redeeming documents, one conversion at a time"
- "Breaking free from proprietary formats"
- "Hope is a good thing, maybe the best of formats"

#### About/Mission Statement
Use in footer, about page, or README introduction:

"The Markdown Redemption uses advanced vision-language models to extract and convert text from images and PDFs into clean, portable Markdown format. Whether you're digitizing old documents, liberating content from locked PDFs, or archiving scanned materials, we believe every document deserves redemption in the world of open, accessible plain text. No proprietary formats. No vendor lock-in. Just freedom."

### Visual Design Language

#### Logo Concept

The logo should visually communicate transformation, liberation, and redemption through one or more of these conceptual elements:

**Liberation Theme**: Broken chains or shackles representing freedom from proprietary formats, with a document icon or hash symbol (#) emerging.

**Transformation Theme**: A document icon morphing into a Markdown hash symbol, possibly with a gradient showing the transition.

**Prison Break Theme**: Subtle reference to the film with prison bars made of "PDF" text breaking apart, Markdown symbol shining through.

**Phoenix/Rebirth Theme**: Document rising from ashes or transforming, emphasizing the "redemption" concept.

**Style Guidelines**: Modern, clean, friendly. Avoid overly technical or intimidating imagery. The logo should work in:
- Full color for web headers
- Single color (white) for dark backgrounds
- Monochrome for favicon
- Various sizes from 16x16px favicon to 512x512px

#### Color Palette

**Primary - Hope Blue**: `#4A90E2`  
Used for: Main buttons, links, active states, primary UI elements. Represents hope, freedom, and trust.

**Secondary - Midnight Gray**: `#2C3E50`  
Used for: Headers, body text, borders. Provides professional, readable contrast.

**Accent - Redemption Red**: `#E74C3C`  
Used sparingly for: Important CTAs, error states that need attention. Represents urgency and transformation.

**Success - Freedom Green**: `#10B981`  
Used for: Success messages, completed states, checkmarks. Represents successful liberation of document text.

**Warning - Caution Amber**: `#F59E0B`  
Used for: Warning messages, partial success states, attention-needed items.

**Error - Alert Red**: `#EF4444`  
Used for: Error messages, failed conversions, deletion actions.

**Background - Clean Slate**: `#F8F9FA`  
Used for: Page backgrounds, card backgrounds. Light, neutral foundation.

**Surface White**: `#FFFFFF`  
Used for: Cards, modals, input fields. Pure white for content areas.

**Border - Subtle Gray**: `#E5E7EB`  
Used for: Dividers, card borders, input borders. Subtle separation.

#### Typography

**Font Families**:

Primary (Headings & UI): System font stack for performance and native feel:
```
-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif
```

Alternative: Inter or Source Sans Pro from Google Fonts if brand consistency across platforms is priority over performance.

Monospace (Filenames & Code): 
```
"Fira Code", "SF Mono", Monaco, Consolas, monospace
```

**Type Scale**:
- H1 (Page Title): 2.5rem (40px), bold, letter-spacing -0.5px
- H2 (Section): 2rem (32px), semi-bold
- H3 (Subsection): 1.5rem (24px), semi-bold
- Body: 1rem (16px), regular, line-height 1.6
- Small: 0.875rem (14px), regular
- Caption: 0.75rem (12px), regular, muted color

**Responsive Adjustments**: Reduce heading sizes by 20% on mobile devices (screens < 640px).

#### UI Component Styling

**Buttons**:
- Border radius: 8px (rounded corners)
- Padding: 12px 24px for primary buttons
- Hover state: Darken by 10%, scale(1.02) transform
- Active state: Darken by 15%, scale(0.98)
- Disabled state: 50% opacity, cursor not-allowed
- Transition: all 200ms ease-in-out

**Cards & Containers**:
- Background: white on light backgrounds
- Border: 1px solid border color, or subtle shadow
- Border radius: 12px
- Padding: 24px
- Shadow: 0 1px 3px rgba(0,0,0,0.1) on hover

**Input Fields**:
- Border: 1px solid border color
- Border radius: 6px
- Padding: 10px 12px
- Focus state: Primary color border, subtle glow shadow
- Error state: Error color border

**Drag & Drop Zone**:
- Dashed border: 2px dashed border color
- Border radius: 12px
- Padding: 48px
- Hover state: Primary color border, background tint
- Active drag state: Primary color border (solid), stronger background tint

#### Icons

Use a consistent icon set throughout the application. Recommended: Heroicons, Feather Icons, or Material Icons for their clean, modern aesthetic.

**Required Icons**:
- Upload: Cloud with up arrow or upload tray
- Download: Down arrow or download tray
- Success: Checkmark or check circle
- Error: X or alert circle
- Warning: Exclamation triangle
- Info: Info circle
- File: Document icon
- Image: Picture frame icon
- PDF: Document with "PDF" text
- ZIP: Compressed folder
- Delete/Remove: Trash can or X
- Process/Loading: Spinner or hourglass
- Refresh/Retry: Circular arrow

**Icon Sizing**: 20px for inline icons, 24px for button icons, 48px for feature illustrations.

#### Favicon

Create a multi-size favicon package including:
- 16x16px: Simple monogram or hash symbol
- 32x32px: Same design with more detail
- Apple touch icon (180x180px): Full logo with padding
- SVG version for modern browsers

Concept: "MD" monogram with broken chain link, or hash symbol (#) breaking through paper texture.

### Responsive Design Strategy

#### Breakpoints

**Mobile**: < 640px
- Single column layout
- Simplified navigation
- Larger touch targets (minimum 44x44px)
- Reduced padding and margins
- Stacked button arrangements

**Tablet**: 640px - 1024px  
- Two-column layouts where appropriate
- Optimized for both portrait and landscape
- Touch-friendly but denser than mobile
- Side-by-side buttons

**Desktop**: > 1024px
- Full multi-column layouts
- Hover states and subtle animations
- Maximum content width: 1280px centered
- Generous whitespace

#### Mobile-Specific Optimizations

Upload zone occupies more vertical space on mobile for easier thumb reach. File list uses larger text and bigger remove buttons. Results page shows one prominent download button rather than multiple options side-by-side.

### Accessibility Requirements

**WCAG 2.1 Level AA Compliance**:

Color contrast ratios must meet minimum standards:
- Normal text: 4.5:1 minimum
- Large text (18pt+): 3:1 minimum
- UI components: 3:1 minimum

**Keyboard Navigation**:
- All interactive elements focusable with Tab key
- Logical tab order following visual layout
- Enter/Space activates buttons
- Escape closes modals
- Visible focus indicators (outline or glow)

**Screen Reader Support**:
- Semantic HTML elements (nav, main, article, etc.)
- ARIA labels for icon-only buttons
- ARIA live regions for dynamic status updates
- Alt text for all meaningful images
- Form labels properly associated with inputs

**Other Considerations**:
- Support for browser zoom up to 200%
- No information conveyed by color alone
- Sufficient click/tap target sizes
- Animations respect prefers-reduced-motion preference

---

## User Interface Specifications

### Page 1: Upload Interface (index.html)

#### Layout Structure

**Header Section** (full width, fixed or static):
- Left: Application logo and name
- Center: Tagline (hidden on mobile)
- Right: Help icon linking to documentation or API status indicator

**Main Content** (centered, max-width 800px):
- Hero section with brief description
- Large drag-and-drop upload zone
- "or" divider
- Traditional file input button
- Supported formats and limits text
- Selected files list (empty state initially)
- Primary action button

**Footer** (full width):
- Links: About, How It Works, Privacy, GitHub repository
- API status indicator showing if LLM endpoint is reachable
- Data retention policy statement
- Powered by model name

#### Drag & Drop Zone Specifications

**Visual Design**:
- Large rectangular area, minimum 300px height on desktop
- Dashed border in subtle gray
- Centered icon (upload cloud or document stack)
- Primary heading: "Drag & Drop Files Here"
- Secondary text: "or click to browse your computer"
- Tertiary text: Supported formats and size limits

**Interactive States**:

Default: Subtle gray dashed border, light background.

Hover (desktop): Primary color dashed border, very light primary color background tint.

Drag Over: Primary color solid border, stronger primary color background tint, slight scale increase, text changes to "Drop files to add them".

Invalid Drag: Red border, red background tint, text changes to "This file type is not supported".

**Behavior**:
- Clicking anywhere in zone triggers file input dialog
- Multiple file selection enabled by default
- Files can be added via drag-and-drop multiple times
- Duplicate filenames are allowed (system will handle)

#### Selected Files List

**Empty State**:
Display subtle message: "No files selected yet. Choose files to begin redemption."

**Populated State**:

Shows heading: "Selected Files ({count}):"

Each file row displays:
- File type icon (image or PDF)
- Filename in monospace font
- File size in human-readable format (KB/MB)
- Remove button (X icon) on the right

Below list shows: "Total: {combined size}"

**File List Item Design**:
- Each item has subtle border or background
- Hover state shows remove button more prominently
- Remove button has confirm-on-hover tooltip: "Remove file"

**Constraints**:
- Maximum 10 files visible warning if limit reached
- Cannot add 11th file; show error message
- Total size display updates dynamically

#### Primary Action Button

**Label**: "Redeem Documents" or "Start Conversion"

**Visual Design**:
- Large button, full width on mobile, auto-width centered on desktop
- Primary color background
- White text, bold weight
- Arrow or processing icon on the right

**States**:

Disabled (no files selected): Grayed out, 50% opacity, cursor not-allowed, no hover effect.

Enabled: Full color, hover effect (darken + scale up), active effect (darken + scale down).

Loading (after click): Button text changes to "Processing...", shows spinner icon, button remains disabled.

**Behavior**:
Clicking submits form via POST to `/upload` endpoint. Browser shows loading state. No client-side JavaScript required, but progressive enhancement possible.

#### Client-Side Enhancements (Optional)

**Pre-Upload Validation**:
Check file extensions against allowed list before form submission. Show instant error messages for invalid files.

**File Size Validation**:
Check each file size against MAX_UPLOAD_SIZE limit. Show instant error for oversized files.

**Drag Visual Feedback**:
Add/remove CSS classes on dragenter/dragleave/drop events for visual states.

**Multiple Drop Support**:
Allow users to drag files multiple times, accumulating selection.

**Thumbnail Previews**:
For image files, show small thumbnail preview using FileReader API.

### Page 2: Processing Page (processing.html)

#### Purpose

This page is optional for MVP. It provides user feedback during long-running conversions, especially for PDFs or multiple files.

#### Simple Implementation (Recommended for V1)

**Layout**:
- Centered vertical layout
- Large processing icon (animated spinner or hourglass)
- Primary heading: "Redeeming Your Documents..."
- Secondary text: "Processing {current} of {total} files"
- Current filename being processed
- Progress bar (if multiple files)
- Warning message: "Please don't close this window"

**Implementation**:
Server processes files synchronously. Page either:
- Uses meta refresh tag to poll status endpoint every 5 seconds
- Automatically redirects to results page when complete
- Shows static message if processing takes < 10 seconds

#### Advanced Implementation (Future Enhancement)

**Real-Time Updates**:
Use WebSocket or Server-Sent Events to push progress updates from server.

**Detailed Progress**:
- Individual progress bar for each file
- Estimated time remaining
- Current processing step (uploading, rendering, extracting, etc.)
- Ability to cancel processing

**Status Persistence**:
Store processing state in Redis or database so users can close browser and check back later.

### Page 3: Results Page (result.html)

#### Layout Structure

**Header**: Same as upload page for consistency.

**Main Content** (centered, max-width 900px):

Success section with celebratory icon and message. Download area as prominent card. File list showing what was converted. Error section if partial failures occurred. Action buttons for next steps.

**Footer**: Same as upload page.

#### Success Section

**Visual Design**:
- Large success icon (checkmark, celebration, or "redemption" themed illustration)
- Primary heading: Success message
- Subheading: File count summary

**Message Variations**:

Single file success: "Your Document Has Been Redeemed!"

Multiple files success: "Your Documents Have Been Redeemed!"

Partial success: "Partial Success" with warning icon instead

Complete failure: "Conversion Failed" with error icon (should be rare)

**Statistics Display**:
Show "Successfully converted: {count} files" prominently. If errors exist, show "Failed: {count} files" in warning color.

#### Download Card (Single File)

**Layout**:
- Large card with white background and subtle shadow
- Filename as heading in monospace font
- "Preview:" subheading
- Scrollable preview box showing first 500 characters of Markdown
- "Show More" button to expand full content
- Two action buttons: "Download Markdown" and "Copy to Clipboard"

**Preview Box**:
- Light gray background
- Monospace or rendered markdown preview
- Max height 300px with scroll
- Border around container

**Button Layout**:
Side-by-side on desktop, stacked on mobile. Download button is primary (filled), Copy button is secondary (outline).

**Copy to Clipboard Behavior**:
Click shows temporary success message: "Copied to clipboard!" Button text temporarily changes, then reverts after 2 seconds.

#### Download Card (Multiple Files)

**Layout**:
- Large card with white background
- ZIP icon illustration
- Filename: `converted_YYYYMMDD_HHMMSS.zip`
- File size and count: "{size} • {count} files"
- Single prominent download button
- Expandable file list below

**File List**:
- Heading: "Files included:"
- Each file shows checkmark, filename in monospace
- Optionally show file size for each
- Can be collapsed by default with "Show files" toggle

**Download Button**:
- Full width on mobile, large centered on desktop
- Primary color, bold
- Icon: Download arrow
- Label: "Download ZIP Archive"

#### Error Display (Partial Failures)

**Section Location**: Below download card but above action buttons.

**Design**:
- Two-column or tabbed layout separating successes and failures
- Success column: Green checkmarks, list of successful conversions
- Failure column: Red X marks, list of failed files with error messages

**Error Messages**:
Each failed file shows:
- Filename
- Brief error explanation in plain language
- Icon indicating error type

**Error Message Examples**:
- "Unable to read PDF file - file may be corrupted"
- "API timeout - try a simpler document"
- "Invalid image format"
- "LLM service unavailable"

**Action Option**:
Provide "Try Failed Files Again" button that resubmits only the files that failed (implementation optional for V1).

#### Action Buttons

**Primary Action**: "Redeem More Documents"  
Returns user to upload page, clears current session.

**Secondary Action**: "Download Another Copy"  
Triggers download again without reprocessing.

**Tertiary Action** (desktop only): "View Conversion Details"  
Shows modal or expands section with:
- Model used
- Processing time
- API endpoint
- File sizes before/after
- Timestamp

---

## Application Routes & Flow

### Route: GET /

**Purpose**: Display the upload page.

**Handler**: `index()`

**Actions**:
- Run automatic file cleanup if enabled
- Check if LLM API endpoint is reachable (optional, for status indicator)
- Render `index.html` template with configuration data

**Template Variables**:
- `app_name`: Application name from config
- `app_tagline`: Tagline from config
- `max_size_mb`: Maximum upload size in megabytes
- `max_files`: Maximum concurrent uploads allowed
- `allowed_extensions`: List of allowed file types for display
- `api_online`: Boolean indicating if API is reachable (optional)

**Query Parameters**: None.

**Session Requirements**: None.

### Route: POST /upload

**Purpose**: Handle file upload and save to temporary storage.

**Handler**: `upload_files()`

**Expected Form Data**:
- Field name: `files[]` or `files`
- Multiple files allowed
- Content-Type: `multipart/form-data`

**Actions**:
1. Validate request contains files
2. Extract file list from request
3. Validate each file (extension, size, MIME type)
4. Generate unique session ID using UUID4
5. Create session directory in uploads folder
6. Save valid files with secure filenames
7. Store session metadata in Flask session
8. Handle validation errors gracefully
9. Redirect to processing route

**Session Data Stored**:
- `session_id`: Unique identifier for this batch
- `files`: List of uploaded file metadata (original name, saved name, size)
- `upload_timestamp`: When upload occurred

**Success Response**: HTTP 302 redirect to `/process`

**Error Responses**:
- 400 Bad Request: No files provided, all files invalid
- 413 Payload Too Large: File exceeds MAX_UPLOAD_SIZE
- 500 Internal Server Error: Disk write failure, permission issues

**Flash Messages**:
- Error: "No files selected"
- Error: "File exceeds size limit: {filename}"
- Warning: "File type not allowed: {filename}"
- Error: "Failed to save file: {filename}"

### Route: GET /process

**Purpose**: Process uploaded files and display results.

**Handler**: `process_documents()`

**Actions**:
1. Retrieve session ID from session
2. Validate session exists and upload directory exists
3. Iterate through each uploaded file
4. Determine file type (image vs PDF)
5. Call appropriate conversion function
6. Collect results and errors
7. Create single markdown file OR ZIP archive based on count
8. Store results metadata in session
9. Clean up uploaded files
10. Render results template

**Session Data Required**:
- `session_id`: From upload step
- `files`: List of files to process

**Session Data Stored**:
- `result_type`: "single" or "zip"
- `result_filename`: Name of output file
- `success_count`: Number of successful conversions
- `error_count`: Number of failed conversions
- `errors`: List of error details
- `processed_files`: List of successfully converted filenames

**Success Response**: HTTP 200 with `result.html` rendered

**Error Responses**:
- 302 Redirect to `/` if session invalid
- Flash error message if no valid results

**Template Variables**:
- `result_type`: single or zip
- `result_filename`: Name of downloadable file
- `success_count`: Number of successful conversions
- `error_count`: Number of failures
- `errors`: List of error objects with filename and message
- `markdown_preview`: First 500 chars (if single file)
- `file_list`: List of converted filenames (if multiple)
- `download_size`: Human-readable file size

**Processing Flow Details**:

For each file:
- Check file extension
- Route to image or PDF processor
- Catch and log any exceptions
- Continue processing remaining files even if one fails
- Store result or error

After all files processed:
- If 1 result: Save single `.md` file
- If 2+ results: Create ZIP archive with all `.md` files
- Calculate total processing time
- Store summary in session

### Route: GET /download

**Purpose**: Serve the converted file(s) for download.

**Handler**: `download_file()`

**Actions**:
1. Retrieve session ID and result metadata from session
2. Validate session and result file exist
3. Determine MIME type based on result type
4. Stream file to client with appropriate headers
5. Optional: Log download event
6. Optional: Schedule cleanup of this session's files

**Session Data Required**:
- `session_id`: Identifies result folder
- `result_type`: "single" or "zip"
- `result_filename`: Exact filename to serve

**Response Headers**:

For single Markdown file:
- Content-Type: `text/markdown; charset=utf-8`
- Content-Disposition: `attachment; filename="{original_name}.md"`

For ZIP archive:
- Content-Type: `application/zip`
- Content-Disposition: `attachment; filename="converted_{timestamp}.zip"`

Both:
- Cache-Control: `no-cache, no-store, must-revalidate`
- Expires: `0`

**Success Response**: HTTP 200 with file stream

**Error Responses**:
- 404 Not Found: Session expired or file doesn't exist
- 302 Redirect to `/` with flash message

**Implementation Notes**:
Use Flask's `send_file()` or `send_from_directory()` for efficient file serving. Do not load entire file into memory. Stream large files.

### Route: GET /api/status (Optional)

**Purpose**: Health check endpoint for API availability.

**Handler**: `api_status()`

**Actions**:
1. Attempt to reach LLM endpoint with minimal request
2. Measure response time
3. Return JSON status

**Response JSON**:
```
{
  "status": "online" | "offline" | "degraded",
  "endpoint": "http://localhost:11434/...",
  "model": "qwen2.5vl:latest",
  "response_time_ms": 245
}
```

**Use Case**: JavaScript on upload page can poll this to show real-time API status indicator.

### Route: POST /cleanup (Optional)

**Purpose**: Manual trigger for file cleanup (admin use).

**Handler**: `manual_cleanup()`

**Actions**:
1. Run cleanup function immediately
2. Return JSON with cleanup results

**Authentication**: Should require admin token or be disabled in production.

**Response JSON**:
```
{
  "deleted_files": 42,
  "freed_space_mb": 128.5
}
```

---

## Core Functionality

### File Upload Processing

#### Validation Layer

**Extension Validation**: Extract file extension from filename, convert to lowercase, check against `ALLOWED_EXTENSIONS` list. Reject immediately if not allowed.

**Size Validation**: Check `Content-Length` if provided, or file size after upload. Reject files exceeding `MAX_UPLOAD_SIZE`.

**MIME Type Validation**: Read file headers to verify MIME type matches extension. Prevents spoofed extensions. For example, a file named `image.jpg` should have MIME type `image/jpeg`, not `application/pdf`.

**Filename Sanitization**: Use Werkzeug's `secure_filename()` to remove path traversal attempts, special characters, and normalize to ASCII. Handle Unicode filenames gracefully.

**Batch Size Validation**:
