#!/usr/bin/env python3
"""Run a native interface check with a deadline and a macOS process sample."""

import argparse
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile


def sample_process(process):
    if sys.platform != 'darwin' or not shutil.which('sample'):
        return
    with tempfile.TemporaryDirectory(prefix='alphasync-interface-') as directory:
        report = Path(directory) / 'sample.txt'
        try:
            subprocess.run(['sample', str(process.pid), '5', '-file', str(report)],
                           stdout=sys.stderr, stderr=sys.stderr, timeout=15, check=False)
            if report.exists():
                print(report.read_text(errors='replace'), file=sys.stderr, flush=True)
        except (OSError, subprocess.TimeoutExpired) as error:
            print(f'Could not sample the stalled interface check: {error}', file=sys.stderr, flush=True)


def stop_process(process):
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
    except ProcessLookupError:
        process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout', type=float, default=180)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.timeout <= 0 or not args.command:
        parser.error('Supply a positive timeout and an interface-check command.')
    process = subprocess.Popen(args.command, start_new_session=True)
    try:
        result = process.wait(timeout=args.timeout)
        return result if result >= 0 else 128 - result
    except subprocess.TimeoutExpired:
        print(f'Interface check exceeded {args.timeout:g} seconds; sampling process {process.pid}.',
              file=sys.stderr, flush=True)
        try:
            sample_process(process)
        finally:
            stop_process(process)
        return 124


if __name__ == '__main__':
    sys.exit(main())
