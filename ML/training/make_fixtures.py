#!/usr/bin/env python3
"""Writes expected model outputs for the CI Core ML check.

Usage: python make_fixtures.py MODEL_DIR ML/training/fixtures
Reads every *.csv in the fixtures folder (app arm-frame format), runs the PyTorch model exactly as
check_coreml.py runs the Core ML model, and stores the averaged probabilities in expected.json.
"""
import json
import os
import sys

import numpy as np
import torch
import torch.nn.functional as F

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from evaluate_csv import load_csv  # noqa: E402
from train_model import WINDOW, ExerciseNet  # noqa: E402

model_dir, folder = sys.argv[1], sys.argv[2]
classes = json.load(open(os.path.join(model_dir, "classes.json")))
model = ExerciseNet(len(classes))
model.load_state_dict(torch.load(os.path.join(model_dir, "model.pt"), map_location="cpu"))
model.eval()
expected = {}
for name in sorted(os.listdir(folder)):
    if not name.endswith(".csv"):
        continue
    x = load_csv(os.path.join(folder, name))
    starts = range(0, len(x) - WINDOW + 1, WINDOW // 2)
    with torch.no_grad():
        p = F.softmax(model(torch.from_numpy(np.stack([x[s:s + WINDOW] for s in starts])).permute(0, 2, 1)), 1).mean(0)
    expected[name] = {c: round(float(v), 5) for c, v in zip(classes, p)}
    top = sorted(expected[name].items(), key=lambda kv: -kv[1])[:3]
    print(name, top)
json.dump(expected, open(os.path.join(folder, "expected.json"), "w"), indent=1)
