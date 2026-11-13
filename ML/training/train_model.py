#!/usr/bin/env python3
"""Trains Rep Coach's exercise classifier on arm-frame data and exports it to Core ML.

Usage:
    python train_model.py recofit_armframe.npz OUTPUT_DIR [--epochs 30] [--eval-only-split]

Outputs in OUTPUT_DIR:
    ExerciseActivityClassifier.mlpackage   (drop into the "ExerciseTracker Watch App" target)
    report.txt                             (held-out-subject evaluation)

Model input: nine 1-D arrays named like the app's TrainingCSV columns (gravity_*, accel_*,
rotation_*), each WINDOW samples at 25 Hz in the calibrated arm frame. Output: class probabilities
whose labels are ExerciseType raw values (plus "other", which the app ignores).
"""
import argparse
import json
import math
import os

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

RATE = 25
WINDOW = 128          # 5.12 s
TRAIN_HOP = 12
EVAL_HOP = 32
COLUMNS = ["gravity_forearm", "gravity_palm", "gravity_radial",
           "accel_forearm", "accel_palm", "accel_radial",
           "rotation_forearm", "rotation_palm", "rotation_radial"]
MAX_OTHER_WINDOWS_PER_RECORDING = 40

torch.set_num_threads(max(1, os.cpu_count() or 1))


