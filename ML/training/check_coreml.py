#!/usr/bin/env python3
"""CI check (macOS): the Core ML model loads, has the inputs the app expects, and reproduces the
PyTorch model's outputs on fixture recordings (expected.json from make_fixtures.py).

Usage: python check_coreml.py WatchApp/ML/ExerciseActivityClassifier.mlpackage ML/training/fixtures
"""
import json
import os
import sys

import coremltools as ct
import numpy as np

COLUMNS = ["gravity_forearm", "gravity_palm", "gravity_radial", "accel_forearm", "accel_palm", "accel_radial",
           "rotation_forearm", "rotation_palm", "rotation_radial"]

path, folder = sys.argv[1], sys.argv[2]
model = ct.models.MLModel(path)
spec = model.get_spec()
inputs = [i.name for i in spec.description.input]
meta = dict(spec.description.metadata.userDefined)
print("inputs:", inputs)
print("outputs:", [o.name for o in spec.description.output])
print("metadata:", meta)
assert sorted(inputs) == sorted(COLUMNS), "model inputs must match the app's arm-frame columns"
window = int(meta["window"])
rate = float(meta["sample_rate"])
expected = json.load(open(os.path.join(folder, "expected.json")))

worst = 0.0
for name, exp in sorted(expected.items()):
    data = np.loadtxt(os.path.join(folder, name), delimiter=",", skiprows=1, ndmin=2)
    t, x = data[:, 0], data[:, 1:10]
    factor = max(1, int(round((len(t) - 1) / (t[-1] - t[0]) / rate)))
    n = (len(x) // factor) * factor
    x = x[:n].reshape(-1, factor, 9).mean(1)
    x[:, 0:3] /= np.linalg.norm(x[:, 0:3], axis=1, keepdims=True)
    sums, count = {}, 0
    for s in range(0, len(x) - window + 1, window // 2):
        out = model.predict({c: x[s:s + window, k].astype(np.float32) for k, c in enumerate(COLUMNS)})
        probs = next(v for v in out.values() if isinstance(v, dict))
        for k, v in probs.items():
            sums[k] = sums.get(k, 0.0) + v
        count += 1
    got = {k: v / count for k, v in sums.items()}
    diff = max(abs(got.get(k, 0.0) - v) for k, v in exp.items())
    worst = max(worst, diff)
    top = sorted(got.items(), key=lambda kv: -kv[1])[:3]
    print(f"{name:28s} max |coreml - pytorch| = {diff:.4f}   top: " + ", ".join(f"{k} {v:.0%}" for k, v in top))
print("worst difference", round(worst, 4))
sys.exit(0 if worst < 0.03 else 1)
