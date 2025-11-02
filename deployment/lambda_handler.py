"""
AWS Lambda handler for The Markdown Redemption Flask application.

This module adapts the Flask WSGI application to work with AWS Lambda
using the Mangum adapter for ASGI/WSGI compatibility.
"""

import os
from mangum import Mangum
from app import app

# Configure Lambda-specific settings
# Increase max content length for Lambda (larger ephemeral storage)
app.config['MAX_CONTENT_LENGTH'] = int(os.getenv('MAX_UPLOAD_SIZE', 524288000))  # 500MB for Lambda

# Create the Lambda handler using Mangum
# Mangum adapts ASGI/WSGI applications to work with AWS Lambda
handler = Mangum(app, lifespan="off")

def lambda_handler(event, context):
    """
    AWS Lambda handler function.

    Args:
        event: Lambda event containing HTTP request data from Function URL
        context: Lambda context object with runtime information

    Returns:
        HTTP response formatted for Lambda Function URL
    """
    # Log Lambda environment info for debugging
    if os.getenv('VERBOSE_LOGGING', 'False').lower() == 'true':
        print(f"Lambda Function: {context.function_name}")
        print(f"Lambda Request ID: {context.request_id}")
        print(f"Remaining time: {context.get_remaining_time_in_millis()}ms")
        print(f"Memory limit: {context.memory_limit_in_mb}MB")
        print(f"Event type: {event.get('requestContext', {}).get('http', {}).get('method', 'UNKNOWN')}")
        print(f"Path: {event.get('requestContext', {}).get('http', {}).get('path', '/')}")

    # Call Mangum handler
    return handler(event, context)
