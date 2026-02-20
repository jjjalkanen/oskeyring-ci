#!/usr/bin/env python3
import http.server
import socketserver
import json
import threading
import sys
from datetime import datetime

PORT = 9999
EXPECTED_CONSUMERS = ['consumer-arch', 'consumer-debian', 'consumer-redhat']

results = {}
results_lock = threading.Lock()
all_reported = threading.Event()

class ResultsHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/report':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)

            try:
                report = json.loads(post_data.decode('utf-8'))
                consumer = report.get('consumer', 'unknown')

                with results_lock:
                    results[consumer] = report
                    print(f"\n[COLLECTOR] Received report from {consumer}: {report.get('status')}")
                    print(f"[COLLECTOR] Reports received: {len(results)}/{len(EXPECTED_CONSUMERS)}")

                    # Check if all consumers have reported
                    if len(results) >= len(EXPECTED_CONSUMERS):
                        all_reported.set()

                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"status": "received"}).encode())

            except Exception as e:
                print(f"[COLLECTOR] Error processing report: {e}")
                self.send_response(400)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Suppress default logging
        pass

def print_summary():
    print("\n" + "="*80)
    print("TEST RESULTS SUMMARY")
    print("="*80)

    all_passed = True
    for consumer in EXPECTED_CONSUMERS:
        if consumer in results:
            report = results[consumer]
            status = report.get('status', 'unknown')
            output = report.get('output', '')
            error = report.get('error', '')

            status_symbol = "✓" if status == "pass" else "✗"
            print(f"\n{status_symbol} {consumer}: {status.upper()}")

            if output:
                print(f"  Output: {output}")
            if error:
                print(f"  Error: {error}")

            if status != "pass":
                all_passed = False
        else:
            print(f"\n✗ {consumer}: NO REPORT RECEIVED")
            all_passed = False

    print("\n" + "="*80)
    if all_passed:
        print("RESULT: ALL TESTS PASSED")
        print("="*80 + "\n")
        return 0
    else:
        print("RESULT: SOME TESTS FAILED")
        print("="*80 + "\n")
        return 1

if __name__ == "__main__":
    print(f"[COLLECTOR] Starting results collector on port {PORT}...")
    print(f"[COLLECTOR] Waiting for reports from: {', '.join(EXPECTED_CONSUMERS)}")

    # Start server in background thread
    server = socketserver.TCPServer(("", PORT), ResultsHandler)
    server_thread = threading.Thread(target=server.serve_forever)
    server_thread.daemon = True
    server_thread.start()

    print(f"[COLLECTOR] Results collector listening on port {PORT}")

    # Wait for all consumers to report (or timeout after 10 minutes)
    if all_reported.wait(timeout=600):
        print(f"[COLLECTOR] All consumers have reported")
    else:
        print(f"[COLLECTOR] Timeout waiting for all consumers")

    # Print summary and exit
    exit_code = print_summary()
    server.shutdown()
    sys.exit(exit_code)
