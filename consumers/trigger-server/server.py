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
                env_args = []
                for var in ['SNAP_REGISTRY_URL']:
                    val = os.environ.get(var)
                    if val:
                        env_args.extend([f'{var}={val}'])
                upgrade = subprocess.run(
                    ['sudo'] + env_args + [f'{CONSUMER_DIR}/upgrade.sh'],
                    capture_output=True, text=True, timeout=300
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
                    capture_output=True, text=True, timeout=120
                )
                results = json.loads(test.stdout.strip())
                print(f"[{consumer_name}] Test result: {results.get('status')}")

                # Step 2.5: IDB encryption verification (always both modes)
                idb_runner = f'{CONSUMER_DIR}/idb-verify.py'
                if os.path.exists(idb_runner):
                    for mode, flag in [('idb_plaintext', []), ('idb_encrypted', ['--encryption'])]:
                        label = 'encrypted' if flag else 'plaintext'
                        print(f"[{consumer_name}] IDB verify ({label})...")
                        try:
                            cmd = ['python3', idb_runner] + flag
                            binary = os.environ.get('WPT_FIREFOX_BINARY', '')
                            if binary:
                                cmd.extend(['--binary', binary])
                            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
                            try:
                                results[mode] = json.loads(proc.stdout.strip())
                            except json.JSONDecodeError:
                                results[mode] = {'idb_status': 'error', 'details': proc.stderr[-2000:]}
                        except subprocess.TimeoutExpired:
                            results[mode] = {'idb_status': 'timeout'}
                        except Exception as e:
                            results[mode] = {'idb_status': 'error', 'details': str(e)}
                        print(f"[{consumer_name}] IDB ({label}): {results[mode].get('idb_status')}")

                # Step 3: WPT tests (if available)
                wpt_runner = f'{CONSUMER_DIR}/wpt-runner.py'
                if os.path.exists(wpt_runner):
                    print(f"[{consumer_name}] Running WPT tests...")
                    try:
                        wpt_cmd = ['python3', wpt_runner]
                        if os.environ.get('WPT_ENCRYPTION'):
                            wpt_cmd.append('--encryption')
                        wpt_binary = os.environ.get('WPT_FIREFOX_BINARY', '')
                        if wpt_binary:
                            wpt_cmd.extend(['--binary', wpt_binary])
                        wpt_geckodriver = os.environ.get('WPT_GECKODRIVER_BINARY', '')
                        if wpt_geckodriver:
                            wpt_cmd.extend(['--webdriver-binary', wpt_geckodriver])
                        wpt = subprocess.run(
                            wpt_cmd,
                            capture_output=True, text=True, timeout=600
                        )
                        try:
                            wpt_results = json.loads(wpt.stdout.strip())
                            results['wpt'] = wpt_results
                        except json.JSONDecodeError:
                            results['wpt'] = {
                                'wpt_status': 'error',
                                'wpt_log': wpt.stderr[-2000:] if wpt.stderr else ''
                            }
                        print(f"[{consumer_name}] WPT result: {results['wpt'].get('wpt_status')}")
                    except subprocess.TimeoutExpired:
                        results['wpt'] = {'wpt_status': 'timeout', 'wpt_log': 'WPT runner timed out after 600s'}
                    except Exception as e:
                        results['wpt'] = {'wpt_status': 'error', 'wpt_log': str(e)}

                # Step 4: Report to builder
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
