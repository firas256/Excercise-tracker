#!/usr/bin/env python3
"""Exports screenshot attachments from .xcresult bundles with readable file names.

Usage: python3 scripts/export_screenshots.py <dir-with-xcresults> <output-dir>
Requires Xcode 16+ (`xcresulttool export attachments`).
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)


def walk(node):
    if isinstance(node, dict):
        if "exportedFileName" in node:
            yield node
        for v in node.values():
            yield from walk(v)
    elif isinstance(node, list):
        for v in node:
            yield from walk(v)


for bundle in sorted(os.listdir(src)):
    if not bundle.endswith(".xcresult"):
        continue
    tmp = tempfile.mkdtemp()
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", os.path.join(src, bundle),
                    "--output-path", tmp], check=False)
    manifest_path = os.path.join(tmp, "manifest.json")
    if not os.path.exists(manifest_path):
        print(f"no attachments in {bundle}")
        continue
    with open(manifest_path) as f:
        manifest = json.load(f)
    for att in walk(manifest):
        name = att.get("suggestedHumanReadableName") or att["exportedFileName"]
        name = re.sub(r"_\d+_[0-9A-Fa-f-]{36}", "", name)
        shutil.copy(os.path.join(tmp, att["exportedFileName"]), os.path.join(out, name))
        print("exported", name)
