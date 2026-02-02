#!/usr/bin/env python3
import subprocess
import json
import os
import sys

def run_test():
    consumer_name = os.environ.get('CONSUMER_NAME', 'unknown')

    try:
        # Try to run access-keys
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
