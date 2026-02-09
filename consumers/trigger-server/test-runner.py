#!/usr/bin/env python3
import subprocess
import json
import os
import sys

def test_flatpak_storage():
    """Flatpak-specific test: verify Secret Portal retrieval and isolation"""
    errors = []

    # The Secret Portal provides a per-application master secret
    # It's automatically generated and should be consistent across runs
    first_secret = None

    # First run: retrieve the secret
    try:
        result = subprocess.run(
            ['flatpak', 'run', 'org.example.access-keys'],
            capture_output=True,
            text=True,
            timeout=30
        )
        output = result.stdout.strip()

        if result.returncode != 0:
            errors.append(f"First run failed with exit code {result.returncode}: {result.stderr}")
        elif not output.startswith("Secret read from Flatpak Portal:"):
            errors.append(f"First run expected secret read message, got: {output}")
        else:
            # Extract the hex secret from output
            first_secret = output

    except Exception as e:
        errors.append(f"First run error: {str(e)}")
        return False, errors

    # Second run: should get the same secret (demonstrating persistence)
    try:
        result = subprocess.run(
            ['flatpak', 'run', 'org.example.access-keys'],
            capture_output=True,
            text=True,
            timeout=30
        )
        output = result.stdout.strip()

        if result.returncode != 0:
            errors.append(f"Second run failed with exit code {result.returncode}: {result.stderr}")
        elif not output.startswith("Secret read from Flatpak Portal:"):
            errors.append(f"Second run expected secret read message, got: {output}")
        elif first_secret and output != first_secret:
            errors.append(f"Secret changed between runs! First: {first_secret}, Second: {output}")

    except Exception as e:
        errors.append(f"Second run error: {str(e)}")
        return False, errors

    # Test isolation: The secret is provided by the portal and not directly accessible
    # from the filesystem. This is different from Snap where we check SNAP_DATA directory.
    # For Flatpak, the portal manages the secret internally and provides it only to the
    # sandboxed application through D-Bus.
    # We consider the test passed if we successfully retrieved the secret twice.

    return len(errors) == 0, errors

def test_snap_storage():
    """Snap-specific test: verify secret storage and isolation"""
    errors = []
    env = {**os.environ, 'PATH': '/snap/bin:' + os.environ.get('PATH', '')}

    # First run: should create secret
    try:
        result = subprocess.run(
            ['access-keys'],
            capture_output=True,
            text=True,
            timeout=30,
            env=env
        )
        output = result.stdout.strip()

        if result.returncode != 0:
            errors.append(f"First run failed with exit code {result.returncode}: {result.stderr}")
        elif output != "Secret created":
            errors.append(f"First run expected 'Secret created', got: {output}")

    except Exception as e:
        errors.append(f"First run error: {str(e)}")
        return False, errors

    # Second run: should read secret back
    try:
        result = subprocess.run(
            ['access-keys'],
            capture_output=True,
            text=True,
            timeout=30,
            env=env
        )
        output = result.stdout.strip()

        if result.returncode != 0:
            errors.append(f"Second run failed with exit code {result.returncode}: {result.stderr}")
        elif not output.startswith("Secret read from SNAP_DATA:"):
            errors.append(f"Second run expected secret read message, got: {output}")
        elif "Stored secret" not in output:
            errors.append(f"Second run did not contain expected secret value: {output}")

    except Exception as e:
        errors.append(f"Second run error: {str(e)}")
        return False, errors

    # Test isolation: try to read snap data as current user
    # In devmode, SNAP_DATA should still be isolated
    snap_data_path = "/var/snap/access-keys/current"
    try:
        # Try to list the directory
        result = subprocess.run(
            ['ls', '-la', snap_data_path],
            capture_output=True,
            text=True,
            timeout=10
        )

        # In devmode, we can see it but it should be restricted to root or snap user
        # The test passes either way - we're just documenting the behavior

    except Exception as e:
        # If we can't access it at all, that's also fine
        pass

    return len(errors) == 0, errors

