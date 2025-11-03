"""
AWS Lambda handler for The Markdown Redemption Flask application.

This module adapts the Flask WSGI application to work with AWS Lambda
using a simple WSGI->HTTP adapter that avoids Mangum compatibility issues.
"""

import os
import json
import base64
from io import BytesIO
from urllib.parse import unquote, urlencode
from app import app

# Configure Lambda-specific settings
# Increase max content length for Lambda (larger ephemeral storage)
app.config['MAX_CONTENT_LENGTH'] = int(os.getenv('MAX_UPLOAD_SIZE', 524288000))  # 500MB for Lambda

class WSGIEventAdapter:
    """Converts AWS Lambda/API Gateway events to WSGI environ dicts"""

    def __init__(self, event, context):
        self.event = event
        self.context = context

    def get_environ(self):
        """Build a WSGI environ dictionary from Lambda event"""
        # Handle both REST API and HTTP API event formats
        if 'requestContext' in self.event and 'http' in self.event['requestContext']:
            # HTTP API format (Lambda Function URL)
            http_info = self.event['requestContext']['http']
            method = http_info.get('method', 'GET')
            path = http_info.get('path', '/')
            source_ip = http_info.get('sourceIp', '127.0.0.1')
            stage = ''
        else:
            # REST API format
            method = self.event.get('httpMethod', 'GET')
            path = self.event.get('path', '/')
            source_ip = self.event.get('requestContext', {}).get('identity', {}).get('sourceIp', '127.0.0.1')
            # Get stage from requestContext
            stage = self.event.get('requestContext', {}).get('stage', '')

        # Parse query string
        query_string = self.event.get('rawQueryString', '') or \
                      urlencode(self.event.get('queryStringParameters') or {})

        # Get headers
        headers = self.event.get('headers', {}) or {}

        # Get body
        body = self.event.get('body', '') or ''
        if self.event.get('isBase64Encoded'):
            body = base64.b64decode(body)
        else:
            body = body.encode('utf-8') if isinstance(body, str) else body

        # Build environ
        # For REST API, stage is in requestContext and already stripped from path
        # Set SCRIPT_NAME to /stage so Flask generates correct URLs
        script_name = f'/{stage}' if stage and stage != '$default' else ''
        path_info = unquote(path)

        # Debug logging
        print(f"[WSGI] Stage: {stage}")
        print(f"[WSGI] Original path: {path}")
        print(f"[WSGI] SCRIPT_NAME: {script_name}")
        print(f"[WSGI] PATH_INFO: {path_info}")

        environ = {
            'REQUEST_METHOD': method,
            'SCRIPT_NAME': script_name,
            'PATH_INFO': path_info,
            'QUERY_STRING': query_string,
            'CONTENT_TYPE': headers.get('content-type', 'application/x-www-form-urlencoded'),
            'CONTENT_LENGTH': str(len(body)),
            'SERVER_NAME': headers.get('host', 'localhost').split(':')[0],
            'SERVER_PORT': headers.get('host', 'localhost').split(':')[1] if ':' in headers.get('host', '') else '443',
            'SERVER_PROTOCOL': 'HTTP/1.1',
            'wsgi.version': (1, 0),
            'wsgi.url_scheme': headers.get('x-forwarded-proto', 'https'),
            'wsgi.input': BytesIO(body),
            'wsgi.errors': BytesIO(),
            'wsgi.multithread': False,
            'wsgi.multiprocess': False,
            'wsgi.run_once': False,
            'REMOTE_ADDR': source_ip,
        }

        # Add HTTP headers
        for key, value in headers.items():
            key = key.upper().replace('-', '_')
            if key not in ('CONTENT_TYPE', 'CONTENT_LENGTH'):
                environ[f'HTTP_{key}'] = value

        return environ

def lambda_handler(event, context):
    """AWS Lambda handler for API Gateway/Function URL events"""

    adapter = WSGIEventAdapter(event, context)
    environ = adapter.get_environ()

    # Call Flask app
    response_data = {'statusCode': 500, 'body': 'Internal Server Error', 'headers': {}}

    def start_response(status, response_headers, exc_info=None):
        """WSGI start_response callable"""
        status_code = int(status.split(' ')[0])
        response_data['statusCode'] = status_code
        response_data['headers'] = dict(response_headers)

    try:
        app_iter = app(environ, start_response)
        body = b''.join(app_iter)

        # Check if body is already bytes
        if isinstance(body, bytes):
            try:
                body_str = body.decode('utf-8')
                response_data['isBase64Encoded'] = False
            except:
                response_data['body'] = base64.b64encode(body).decode('utf-8')
                response_data['isBase64Encoded'] = True
                return response_data
        else:
            body_str = str(body)
            response_data['isBase64Encoded'] = False

        response_data['body'] = body_str

    except Exception as e:
        response_data['statusCode'] = 500
        response_data['body'] = json.dumps({'error': str(e)})
        response_data['headers']['content-type'] = 'application/json'

    return response_data
