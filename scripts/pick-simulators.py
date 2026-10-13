#!/usr/bin/env python3
"""Neuestes iOS im Simulator und darauf ein iPhone und ein iPad wählen.

Schreibt für GitHub Actions:  iphone=<udid>  ipad=<udid>  iphone_name=…  ipad_name=…
"""
import json
import re
import subprocess
import sys

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))


def version(runtime: str):
    match = re.search(r"iOS-(\d+)-(\d+)(?:-(\d+))?", runtime)
    return tuple(int(part or 0) for part in match.groups()) if match else (0, 0, 0)


runtimes = sorted((key for key in data["devices"] if "iOS" in key), key=version, reverse=True)
if not runtimes:
    sys.exit("Kein iOS-Simulator gefunden.")


def pick(prefixes, devices):
    for prefix in prefixes:
        for device in devices:
            if device["name"].startswith(prefix):
                return device
    return None


for runtime in runtimes:
    devices = [device for device in data["devices"][runtime] if device.get("isAvailable", True)]
    iphone = pick(["iPhone 17 Pro", "iPhone 16 Pro", "iPhone 17", "iPhone 16", "iPhone"], devices)
    ipad = pick(["iPad Pro 13-inch", "iPad Pro (12.9-inch)", "iPad Air 13-inch", "iPad Pro", "iPad Air", "iPad"], devices)
    if iphone and ipad:
        print(f"iphone={iphone['udid']}")
        print(f"ipad={ipad['udid']}")
        print(f"iphone_name={iphone['name']}")
        print(f"ipad_name={ipad['name']}")
        print(f"runtime={runtime.split('.')[-1]}")
        sys.exit(0)

sys.exit("Kein passendes iPhone/iPad im Simulator.")
