#!/usr/bin/env python3
import argparse
import glob
import resource
import subprocess
import json
import os
import shutil
import sys

WPT_DIR = '/opt/wpt'

# WPT config to avoid port conflicts with trigger-server (port 9000).
# WPT expects exactly 2 http ports and 2 https ports.
# h2 key moves the HTTP/2 server off its default port 9000.
WPT_CONFIG = {
    "ports": {
        "http": [8001, 8002],
        "https": [8444, 8445],
        "ws": [9001],
        "wss": [9002],
        "h2": [9003]
    }
}


def check_hosts():
    """Warn if WPT hosts are missing from /etc/hosts."""
    try:
        with open('/etc/hosts') as f:
            if 'web-platform.test' not in f.read():
                print("WARNING: WPT hosts not found in /etc/hosts. "
                      "Tests may fail. Run: cd /opt/wpt && python3 ./wpt make-hosts-file >> /etc/hosts",
                      file=sys.stderr)
    except OSError:
        pass


def write_wpt_config():
    """Write WPT config.json to avoid port conflicts."""
    config_path = os.path.join(WPT_DIR, 'config.json')
    with open(config_path, 'w') as f:
        json.dump(WPT_CONFIG, f, indent=2)


def run_wpt(args, test_path, report_file):
    binary = args.binary or shutil.which('firefox')
    geckodriver = args.webdriver_binary or shutil.which('geckodriver')

    if not binary:
        print(json.dumps({'wpt_status': 'error', 'wpt_log': 'firefox not found on PATH'}))
        sys.exit(0)

    write_wpt_config()

    crash_dir = '/tmp/crash-dumps'
    os.makedirs(crash_dir, exist_ok=True)

    cmd = [
        'python3', './wpt', 'run',
        '--headless',
        '--yes',
        f'--binary={binary}',
        f'--log-wptreport={report_file}',
        '--log-raw=/tmp/wpt-raw.log',
    ]

    # Always wrap Firefox in its own dbus-run-session, even if
    # DBUS_SESSION_BUS_ADDRESS is already set. This gives Firefox a dedicated
    # session bus (avoiding shared-bus issues when the trigger-server already
    # runs inside dbus-run-session, as on Debian).
    dbus_run_session = shutil.which('dbus-run-session')
    if dbus_run_session:
        cmd = [dbus_run_session] + cmd
    if args.encryption:
        cmd.append('--setpref=dom.quotaManager.encryption.enabled=true')
    cmd.append('--setenv=MOZ_LOG=QuotaManager:5,IndexedDB:3,timestamp')
    cmd.append('--setenv=MOZ_LOG_FILE=/tmp/moz_wpt.log')
    cmd.append('--setenv=MOZ_CRASHREPORTER=1')
    cmd.append('--setenv=MOZ_CRASHREPORTER_NO_REPORT=1')
    cmd.append(f'--setenv=MINIDUMP_SAVE_PATH={crash_dir}')
    cmd.append('--setenv=XPCOM_DEBUG_BREAK=stack')
    if geckodriver:
        cmd.append(f'--webdriver-binary={geckodriver}')
    cmd.append('--setpref=browser.privatebrowsing.autostart=true')
    cmd.append('--setenv=MOZ_DISABLE_CONTENT_SANDBOX=1')
    # Snap devmode Firefox needs LD_LIBRARY_PATH to find libxul.so etc.
    ld_lib = os.environ.get('LD_LIBRARY_PATH', '')
    if ld_lib:
        cmd.append(f'--setenv=LD_LIBRARY_PATH={ld_lib}')
    cmd.extend(['firefox', test_path])

    # Clear debug log so we get fresh output from this run
    try:
        os.unlink('/tmp/wpt-firefox-debug.log')
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env['MOZ_CRASHREPORTER'] = '1'
    env['MOZ_CRASHREPORTER_NO_REPORT'] = '1'
    env['MINIDUMP_SAVE_PATH'] = crash_dir
    env['XPCOM_DEBUG_BREAK'] = 'stack'
    env['MOZ_LOG'] = 'QuotaManager:5,IndexedDB:3,timestamp'
    env['MOZ_LOG_FILE'] = '/tmp/moz_wpt.log'

    # Enable core dumps
    try:
        resource.setrlimit(resource.RLIMIT_CORE, (resource.RLIM_INFINITY, resource.RLIM_INFINITY))
    except (ValueError, resource.error):
        pass

    # Log D-Bus state for crash investigation
    dbus_addr = os.environ.get('DBUS_SESSION_BUS_ADDRESS', '<not set>')
    print(f"D-Bus session bus: {dbus_addr}", file=sys.stderr)

    # Write full stdout/stderr to files for crash investigation
    stdout_log = open('/tmp/wpt-stdout.log', 'w')
    stderr_log = open('/tmp/wpt-stderr.log', 'w')

    try:
        proc = subprocess.run(cmd, cwd=WPT_DIR, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True, timeout=300,
                              env=env)
    except subprocess.TimeoutExpired as e:
        proc = type('FakeResult', (), {
            'stdout': e.stdout or '',
            'stderr': (e.stderr or '') + '\n[TIMEOUT after 300s]',
            'returncode': -1
        })()

    stdout_log.write(proc.stdout or '')
    stdout_log.close()
    stderr_log.write(proc.stderr or '')
    stderr_log.close()

    return proc


