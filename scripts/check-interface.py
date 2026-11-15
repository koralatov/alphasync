#!/usr/bin/env python3
"""Run native component and real SwiftUI app checks within one bounded lifetime."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time


def run_phase(command, output, deadline, app=False):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        print("Native interface checks exceeded their combined 120-second deadline.", file=sys.stderr, flush=True)
        return 1
    child = subprocess.Popen(command, start_new_session=True)
    try:
        return child.wait(timeout=remaining)
    except subprocess.TimeoutExpired:
        print("Native interface checks exceeded 120 seconds; saving a process sample.", file=sys.stderr, flush=True)
        target = child.pid
        if app and (output / "process-id").exists():
            try:
                candidate = int((output / "process-id").read_text().strip())
                if candidate > 1:
                    target = candidate
            except (OSError, ValueError):
                pass
        try:
            subprocess.run(["/usr/bin/sample", str(target), "1", "1", "-file", str(output / "timeout-sample.txt")],
                           check=False, timeout=10)
        except (OSError, subprocess.TimeoutExpired) as error:
            print("Could not collect the process sample: " + str(error), file=sys.stderr, flush=True)
        for requested in [signal.SIGTERM, signal.SIGKILL]:
            if target != child.pid:
                try:
                    os.kill(target, requested)
                except ProcessLookupError:
                    pass
            try:
                os.killpg(child.pid, requested)
            except ProcessLookupError:
                pass
            try:
                child.wait(timeout=5)
                break
            except subprocess.TimeoutExpired:
                continue
        return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    executable = os.environ.get("INTERFACE_CHECK_EXECUTABLE")
    if not executable:
        directory = subprocess.check_output(["swift", "build", "--show-bin-path"], text=True, timeout=30).strip()
        executable = str(Path(directory) / "AlphaSyncUIChecks")
    deadline = time.monotonic() + 120
    print("Launching compiled native component checks: " + executable, flush=True)
    result = run_phase([executable, str(output)], output, deadline)
    if result:
        return result

    scene = output / "window-scene"
    scene.mkdir(parents=True, exist_ok=True)
    for name in ["result.json", "process-id", "stdout.log", "stderr.log"]:
        (scene / name).unlink(missing_ok=True)
    with tempfile.TemporaryDirectory(prefix="AlphaSyncWindowChecks-") as temporary:
        bundle = Path(temporary) / "AlphaSyncWindowChecks.app"
        contents = bundle / "Contents"
        binary = contents / "MacOS/AlphaSyncUIChecks"
        binary.parent.mkdir(parents=True)
        shutil.copy2(executable, binary)
        info = {"CFBundleIdentifier": "com.koralatov.AlphaSyncWindowChecks", "CFBundleName": "AlphaSyncWindowChecks",
                "CFBundleExecutable": "AlphaSyncUIChecks", "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "0", "CFBundleVersion": "0",
                "LSMinimumSystemVersion": "13.0", "NSPrincipalClass": "NSApplication", "NSHighResolutionCapable": True}
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        subprocess.run(["codesign", "--force", "--sign", "-", str(bundle)], check=True, timeout=15)
        command = ["/usr/bin/open", "-n", "-W", "--stdout", str(scene / "stdout.log"),
                   "--stderr", str(scene / "stderr.log"), str(bundle), "--args", "--window-scene",
                   "--output-directory=" + str(scene)]
        print("Launching the real SwiftUI window-scene app bundle.", flush=True)
        try:
            result = run_phase(command, scene, deadline, app=True)
        finally:
            for name in ["stdout.log", "stderr.log"]:
                path = scene / name
                if path.exists():
                    print(path.read_text(errors="replace"), flush=True)
        if result:
            return result
        receipt = scene / "result.json"
        if not receipt.exists() or json.loads(receipt.read_text()) != {"passed": True, "layouts": 32}:
            print("The window-scene app did not confirm all thirty-two layout checks.", file=sys.stderr, flush=True)
            return 1
    print("Native interface checks passed. No USB devices or login registrations were changed.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
