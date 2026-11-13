#!/usr/bin/env python3
"""Loads the shipped Core ML model and runs it on fixture windows (CI runs this on macOS, where
Core ML predictions are available). Fails if the model can't be loaded or a fixture is misread.

Usage: python check_coreml.py WatchApp/ML/ExerciseActivityClassifier.mlpackage ML/training/fixtures
Fixtures are CSVs in the app's arm-frame format named <expectedExercise>.csv (50 Hz).
"""
import os
import sys

import coremltools as ct
import numpy as np

path, fixtures = sys.argv[1], sys.argv[2]
model = ct.models.MLModel(path)
spec = model.get_spec()
inputs = [i.name for i in spec.description.input]
meta = dict(spec.description.metadata.userDefined)
window = int(meta.get("window", 128))
rate = float(meta.get("sample_rate", 25))
print("inputs:", inputs)
print("outputs:", [o.name for o in spec.description.output])
print("metadata:", meta)

columns = ["gravity_forearm", "gravity_palm", "gravity_radial", "accel_forearm", "accel_palm", "accel_radial",
           "rotation_forearm", "rotation_palm", "rotation_radial"]
failures = 0
for name in sorted(os.listdir(fixtures)):
    if not name.endswith(".csv"):
        continue
    expected = name[:-4]
    data = np.loadtxt(os.path.join(fixtures, name), delimiter=",", skiprows=1, ndmin=2)
    t, x = data[:, 0], data[:, 1:10]
    factor = max(1, int(round((len(t) - 1) / (t[-1] - t[0]) / rate)))
    n = (len(x) // factor) * factor
    x = x[:n].reshape(-1, factor, 9).mean(1)
    x[:, 0:3] /= np.linalg.norm(x[:, 0:3], axis=1, keepdims=True)
    sums = {}
    count = 0
    for s in range(0, len(x) - window + 1, window // 2):
        out = model.predict({c: x[s:s + window, k].astype(np.float32) for k, c in enumerate(columns)})
        probs = next(v for v in out.values() if isinstance(v, dict))
        for k, v in probs.items():
            sums[k] = sums.get(k, 0) + v
        count += 1
    ranked = sorted(((v / count, k) for k, v in sums.items()), reverse=True)[:3]
    ok = ranked[0][1] == expected
    failures += not ok
    print(f"{'OK  ' if ok else 'FAIL'} {expected:22s} -> " + ", ".join(f"{k} {p:.0%}" for p, k in ranked))
sys.exit(1 if failures else 0)
