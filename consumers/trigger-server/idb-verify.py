#!/usr/bin/env python3
"""
IndexedDB on-disk encryption verification.

Runs Firefox headless twice:
1. Without encryption — expects .sqlite files to be valid SQLite
2. With encryption — expects .sqlite files to NOT be valid SQLite

Outputs JSON result to stdout.
"""
import argparse
import glob
import json
import os
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time

BASE_PREFS = [
    ('browser.shell.checkDefaultBrowser', 'false'),
    ('browser.aboutwelcome.enabled', 'false'),
    ('datareporting.policy.dataSubmissionEnabled', 'false'),
    ('trailhead.firstrun.branches', '"nofirstrun"'),
    ('browser.tabs.warnOnClose', 'false'),
    ('browser.warnOnQuitShortcut', 'false'),
    ('browser.showQuitWarning', 'false'),
]

IDB_URL = 'http://builder:8888/idb-test.html'
FIREFOX_WAIT = 15
KILL_WAIT = 10


def write_user_js(profile_dir, encryption=False):
    prefs = list(BASE_PREFS)
    if encryption:
        prefs.append(('dom.quotaManager.encryption.enabled', 'true'))
    with open(os.path.join(profile_dir, 'user.js'), 'w') as f:
        for key, value in prefs:
            f.write(f'user_pref("{key}", {value});\n')


def is_valid_sqlite(path):
    """Check both header magic and query ability."""
    try:
        with open(path, 'rb') as f:
            header = f.read(16)
        if not header.startswith(b'SQLite format 3\x00'):
            return False
        conn = sqlite3.connect(f'file:{path}?mode=ro', uri=True)
        conn.execute('SELECT name FROM sqlite_master')
        conn.close()
        return True
    except Exception:
        return False


def find_idb_files(profile_dir):
    """Find IndexedDB .sqlite files in the profile."""
    # Primary path
    primary = os.path.join(profile_dir, 'storage', 'default',
                           'http+++builder+8888', 'idb', '*.sqlite')
    files = glob.glob(primary)
    if files:
        return files
    # Fallback: recursive search
    fallback = os.path.join(profile_dir, 'storage', '**', 'idb', '*.sqlite')
    return glob.glob(fallback, recursive=True)


def run_firefox(binary, profile_dir, encryption=False):
    """Launch Firefox, wait, kill, inspect storage."""
    write_user_js(profile_dir, encryption=encryption)

    cmd = [binary, '--headless', '--profile', profile_dir,
           '--new-window', IDB_URL]

    env = os.environ.copy()
    creds_tmpdir = None
    if encryption:
        creds_tmpdir = tempfile.mkdtemp(prefix='firefox-creds-')
        stashed = '/run/firefox-test-creds/sync-key'
        if os.path.exists(stashed):
            import shutil
            shutil.copy2(stashed, os.path.join(creds_tmpdir, 'sync-key'))
        else:
            # Fallback: generate a fresh key so the Systemd backend is satisfied
            import secrets
            key = secrets.token_bytes(64)
            with open(os.path.join(creds_tmpdir, 'sync-key'), 'wb') as f:
                f.write(key)
        env['CREDENTIALS_DIRECTORY'] = creds_tmpdir

    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=env)

    time.sleep(FIREFOX_WAIT)

    # Graceful shutdown
    proc.send_signal(signal.SIGTERM)
    try:
        proc.wait(timeout=KILL_WAIT)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)

    if creds_tmpdir and os.path.exists(creds_tmpdir):
        import shutil
        shutil.rmtree(creds_tmpdir, ignore_errors=True)

    exit_code = proc.returncode
    stderr_raw = proc.stderr.read().decode('utf-8', errors='replace')
    # EncryptionKeyManager logs appear at startup; IPC shutdown noise is at the end.
    # Capture both ends so neither is lost, and pull out any EKM lines explicitly.
    ekm_lines = [l for l in stderr_raw.splitlines()
                 if 'EncryptionKeyManager' in l or 'QuotaManager:' in l]
    stderr_text = ''
    if ekm_lines:
        stderr_text += '[EKM] ' + '\n[EKM] '.join(ekm_lines) + '\n'
    stderr_text += stderr_raw[:1000]
    if len(stderr_raw) > 2000:
        stderr_text += '\n...\n' + stderr_raw[-500:]

    # Find and inspect IDB files
    files = find_idb_files(profile_dir)
    if not files:
        return {
            'idb_status': 'fail',
            'encryption': encryption,
            'details': 'No .sqlite files found in profile storage',
            'files_found': 0,
            'firefox_exit_code': exit_code,
            'firefox_stderr': stderr_text,
        }

    readable_files = []
    unreadable_files = []
    for f in files:
        fname = os.path.basename(f)
        if is_valid_sqlite(f):
            readable_files.append(fname)
        else:
            unreadable_files.append(fname)

    if encryption:
        # With encryption: ALL files should be unreadable
        if len(unreadable_files) == len(files):
            status = 'pass'
            details = f'All {len(files)} .sqlite files are encrypted (not valid SQLite)'
        else:
            status = 'fail'
            details = (f'{len(readable_files)}/{len(files)} files still readable: '
                       f'{readable_files}')
    else:
        # Without encryption: at least some files should be readable
        if readable_files:
            status = 'pass'
            details = f'{len(readable_files)}/{len(files)} .sqlite files are valid SQLite'
        else:
            status = 'fail'
            details = f'No .sqlite files are readable (all {len(files)} unreadable)'

    return {
        'idb_status': status,
        'encryption': encryption,
        'details': details,
        'files_found': len(files),
        'readable': len(readable_files),
        'unreadable': len(unreadable_files),
        'firefox_exit_code': exit_code,
        'firefox_stderr': stderr_text,
    }


def main():
    parser = argparse.ArgumentParser(description='IDB encryption verification')
    parser.add_argument('--encryption', action='store_true',
                        help='Enable dom.quotaManager.encryption.enabled')
    parser.add_argument('--binary', default='firefox',
                        help='Path to Firefox binary')
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix='idb-verify-') as profile_dir:
        result = run_firefox(args.binary, profile_dir, encryption=args.encryption)

    print(json.dumps(result))


if __name__ == '__main__':
    main()
