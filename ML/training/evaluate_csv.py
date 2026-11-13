#!/usr/bin/env python3
"""Runs the trained exercise model on recordings in the app's CSV format and prints its guesses.

Works with the CSVs the iPhone app exports (Settings > Prepare export for Create ML), so you can see
how the model does on your own sets.

Usage:
    python evaluate_csv.py MODEL_DIR file1.csv [file2.csv ...]
    python evaluate_csv.py MODEL_DIR TrainingData/            # walks <exercise>/<set>.csv folders

MODEL_DIR must contain model.pt and classes.json (written by train_model.py).
"""
import json
import os
import sys

import numpy as np
import torch
import torch.nn.functional as F

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from train_model import RATE, WINDOW, ExerciseNet  # noqa: E402


def load_csv(path):
    data = np.loadtxt(path, delimiter=",", skiprows=1, ndmin=2)
    t, x = data[:, 0], data[:, 1:10]
    rate = (len(t) - 1) / (t[-1] - t[0]) if len(t) > 1 and t[-1] > t[0] else 50.0
    factor = max(1, int(round(rate / RATE)))
    n = (len(x) // factor) * factor
    x = x[:n].reshape(-1, factor, 9).mean(1)
    x[:, 0:3] /= np.linalg.norm(x[:, 0:3], axis=1, keepdims=True)
    return x.astype(np.float32)


def classify(model, x, classes):
    if len(x) < WINDOW:
        return None
    starts = range(0, len(x) - WINDOW + 1, WINDOW // 2)
    batch = torch.from_numpy(np.stack([x[s:s + WINDOW] for s in starts])).permute(0, 2, 1)
    with torch.no_grad():
        p = F.softmax(model(batch), dim=1).mean(0).numpy()
    order = np.argsort(-p)[:3]
    return [(classes[i], float(p[i])) for i in order]


def main():
    model_dir, paths = sys.argv[1], sys.argv[2:]
    classes = json.load(open(os.path.join(model_dir, "classes.json")))
    model = ExerciseNet(len(classes))
    model.load_state_dict(torch.load(os.path.join(model_dir, "model.pt"), map_location="cpu"))
    model.eval()
    files = []
    for p in paths:
        if os.path.isdir(p):
            for root, _, names in os.walk(p):
                files += [os.path.join(root, n) for n in sorted(names) if n.endswith(".csv")]
        else:
            files.append(p)
    for f in files:
        guess = classify(model, load_csv(f), classes)
        label = os.path.basename(os.path.dirname(f))
        shown = " | ".join(f"{c} {p:.0%}" for c, p in guess) if guess else "too short"
        print(f"{os.path.relpath(f):55s} -> {shown}" + (f"   (labelled {label})" if label in classes else ""))


if __name__ == "__main__":
    main()
