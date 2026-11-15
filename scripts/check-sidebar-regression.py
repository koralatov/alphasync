#!/usr/bin/env python3
"""Probe build 161’s sidebar button in an isolated, bounded native application."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import tempfile

BASELINE = "1b5495c5b78efcbb09c9a700c0caf18d82047a0b"
ROOT = Path(__file__).resolve().parent.parent

PROBE = r'''
    private func run(in window: NSWindow) async throws {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        store.devices = [try InterfaceChecks.sample()]
        store.reconcileSelection()
        await InterfaceChecks.yieldLayout()
        await resize(window, width: 760, height: 460)
        func record(_ stage: String) throws {
            let value: [String: Any] = ["stage": stage,
                "toolbar": window.toolbar?.items.map(\.label) ?? [],
                "frame": InterfaceChecks.frameRecord(window.frame)]
            try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("probe.json"), options: .atomic)
            InterfaceChecks.checkpoint("Build 161 sidebar probe: " + stage)
        }
        func activate() throws {
            guard let item = window.toolbar?.items.first(where: { $0.label.localizedCaseInsensitiveContains("sidebar") }) else {
                try InterfaceChecks.require(false, "Build 161 did not expose its sidebar button")
                return
            }
            if let action = item.action {
                try InterfaceChecks.require(NSApplication.shared.sendAction(action, to: item.target, from: item), "The native sidebar action was not handled")
            } else if let view = item.view, view.window === window {
                let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
                guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
                    let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0) else {
                    try InterfaceChecks.require(false, "Cannot construct the native sidebar click")
                    return
                }
                // Queue mouse-up before the synchronous AppKit tracking loop begins.
                NSApplication.shared.postEvent(up, atStart: false)
                window.sendEvent(down)
            } else {
                try InterfaceChecks.require(false, "The native sidebar item has no public action or view")
            }
        }
        try capture(window, "before-hide")
        try record("before-hide")
        try activate()
        await InterfaceChecks.yieldLayout()
        try record("after-hide")
        try capture(window, "after-hide")
        try record("complete")
    }
}
'''


def run(command, **kwargs):
    return subprocess.run(command, check=True, timeout=180, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    output = parser.parse_args().output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if subprocess.run(["git", "cat-file", "-e", BASELINE + "^{commit}"], cwd=ROOT,
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        run(["git", "fetch", "--no-tags", "--depth=1", "origin", BASELINE], cwd=ROOT)
    report = {"baselineSource": BASELINE, "hardware": "Hosted Apple Silicon; no physical Neo",
              "system": subprocess.check_output(["sw_vers"], text=True), "deadlineSeconds": 20,
              "sourceChanges": "Only the diagnostic window driver is replaced; shipping sources are exact build 161."}
    with tempfile.TemporaryDirectory(prefix="AlphaSyncSidebar161-") as temporary:
        checkout = Path(temporary) / "source"
        checkout.mkdir()
        archive = Path(temporary) / "source.tar"
        with archive.open("wb") as stream:
            run(["git", "archive", BASELINE], cwd=ROOT, stdout=stream)
        run(["tar", "-xf", str(archive), "-C", str(checkout)])
        original = checkout / "Sources/AlphaSyncUI/MainView.swift"
        report["mainViewSHA256"] = hashlib.sha256(original.read_bytes()).hexdigest()
        driver = checkout / "Tests/AlphaSyncUIChecks/WindowSceneChecks.swift"
        marker = "    private func run(in window: NSWindow) async throws {"
        text = driver.read_text()
        if text.count(marker) != 1:
            raise RuntimeError("The pinned baseline driver did not match the reviewed source")
        driver.write_text(text.split(marker)[0] + PROBE)
        with (output / "compile.log").open("w") as log:
            run(["swift", "build", "--product", "AlphaSyncUIChecks"], cwd=checkout, stdout=log, stderr=subprocess.STDOUT)
        binary_dir = subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=checkout, text=True, timeout=30).strip()
        bundle = Path(temporary) / "AlphaSyncSidebar161.app"
        contents = bundle / "Contents"
        executable = contents / "MacOS/AlphaSyncUIChecks"
        executable.parent.mkdir(parents=True)
        shutil.copy2(Path(binary_dir) / "AlphaSyncUIChecks", executable)
        info = {"CFBundleIdentifier": "com.koralatov.AlphaSyncSidebar161", "CFBundleName": "AlphaSyncSidebar161",
                "CFBundleExecutable": "AlphaSyncUIChecks", "CFBundlePackageType": "APPL",
                "CFBundleVersion": "0", "CFBundleShortVersionString": "0", "LSMinimumSystemVersion": "13.0",
                "NSPrincipalClass": "NSApplication", "NSHighResolutionCapable": True}
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        run(["codesign", "--force", "--sign", "-", str(bundle)])
        command = ["/usr/bin/open", "-n", "-W", "--stdout", str(output / "stdout.log"),
                   "--stderr", str(output / "stderr.log"), str(bundle), "--args", "--window-scene",
                   "--output-directory=" + str(output)]
        child = subprocess.Popen(command, start_new_session=True)
        timed_out = False
        try:
            child.wait(timeout=20)
        except subprocess.TimeoutExpired:
            timed_out = True
            target = int((output / "process-id").read_text()) if (output / "process-id").exists() else child.pid
            if target <= 1:
                raise RuntimeError("The diagnostic application did not record a valid process ID")
            subprocess.run(["/usr/bin/sample", str(target), "1", "1", "-file", str(output / "timeout-sample.txt")],
                           check=False, timeout=10)
            if target != child.pid:
                try:
                    os.kill(target, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait(timeout=5)
        probe = json.loads((output / "probe.json").read_text()) if (output / "probe.json").exists() else {}
        report["lastProbe"] = probe
        report["timedOut"] = timed_out
        if timed_out and probe.get("stage") == "before-hide":
            report["outcome"] = "hang-after-sidebar-action"
        elif (not timed_out and probe.get("stage") == "complete" and (output / "result.json").exists()
              and json.loads((output / "result.json").read_text()) == {"passed": True, "layouts": 0}):
            report["outcome"] = "no-hang-reproduced"
        else:
            report["outcome"] = "probe-failed"
        (output / "diagnosis.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2), flush=True)
        for name in ["stdout.log", "stderr.log"]:
            if (output / name).exists():
                print((output / name).read_text(errors="replace"), flush=True)
        return 1 if report["outcome"] == "probe-failed" else 0


if __name__ == "__main__":
    raise SystemExit(main())
