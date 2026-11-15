#!/usr/bin/env python3
"""Run the compiled native interface checker with a bounded lifetime."""

import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    executable = os.environ.get("INTERFACE_CHECK_EXECUTABLE")
    if not executable:
        directory = subprocess.check_output(["swift", "build", "--show-bin-path"], text=True, timeout=30).strip()
        executable = str(Path(directory) / "AlphaSyncUIChecks")
    started = time.monotonic()
    phases = [(args.output, []), (args.output / "window-scene", ["--window-scene"])]
    for output, options in phases:
        output.mkdir(parents=True, exist_ok=True)
        remaining = 120 - (time.monotonic() - started)
        if remaining <= 0:
            print("Native interface checks exceeded their combined 120-second deadline.", file=sys.stderr, flush=True)
            return 1
        print("Launching compiled native interface checks: " + executable + " " + " ".join(options), flush=True)
        child = subprocess.Popen([executable, str(output), *options], start_new_session=True)
        try:
            result = child.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            print("Native interface checks exceeded 120 seconds; saving a process sample.", file=sys.stderr, flush=True)
            try:
                subprocess.run(["/usr/bin/sample", str(child.pid), "1", "1", "-file", str(output / "timeout-sample.txt")],
                               check=False, timeout=10)
            except (OSError, subprocess.TimeoutExpired) as error:
                print("Could not collect the process sample: " + str(error), file=sys.stderr, flush=True)
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
        if result != 0:
            return result
    print("Native interface checks passed. No USB devices or login registrations were changed.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