class ExerciseNet(nn.Module):
    def __init__(self, n_classes):
        super().__init__()
        # Fixed input scaling so the app can feed raw values (unit gravity, g, rad/s).
        self.register_buffer("scale", torch.tensor([1, 1, 1, 2, 2, 2, 0.5, 0.5, 0.5], dtype=torch.float32).view(1, 9, 1))

        def block(cin, cout, k, stride):
            return nn.Sequential(nn.Conv1d(cin, cout, k, stride=stride, padding=k // 2), nn.BatchNorm1d(cout), nn.ReLU())

        self.features = nn.Sequential(
            block(9, 32, 7, 1), block(32, 48, 5, 2), block(48, 64, 5, 2),
            block(64, 96, 3, 2), block(96, 128, 3, 1),
        )
        self.dropout = nn.Dropout(0.3)
        self.head = nn.Linear(128, n_classes)

    def forward(self, x):  # x: (B, 9, WINDOW)
        h = self.features(x * self.scale)
        h = h.mean(dim=2)
        return self.head(self.dropout(h))


def windows(arr, hop):
    out = []
    for s in range(0, len(arr) - WINDOW + 1, hop):
        out.append(arr[s:s + WINDOW])
    return out


def build(x, y, subjects, chosen, classes, hop, rng, cap_other=True):
    """Returns (segments for time-warp augmentation, labels). Segments are 1.3x longer when possible."""
    X, Y, REC = [], [], []
    cidx = {c: i for i, c in enumerate(classes)}
    for k, (arr, label, subj) in enumerate(zip(x, y, subjects)):
        if subj not in chosen or len(arr) < WINDOW:
            continue
        ws = windows(arr, hop)
        if label == "other" and cap_other and len(ws) > MAX_OTHER_WINDOWS_PER_RECORDING:
            ws = [ws[i] for i in rng.choice(len(ws), MAX_OTHER_WINDOWS_PER_RECORDING, replace=False)]
        X.extend(ws)
        Y.extend([cidx[label]] * len(ws))
        REC.extend([k] * len(ws))
    return np.stack(X).astype(np.float32), np.array(Y), np.array(REC)


def augment(batch, rng):
    """batch: (B, WINDOW, 9) numpy. Mirror, strap rotation, tilt, tempo and amplitude changes, noise."""
    B = len(batch)
    # Tempo: resample each window by a random factor (0.6x .. 1.4x speed), keeping its length.
    s = np.exp(rng.uniform(math.log(0.6), math.log(1.4), (B, 1)))
    src = np.clip((np.arange(WINDOW)[None, :] - WINDOW / 2) * s + WINDOW / 2, 0, WINDOW - 1)
    lo = np.floor(src).astype(int)
    hi = np.minimum(lo + 1, WINDOW - 1)
    f = (src - lo)[..., None]
    b = (np.take_along_axis(batch, lo[..., None], axis=1) * (1 - f)
         + np.take_along_axis(batch, hi[..., None], axis=1) * f)
    g, a, w = b[..., 0:3].copy(), b[..., 3:6].copy(), b[..., 6:9].copy()
    # Left/right arm mirror (also absorbs the unknown accelerometer sign of the source sensor).
    m = rng.random(B) < 0.5
    g[m, :, 2] *= -1
    a[m, :, 2] *= -1
    w[m, :, 0] *= -1
    w[m, :, 1] *= -1
    # Strap rotation about the forearm (palm/radial plane) and a small tilt of the forearm axis.
    # +-45 deg covers how the strap sits; an occasional quarter turn covers grip differences
    # (e.g. hammer vs palm-up curls), since RecoFit participants mostly used one grip per exercise.
    quarter = rng.choice([-90.0, 0.0, 0.0, 0.0, 90.0], B)
    th = np.radians(rng.uniform(-45, 45, B) + quarter)
    ph = np.radians(rng.uniform(-10, 10, B))
    c, s_, c2, s2 = np.cos(th), np.sin(th), np.cos(ph), np.sin(ph)
    one, zero = np.ones(B), np.zeros(B)
    rot = np.stack([np.stack([one, zero, zero], 1), np.stack([zero, c, -s_], 1), np.stack([zero, s_, c], 1)], 1)
    tilt = np.stack([np.stack([c2, zero, -s2], 1), np.stack([zero, one, zero], 1), np.stack([s2, zero, c2], 1)], 1)
    M = np.transpose(tilt @ rot, (0, 2, 1))
    g = np.einsum("btk,bkj->btj", g, M)
    a = np.einsum("btk,bkj->btj", a, M)
    w = np.einsum("btk,bkj->btj", w, M)
    # Physically consistent tempo change: angular rate scales with speed, acceleration with speed^2.
    a *= (s ** 2)[:, :, None]
    w *= s[:, :, None]
    # The watch sits at the wrist (RecoFit's band sat mid-forearm), so allow up to ~2x acceleration.
    a *= np.exp(rng.uniform(math.log(0.7), math.log(2.0), (B, 1, 1)))
    w *= rng.uniform(0.8, 1.25, (B, 1, 1))
    a += rng.normal(0, 0.02, a.shape)
    w += rng.normal(0, 0.03, w.shape)
    g /= np.linalg.norm(g, axis=2, keepdims=True)
    return np.concatenate([g, a, w], axis=2).astype(np.float32)


def train(model, Xtr, Ytr, classes, epochs, rng, log):
    counts = np.bincount(Ytr, minlength=len(classes)).astype(float)
    weights = torch.tensor((counts.max() / np.maximum(counts, 1)) ** 0.5, dtype=torch.float32)
    opt = torch.optim.AdamW(model.parameters(), lr=2e-3, weight_decay=1e-3)
    steps = epochs * math.ceil(len(Xtr) / 256)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=3e-3, total_steps=steps)
    for epoch in range(epochs):
        model.train()
        order = rng.permutation(len(Xtr))
        total, correct, loss_sum = 0, 0, 0.0
        for s in range(0, len(order), 256):
            idx = order[s:s + 256]
            xb = torch.from_numpy(augment(Xtr[idx], rng)).permute(0, 2, 1)
            yb = torch.from_numpy(Ytr[idx])
            logits = model(xb)
            loss = F.cross_entropy(logits, yb, weight=weights, label_smoothing=0.05)
            opt.zero_grad()
            loss.backward()
            opt.step()
            sched.step()
            loss_sum += loss.item() * len(idx)
            correct += (logits.argmax(1) == yb).sum().item()
            total += len(idx)
        log(f"epoch {epoch + 1:2d}/{epochs} loss {loss_sum / total:.3f} train-acc {correct / total:.3f}")


def predict(model, X):
    model.eval()
    out = []
    with torch.no_grad():
        for s in range(0, len(X), 512):
            out.append(F.softmax(model(torch.from_numpy(X[s:s + 512]).permute(0, 2, 1)), dim=1).numpy())
    return np.concatenate(out)


def evaluate(model, X, Y, REC, classes, log):
    P = predict(model, X)
    win_acc = (P.argmax(1) == Y).mean()
    # Set-level: average window probabilities per recording (what the app does per set).
    recs = np.unique(REC)
    rec_true, rec_pred = [], []
    for r in recs:
        sel = REC == r
        rec_true.append(Y[sel][0])
        rec_pred.append(P[sel].mean(0).argmax())
    rec_true, rec_pred = np.array(rec_true), np.array(rec_pred)
    ex = rec_true != classes.index("other")
    log(f"window accuracy {win_acc:.3f} | set accuracy {np.mean(rec_true == rec_pred):.3f} "
        f"| set accuracy (exercises only) {np.mean(rec_true[ex] == rec_pred[ex]):.3f}")
    log(f"{'class':26s} {'sets':>5s} {'correct':>8s}  most common confusion")
    for ci, c in enumerate(classes):
        sel = rec_true == ci
        if sel.sum() == 0:
            continue
        wrong = rec_pred[sel][rec_pred[sel] != ci]
        conf = ""
        if len(wrong):
            vals, cnt = np.unique(wrong, return_counts=True)
            conf = f"{classes[vals[cnt.argmax()]]} ({cnt.max()})"
        log(f"{c:26s} {sel.sum():5d} {np.mean(rec_pred[sel] == ci):8.2f}  {conf}")
    return np.mean(rec_true[ex] == rec_pred[ex])


class CoreMLWrapper(nn.Module):
    """Nine named 1-D inputs (Create ML style) -> class probabilities."""

    def __init__(self, net):
        super().__init__()
        self.net = net

    def forward(self, gf, gp, gr, af, ap, ar, rf, rp, rr):
        x = torch.stack([gf, gp, gr, af, ap, ar, rf, rp, rr], dim=0).unsqueeze(0)
        return F.softmax(self.net(x), dim=1).squeeze(0)


def export(model, classes, path, report_summary):
    import coremltools as ct
    model.eval()
    wrapper = CoreMLWrapper(model).eval()
    example = tuple(torch.zeros(WINDOW) for _ in COLUMNS)
    traced = torch.jit.trace(wrapper, example)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name=c, shape=(WINDOW,)) for c in COLUMNS],
        classifier_config=ct.ClassifierConfig(classes),
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.watchOS9,
    )
    mlmodel.short_description = ("Recognises gym exercises from 5 s of calibrated arm-frame motion (25 Hz). "
                                 "Trained on the Microsoft Research RecoFit dataset.")
    mlmodel.author = "Rep Coach (trained on RecoFit: Morris et al., CHI 2014, CDLA-Permissive-2.0)"
    mlmodel.license = "Model trained on RecoFit data (CDLA-Permissive-2.0)."
    mlmodel.user_defined_metadata["sample_rate"] = str(RATE)
    mlmodel.user_defined_metadata["window"] = str(WINDOW)
    mlmodel.user_defined_metadata["frame"] = "arm (forearm, palm, radial); gravity unit vector, user acceleration in g, rotation in rad/s"
    mlmodel.user_defined_metadata["evaluation"] = report_summary
    mlmodel.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("data")
    ap.add_argument("out")
    ap.add_argument("--epochs", type=int, default=30)
    ap.add_argument("--skip-final", action="store_true", help="only run the held-out evaluation")
    ap.add_argument("--final-only", action="store_true", help="skip the held-out evaluation")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    report = open(os.path.join(args.out, "report.txt"), "w")

    def log(msg):
        print(msg, flush=True)
        report.write(msg + "\n")

    d = np.load(args.data, allow_pickle=True)
    x, y, subjects = d["x"], d["y"], d["subject"]
    classes = sorted(set(y.tolist()) - {"other"}) + ["other"]
    rng = np.random.default_rng(42)
    torch.manual_seed(42)
    all_subjects = np.unique(subjects)
    test_subjects = set(rng.choice(all_subjects, size=max(1, len(all_subjects) // 5), replace=False).tolist())
    train_subjects = set(all_subjects.tolist()) - test_subjects
    log(f"classes ({len(classes)}): {classes}")
    log(f"subjects: {len(train_subjects)} train, {len(test_subjects)} held out")

    summary = "see ML/README.md for held-out-subject evaluation"
    if not args.final_only:
        Xtr, Ytr, _ = build(x, y, subjects, train_subjects, classes, TRAIN_HOP, rng)
        Xte, Yte, Rte = build(x, y, subjects, test_subjects, classes, EVAL_HOP, rng, cap_other=False)
        log(f"windows: {len(Xtr)} train, {len(Xte)} test")
        model = ExerciseNet(len(classes))
        log(f"parameters: {sum(p.numel() for p in model.parameters())}")
        train(model, Xtr, Ytr, classes, args.epochs, rng, log)
        log("\nHeld-out subjects (never seen in training):")
        acc = evaluate(model, Xte, Yte, Rte, classes, log)
        summary = f"held-out-subject set accuracy on exercises: {acc:.2f}"
    if args.skip_final:
        return

    log("\nFinal model: training on all subjects")
    Xall, Yall, _ = build(x, y, subjects, set(all_subjects.tolist()), classes, TRAIN_HOP, rng)
    final = ExerciseNet(len(classes))
    train(final, Xall, Yall, classes, args.epochs, rng, log)
    torch.save(final.state_dict(), os.path.join(args.out, "model.pt"))
    with open(os.path.join(args.out, "classes.json"), "w") as f:
        json.dump(classes, f)
    export(final, classes, os.path.join(args.out, "ExerciseActivityClassifier.mlpackage"), summary)
    log("exported ExerciseActivityClassifier.mlpackage")


if __name__ == "__main__":
    main()
