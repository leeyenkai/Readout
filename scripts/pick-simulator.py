#!/usr/bin/env python3
"""Prints a runtime and device-type identifier CI can create a simulator from.

Neither is hard-coded, because the GitHub runner image decides which iOS runtimes and
iPhones it ships and the newest of each are not necessarily compatible: asking simctl for
the newest device type outright gets an "Incompatible device" error from `simctl create`.
The device is therefore chosen from the runtime's own supported list.

Usage: xcrun simctl list runtimes --json | scripts/pick-simulator.py
Output: "<runtime identifier> <device type identifier>"
"""

import json
import re
import sys


def version(text: str) -> list[int]:
    return [int(part) for part in re.findall(r"\d+", text)]


def main() -> int:
    runtimes = [
        runtime
        for runtime in json.load(sys.stdin)["runtimes"]
        if runtime["isAvailable"]
        and runtime["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS")
    ]
    if not runtimes:
        print("no available iOS runtime on this machine", file=sys.stderr)
        return 1
    runtime = max(runtimes, key=lambda r: version(r["version"]))

    phones = [
        device
        for device in runtime.get("supportedDeviceTypes", [])
        if re.fullmatch(r"iPhone \d+.*", device["name"])
    ]
    if not phones:
        print(f"no iPhone device type for {runtime['identifier']}", file=sys.stderr)
        return 1
    device = max(phones, key=lambda d: version(d["name"]))

    print(runtime["identifier"], device["identifier"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