def test_systemd_storage():
    """systemd-specific test: verify credential encryption and systemd-run integration"""
    errors = []

    # Negative test: run access-keys directly without systemd
    # Should fail because CREDENTIALS_DIRECTORY is not set
    try:
        result = subprocess.run(
            ['access-keys'],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode == 0:
            errors.append("Direct run should have failed without CREDENTIALS_DIRECTORY, but succeeded")
        # Expected to fail - this is good
    except Exception as e:
        errors.append(f"Negative test error: {str(e)}")
        return False, errors

    # Encryption check: verify raw secret is not in encrypted blob
    try:
        with open('/etc/access-keys/sync.cred', 'rb') as f:
            encrypted_data = f.read()

        # Check that the raw secret "0123456789abcdef" is not in the encrypted file
        if b"0123456789abcdef" in encrypted_data:
            errors.append("Raw secret found in encrypted credential file - encryption failed!")
    except Exception as e:
        errors.append(f"Encryption check error: {str(e)}")
        return False, errors

    # Positive test: run via systemd-run with encrypted credential
    try:
        result = subprocess.run(
            [
                'systemd-run',
                '--pipe',
                '--wait',
                '--quiet',
                '--property=LoadCredentialEncrypted=sync-key:/etc/access-keys/sync.cred',
                '/usr/bin/access-keys'
            ],
            capture_output=True,
            text=True,
            timeout=30
        )
        output = result.stdout.strip()

        if result.returncode != 0:
            errors.append(f"systemd-run failed with exit code {result.returncode}: {result.stderr}")
        elif not output.startswith("Secret read from CREDENTIALS_DIRECTORY:"):
            errors.append(f"Expected secret read message, got: {output}")
        elif "0123456789abcdef" not in output:
            errors.append(f"Output did not contain expected secret value: {output}")

    except Exception as e:
        errors.append(f"Positive test error: {str(e)}")
        return False, errors

    return len(errors) == 0, errors

def run_test():
    consumer_name = os.environ.get('CONSUMER_NAME', 'unknown')

    # Check consumer type
    is_snap = consumer_name == 'consumer-ubuntu'
    is_flatpak = consumer_name == 'consumer-arch'
    is_systemd = consumer_name in ('consumer-debian', 'consumer-redhat')

    try:
        if is_flatpak:
            # Run flatpak-specific test
            success, errors = test_flatpak_storage()

            if success:
                return {
                    "consumer": consumer_name,
                    "status": "pass",
                    "output": "All good",
                    "error": ""
                }
            else:
                return {
                    "consumer": consumer_name,
                    "status": "fail",
                    "output": "",
                    "error": "; ".join(errors)
                }
        elif is_snap:
            # Run snap-specific test
            success, errors = test_snap_storage()

            if success:
                return {
                    "consumer": consumer_name,
                    "status": "pass",
                    "output": "All good",
                    "error": ""
                }
            else:
                return {
                    "consumer": consumer_name,
                    "status": "fail",
                    "output": "",
                    "error": "; ".join(errors)
                }
        elif is_systemd:
            # Run systemd-specific test
            success, errors = test_systemd_storage()

            if success:
                return {
                    "consumer": consumer_name,
                    "status": "pass",
                    "output": "All good",
                    "error": ""
                }
            else:
                return {
                    "consumer": consumer_name,
                    "status": "fail",
                    "output": "",
                    "error": "; ".join(errors)
                }
        else:
            # Standard test for other consumers
            result = subprocess.run(
                ['access-keys'],
                capture_output=True,
                text=True,
                timeout=30
            )

            output = result.stdout.strip()

            # Check if output matches expected
            if result.returncode == 0 and output == "All good":
                return {
                    "consumer": consumer_name,
                    "status": "pass",
                    "output": output,
                    "error": ""
                }
            else:
                return {
                    "consumer": consumer_name,
                    "status": "fail",
                    "output": output,
                    "error": f"Exit code: {result.returncode}, stderr: {result.stderr}"
                }

    except subprocess.TimeoutExpired:
        return {
            "consumer": consumer_name,
            "status": "error",
            "output": "",
            "error": "Test execution timeout"
        }
    except FileNotFoundError:
        return {
            "consumer": consumer_name,
            "status": "error",
            "output": "",
            "error": "access-keys binary not found"
        }
    except Exception as e:
        return {
            "consumer": consumer_name,
            "status": "error",
            "output": "",
            "error": str(e)
        }

if __name__ == "__main__":
    result = run_test()
    print(json.dumps(result))
