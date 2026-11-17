#!/usr/bin/env python3
"""Adds your own recorded sets (exported from the iPhone app) to the training data.

The iPhone keeps every confirmed set as Documents/TrainingData/<exercise>/<set-id>.csv, already in
the calibrated arm frame. Settings › "Prepare export" › "Share training data (.zip)" exports them.

Usage:
    python add_user_data.py recofit_armframe.npz RepCoach-TrainingData.zip merged.npz
    python train_model.py merged.npz out --also-test user-holdout

- Your sets are split ~70/30 into "user" (trained on) and "user-holdout" (only evaluated), so the
  report shows how the model does on sets of yours it never saw. The final model (trained after the
  evaluation) uses all of them.
- Your sets are repeated --weight times so a few dozen of them count against thousands of RecoFit ones.
- Exercises the shipped model doesn't know (e.g. tricepsPushdown, hammerCurl) become new classes
  once you have at least --min-sets sets of them; the app reads the model's labels, so no app change
  is needed.
"""
import argparse
import io
import os
import sys
import tempfile
import zipfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from evaluate_csv import load_csv  # noqa: E402
from train_model import WINDOW  # noqa: E402


def iter_sets(source):
    """Yields (exercise, set-id, path) for every <exercise>/<set>.csv in a folder or zip."""
    if os.path.isdir(source):
        for root, _, names in os.walk(source):
            for n in sorted(names):
                if n.endswith(".csv"):
                    yield os.path.basename(root), n[:-4], os.path.join(root, n)
        return
    with zipfile.ZipFile(source) as z, tempfile.TemporaryDirectory() as tmp:
        for info in z.infolist():
            parts = info.filename.replace("\\", "/").split("/")
            if len(parts) < 2 or not parts[-1].endswith(".csv") or parts[-1].startswith("._"):
                continue
            path = os.path.join(tmp, f"{len(os.listdir(tmp))}.csv")
            with open(path, "wb") as f:
                f.write(z.read(info))
            yield parts[-2], parts[-1][:-4], path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base", help="arm-frame npz from prepare_recofit.py")
    ap.add_argument("user", help="exported TrainingData folder or .zip")
    ap.add_argument("out")
    ap.add_argument("--weight", type=int, default=3, help="how many times each of your sets is repeated")
    ap.add_argument("--min-sets", type=int, default=4, help="sets needed for a new exercise class")
    ap.add_argument("--holdout", type=float, default=0.3, help="fraction of your sets kept for evaluation")
    args = ap.parse_args()

    base = np.load(args.base, allow_pickle=True)
    x, y, subject = list(base["x"]), list(base["y"]), list(base["subject"])
    source = list(base["source"]) if "source" in base else ["recofit"] * len(x)
    known = set(y)

    sets = []
    for exercise, set_id, path in iter_sets(args.user):
        try:
            arr = load_csv(path)
        except Exception as e:  # unreadable file: report and skip
            print(f"skipping {exercise}/{set_id}: {e}")
            continue
        if len(arr) < WINDOW:
            print(f"skipping {exercise}/{set_id}: shorter than one {WINDOW}-sample window")
            continue
        sets.append((exercise, set_id, arr))
    if not sets:
        sys.exit("no usable sets found")

    counts = {}
    for e, _, _ in sets:
        counts[e] = counts.get(e, 0) + 1
    rng = np.random.default_rng(7)
    added = {"user": 0, "user-holdout": 0}
    for exercise in sorted(counts):
        n = counts[exercise]
        if exercise not in known and n < args.min_sets:
            print(f"{exercise}: only {n} set(s) – needs {args.min_sets} to become a new class, skipped")
            continue
        mine = [s for s in sets if s[0] == exercise]
        order = rng.permutation(len(mine))
        n_hold = int(round(args.holdout * len(mine))) if len(mine) >= 3 else 0
        for rank, k in enumerate(order):
            _, set_id, arr = mine[k]
            group = "user-holdout" if rank < n_hold else "user"
            copies = 1 if group == "user-holdout" else args.weight
            for _ in range(copies):
                x.append(arr)
                y.append(exercise)
                subject.append(group)
                source.append("user")
            added[group] += 1
        status = "new class" if exercise not in known else "known"
        print(f"{exercise}: {n} sets ({status}), {n_hold} held out")

    print(f"added {added['user']} sets for training (x{args.weight}) and {added['user-holdout']} for evaluation")
    out = np.empty(len(x), dtype=object)
    for i, arr in enumerate(x):
        out[i] = arr
    np.savez_compressed(args.out, x=out, y=np.array(y), subject=np.array(subject), source=np.array(source))
    print(f"wrote {args.out}: {len(x)} recordings, classes: {sorted(set(y))}")


if __name__ == "__main__":
    main()
