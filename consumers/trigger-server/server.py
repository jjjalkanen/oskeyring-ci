#!/usr/bin/env python3
import http.server
import socketserver
import json
import subprocess
import os
import sys
from pathlib import Path

PORT = 9000
BUILDER_URL = "http://builder:9999/report"

class TriggerHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/trigger':
            consumer_name = os.environ.get('CONSUMER_NAME', 'unknown')
            print(f"[{consumer_name}] Received trigger request")

            # Send immediate response
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "triggered"}).encode())

            # Execute the installation and testing
            try:
                # Run install script
                print(f"[{consumer_name}] Running installation...")
                install_result = subprocess.run(
                    ['/install.sh'],
                    capture_output=True,
                    text=True,
                    timeout=300
                )

                if install_result.returncode != 0:
                    raise Exception(f"Installation failed: {install_result.stderr}")

                print(f"[{consumer_name}] Installation complete, running tests...")

                # Run test
                test_result = subprocess.run(
                    ['python3', '/test-runner.py'],
                    capture_output=True,
                    text=True,
                    timeout=60
                )

                result_data = json.loads(test_result.stdout)

                # Report back to builder
                print(f"[{consumer_name}] Reporting results to builder...")
                report_result = subprocess.run(
                    ['curl', '-X', 'POST',
                     '-H', 'Content-Type: application/json',
                     '-d', json.dumps(result_data),
                     BUILDER_URL],
                    capture_output=True,
                    text=True,
                    timeout=30
                )

                if report_result.returncode == 0:
                    print(f"[{consumer_name}] Results reported successfully")
                else:
                    print(f"[{consumer_name}] Failed to report results: {report_result.stderr}")

            except Exception as e:
                print(f"[{consumer_name}] Error during testing: {e}")
                # Try to report the error
                error_data = {
                    "consumer": consumer_name,
                    "status": "error",
                    "output": "",
                    "error": str(e)
                }
                subprocess.run(
                    ['curl', '-X', 'POST',
                     '-H', 'Content-Type: application/json',
                     '-d', json.dumps(error_data),
                     BUILDER_URL],
                    capture_output=True,
                    timeout=30
                )
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Custom logging format
        consumer_name = os.environ.get('CONSUMER_NAME', 'unknown')
        print(f"[{consumer_name}] {format % args}")

if __name__ == "__main__":
    print(f"Starting trigger server on port {PORT}...")
    with socketserver.TCPServer(("", PORT), TriggerHandler) as httpd:
        print(f"Trigger server listening on port {PORT}")
        httpd.serve_forever()