def read_file_tail(path, max_bytes=50000):
    """Read the tail of a file, returning up to max_bytes."""
    try:
        with open(path) as f:
            content = f.read()
            if len(content) > max_bytes:
                return '...[truncated]...\n' + content[-max_bytes:]
            return content
    except (FileNotFoundError, OSError):
        return ''


def find_minidumps():
    """Look for crash minidump files."""
    patterns = [
        '/tmp/profile*/minidumps/*.dmp',
        '/tmp/rust_mozprofile*/minidumps/*.dmp',
        '/tmp/crash-dumps/*.dmp',
    ]
    dumps = []
    for pattern in patterns:
        dumps.extend(glob.glob(pattern))
    return dumps


def parse_report(report_file):
    """Parse --log-wptreport JSON for pass/fail counts."""
    try:
        with open(report_file) as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {'pass': 0, 'fail': 0, 'total': 0, 'failures': []}

    results = data.get('results', [])
    passed = 0
    failed = 0
    failures = []

    for result in results:
        test_name = result.get('test', 'unknown')
        subtests = result.get('subtests', [])
        test_status = result.get('status', 'ERROR')

        if not subtests:
            # Harness-level result only
            if test_status == 'OK':
                passed += 1
            else:
                failed += 1
                failures.append(f"{test_name} ({test_status})")
        else:
            for sub in subtests:
                sub_status = sub.get('status', 'ERROR')
                sub_name = sub.get('name', 'unknown')
                if sub_status == 'PASS':
                    passed += 1
                else:
                    failed += 1
                    failures.append(f"{test_name}: {sub_name} ({sub_status})")

    return {
        'pass': passed,
        'fail': failed,
        'total': passed + failed,
        'failures': failures
    }


def main():
    parser = argparse.ArgumentParser(description='Run WPT tests against Firefox')
    parser.add_argument('--binary', help='Path to Firefox binary (default: auto-detect on PATH)')
    parser.add_argument('--webdriver-binary', help='Path to geckodriver binary (default: auto-detect on PATH)')
    parser.add_argument('--encryption', action='store_true',
                        help='Enable dom.quotaManager.encryption.enabled pref')
    args = parser.parse_args()

    check_hosts()

    # Smoke test only (single test for iterating on report retrieval)
    smoke = run_wpt(args, 'IndexedDB/idbfactory_open.any.js', '/tmp/wpt-smoke.json')
    smoke_summary = parse_report('/tmp/wpt-smoke.json')

    # Read raw report for host-side validation
    raw_report = None
    try:
        with open('/tmp/wpt-smoke.json') as f:
            raw_report = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        pass

    combined_output = (smoke.stdout or '') + '\n---STDERR---\n' + (smoke.stderr or '')
    wpt_log_head = combined_output[:5000]
    wpt_log_tail = combined_output[-5000:]

    moz_log_content = ''
    try:
        with open('/tmp/moz_wpt.log') as f:
            moz_log_content = f.read()[-15000:]
    except (FileNotFoundError, OSError):
        pass

    debug_log_content = ''
    try:
        with open('/tmp/wpt-firefox-debug.log') as f:
            debug_log_content = f.read()
    except (FileNotFoundError, OSError):
        pass

    # Read full crash investigation logs
    raw_wpt_log = read_file_tail('/tmp/wpt-raw.log')
    full_stderr = read_file_tail('/tmp/wpt-stderr.log')
    minidumps = find_minidumps()

    result = {
        'wpt_status': 'pass' if smoke_summary['fail'] == 0 and smoke_summary['total'] > 0 else 'fail',
        'wpt_smoke': smoke_summary,
        'wpt_returncode': smoke.returncode,
        'wpt_log': wpt_log_head + '\n---TAIL---\n' + wpt_log_tail,
        'moz_log': moz_log_content,
        'debug_log': debug_log_content,
        'raw_report': raw_report,
        'raw_wpt_log': raw_wpt_log,
        'full_stderr': full_stderr,
        'dbus_session_bus': os.environ.get('DBUS_SESSION_BUS_ADDRESS', '<not set>'),
        'minidumps': minidumps,
    }

    print(json.dumps(result))


if __name__ == '__main__':
    main()
