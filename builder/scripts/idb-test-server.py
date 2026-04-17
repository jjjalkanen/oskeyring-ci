#!/usr/bin/env python3
"""Simple HTTP server to serve the IndexedDB test page on port 8888."""
import http.server
import os

PORT = 8888
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=SCRIPT_DIR, **kwargs)

if __name__ == "__main__":
    print(f"IDB test server starting on port {PORT}...")
    with http.server.HTTPServer(("", PORT), Handler) as httpd:
        httpd.serve_forever()
