"""Gunicorn configuration for The Markdown Redemption"""
import multiprocessing
import os

# Load from environment or use defaults
bind = f"{os.getenv('HOST', '0.0.0.0')}:{os.getenv('PORT', '5000')}"
workers = int(os.getenv('WORKERS', multiprocessing.cpu_count() * 2 + 1))

# Timeout settings for long-running LLM requests
# Workers will be gracefully restarted if requests take longer than this
timeout = 600  # 10 minutes - generous for multi-page PDFs
graceful_timeout = 30  # Give workers 30s to finish current request on shutdown
keepalive = 5

# Logging
accesslog = '-'  # Log to stdout
errorlog = '-'   # Log to stderr
loglevel = os.getenv('LOG_LEVEL', 'info')

# Worker class
worker_class = 'sync'

# Prevent memory leaks - restart workers after N requests
max_requests = 1000
max_requests_jitter = 100

# Graceful timeout handler
def worker_abort(worker):
    """Called when a worker times out"""
    worker.log.warning(
        f"Worker timeout (pid:{worker.pid}) - LLM request exceeded {timeout}s. "
        "Consider increasing LLM_TIMEOUT in .env or optimizing API endpoint."
    )
