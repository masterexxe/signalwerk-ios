#!/usr/bin/env python3
"""Ergebnisse eines Laufs für den Zweig ci-results aufbereiten.

  export-results.py <ausgabe> <name>=<pfad.xcresult> …

Legt die Bilder aus den UI-Tests mit lesbaren Namen ab, schreibt Fehler und Warnungen aus den
Build-Logs in summary.md und kürzt die Logs.
"""
import json
import os
import re
import shutil
import subprocess
import sys

out = sys.argv[1]
os.makedirs(f"{out}/screens", exist_ok=True)
summary = []


def run(args):
    return subprocess.run(args, capture_output=True, text=True)


def upright(path):
    """iPad-Bilder entstehen im Querformat, liegen aber hochkant in der Datei: drehen."""
    sizes = run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path]).stdout
    width = re.search(r"pixelWidth: (\d+)", sizes)
    height = re.search(r"pixelHeight: (\d+)", sizes)
    if width and height and int(height.group(1)) > int(width.group(1)):
        run(["sips", "--rotate", "270", path])


for spec in sys.argv[2:]:
    name, path = spec.split("=", 1)
    if not os.path.exists(path):
        summary.append(f"## {name}\n\nKein Ergebnis ({path} fehlt).\n")
        continue
    temp = f"/tmp/attachments-{name}"
    shutil.rmtree(temp, ignore_errors=True)
    result = run(["xcrun", "xcresulttool", "export", "attachments", "--path", path, "--output-path", temp])
    manifest = os.path.join(temp, "manifest.json")
    count = 0
    if os.path.exists(manifest):
        with open(manifest) as handle:
            tests = json.load(handle)
        for test in tests:
            for attachment in test.get("attachments", []):
                exported = attachment.get("exportedFileName")
                human = attachment.get("suggestedHumanReadableName") or exported
                if not exported:
                    continue
                clean = re.sub(r"_\d+_[0-9A-F-]{36}", "", human)
                clean = re.sub(r"[^A-Za-z0-9._-]+", "-", clean)
                target = os.path.join(out, "screens", clean)
                shutil.copy(os.path.join(temp, exported), target)
                if clean.startswith("ipad-") and clean.endswith(".png"):
                    upright(target)
                count += 1
    else:
        summary.append(f"Anhänge aus {name} nicht lesbar: {result.stderr.strip()[:400]}\n")
    # Ergebnis der Tests in Kurzform.
    tests = run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", path])
    text = tests.stdout.strip()
    try:
        data = json.loads(text)
        line = f"{data.get('result', '?')}: {data.get('passedTests', 0)} bestanden, {data.get('failedTests', 0)} fehlgeschlagen, {data.get('skippedTests', 0)} übersprungen"
        failures = data.get("testFailures", [])
        details = "\n".join(f"- {item.get('testName')}: {item.get('failureText', '')[:300]}" for item in failures)
    except ValueError:
        line = text[:300] or tests.stderr.strip()[:300]
        details = ""
    summary.append(f"## {name}\n\n{line}\n\n{details}\nBilder: {count}\n")

# Logs: Fehler und Warnungen aus dem eigenen Code herausziehen.
issues = []
for log in sorted(os.listdir(out)):
    if not log.endswith(".log"):
        continue
    with open(os.path.join(out, log), errors="replace") as handle:
        lines = handle.readlines()
    for line in lines:
        if re.search(r"(error|warning): ", line) and ("/Signalwerk" in line or "SignalwerkKit" in line or "error:" in line):
            issues.append(f"{log}: {line.strip()}")
    # Logs kürzen: Anfang und Ende genügen, die Fehler stehen in summary.md.
    if len(lines) > 1500:
        with open(os.path.join(out, log), "w") as handle:
            handle.writelines(lines[:200] + ["\n… gekürzt …\n\n"] + lines[-1200:])

seen = set()
unique = [issue for issue in issues if not (issue in seen or seen.add(issue))]
with open(os.path.join(out, "summary.md"), "w") as handle:
    handle.write("# Lauf\n\n")
    handle.write("\n".join(summary))
    handle.write("\n## Fehler und Warnungen\n\n")
    handle.write("\n".join(unique[:400]) if unique else "keine\n")
print(f"{len(unique)} Meldungen, Bilder in {out}/screens")
