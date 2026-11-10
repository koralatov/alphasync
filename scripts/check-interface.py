#!/usr/bin/env python3
"""Run the compiled native interface checker with a bounded lifetime."""

import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    executable = os.environ.get("INTERFACE_CHECK_EXECUTABLE")
    if not executable:
        directory = subprocess.check_output(["swift", "build", "--show-bin-path"], text=True, timeout=30).strip()
        executable = str(Path(directory) / "AlphaSyncUIChecks")
    print("Launching compiled native interface checks: " + executable, flush=True)
    child = subprocess.Popen([executable, str(args.output)], start_new_session=True)
    try:
        return child.wait(timeout=120)
    except subprocess.TimeoutExpired:
        print("Native interface checks exceeded 120 seconds; saving a process sample.", file=sys.stderr, flush=True)
        try:
            subprocess.run(["/usr/bin/sample", str(child.pid), "1", "1", "-file", str(args.output / "timeout-sample.txt")],
                           check=False, timeout=10)
        except (OSError, subprocess.TimeoutExpired) as error:
            print("Could not collect the process sample: " + str(error), file=sys.stderr)
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait()
        return 1


if __name__ == "__main__":
    sys.exit(main())
