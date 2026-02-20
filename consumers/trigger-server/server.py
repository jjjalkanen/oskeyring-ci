#!/usr/bin/env python3
import http.server
import json
import os
import subprocess
import sys

PORT = 9000
CONSUMER_DIR = os.environ.get('CONSUMER_DIR', '/home/consumer')
BUILDER_URL = os.environ.get('BUILDER_URL', 'http://builder:9999') + '/report'

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
            print(f"[{consumer_name}] Triggered! Starting upgrade...")

            try:
                # Step 1: Upgrade package (needs root via sudo)
                upgrade = subprocess.run(
                    ['sudo', f'{CONSUMER_DIR}/upgrade.sh'],
                    capture_output=True, text=True, timeout=120
                )
                if upgrade.returncode != 0:
                    error = f"Upgrade failed (exit {upgrade.returncode}): {upgrade.stderr}"
                    print(f"[{consumer_name}] {error}")
                    self._send_and_report(consumer_name, "fail", "", error)
                    return

                print(f"[{consumer_name}] Upgrade complete, running tests...")

                # Step 2: Run tests
                test = subprocess.run(
                    ['python3', f'{CONSUMER_DIR}/test-runner.py'],
                    capture_output=True, text=True, timeout=60
                )
                results = json.loads(test.stdout.strip())
                print(f"[{consumer_name}] Test result: {results.get('status')}")

                # Step 3: Report to builder
                self._report(results)
                self._respond(200, results)

            except Exception as e:
                error = str(e)
                print(f"[{consumer_name}] Error: {error}")
                self._send_and_report(consumer_name, "error", "", error)
        else:
            self.send_response(404)
            self.end_headers()

    def _send_and_report(self, consumer, status, output, error):
        results = {"consumer": consumer, "status": status, "output": output, "error": error}
        self._report(results)
        self._respond(500 if status != "pass" else 200, results)

    def _report(self, results):
        try:
            subprocess.run(
                ['curl', '-s', '-X', 'POST',
                 '-H', 'Content-Type: application/json',
                 '-d', json.dumps(results), BUILDER_URL],
                capture_output=True, timeout=10
            )
        except Exception:
            pass

    def _respond(self, code, data):
        self.send_response(code)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def log_message(self, format, *args):
        consumer_name = os.environ.get('CONSUMER_NAME', 'unknown')
        print(f"[{consumer_name}] {format % args}")

if __name__ == "__main__":
    consumer_name = os.environ.get('CONSUMER_NAME', 'unknown')
    print(f"[{consumer_name}] Starting trigger server on port {PORT}...")
    with http.server.HTTPServer(("", PORT), TriggerHandler) as httpd:
        httpd.serve_forever()
