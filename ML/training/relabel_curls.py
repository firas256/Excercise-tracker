#!/usr/bin/env python3
"""Splits RecoFit's "bicep curl" recordings into palm-up curls and hammer curls by measured grip.

RecoFit labels every curl "bicep curl", but measured in the calibrated arm frame most of them
(about 69 of 101) are done thumb-up – hammer curls – and only ~10 clearly palm-up. Trained on that,
the model called hammer-style movements (including rope pushdowns) "bicep curl".

Grip = the forearm's roll while it is roughly horizontal (0° palm down … 90° thumb up … 180° palm up):
  - roll >= 125°  -> bicepCurl
  - roll <  110°  -> hammerCurl
  - in between    -> dropped (ambiguous)
To balance the classes, every hammer curl is also turned into a palm-up curl by rotating its arm-frame
signals 90° about the forearm axis towards palm-up – turning the palm up *is* a rotation of the watch
about the forearm, so this is the same movement with a supinated grip. Synthesised recordings keep their
person's subject id, so held-out people stay unseen.

Usage: python relabel_curls.py recofit_armframe.npz recofit_grips.npz
"""
import sys

import numpy as np

SUPINATED_MIN, NEUTRAL_MAX = 125.0, 110.0


def grip_roll(arr):
    """(|roll| in degrees, signed direction of the thumb side) while the forearm is near horizontal."""
    g = arr[:, 0:3]
    horiz = np.abs(g[:, 0]) < 0.7
    if horiz.sum() < 20:
        return None, 0.0
    gy, gz = g[horiz, 1], g[horiz, 2]
    r = np.sqrt(gy ** 2 + gz ** 2) + 1e-9
    c, s = np.mean(gy / r), np.mean(gz / r)
    return float(np.degrees(np.arctan2(abs(s), c))), (1.0 if s >= 0 else -1.0)


def rotate_roll(arr, degrees):
    """Rotates gravity, acceleration and rotation rate about the forearm (x) axis."""
    t = np.radians(degrees)
    c, s = np.cos(t), np.sin(t)
    out = arr.copy()
    for k in (0, 3, 6):  # gravity, acceleration, rotation rate: (forearm, palm, radial)
        y, z = arr[:, k + 1], arr[:, k + 2]
        out[:, k + 1] = y * c - z * s
        out[:, k + 2] = y * s + z * c
    return out


def main():
    src, dst = sys.argv[1], sys.argv[2]
    d = np.load(src, allow_pickle=True)
    x, y, subject = list(d["x"]), list(d["y"]), list(d["subject"])
    source = list(d["source"]) if "source" in d else ["recofit"] * len(x)
    out_x, out_y, out_s, out_src = [], [], [], []
    tally = {"bicepCurl": 0, "hammerCurl": 0, "dropped": 0, "synthesised palm-up": 0}
    for arr, label, subj, src_name in zip(x, y, subject, source):
        if label != "bicepCurl":
            out_x.append(arr); out_y.append(label); out_s.append(subj); out_src.append(src_name)
            continue
        roll, side = grip_roll(arr)
        if roll is None or NEUTRAL_MAX <= roll < SUPINATED_MIN:
            tally["dropped"] += 1
            continue
        if roll >= SUPINATED_MIN:
            out_x.append(arr); out_y.append("bicepCurl"); out_s.append(subj); out_src.append(src_name)
            tally["bicepCurl"] += 1
            continue
        out_x.append(arr); out_y.append("hammerCurl"); out_s.append(subj); out_src.append(src_name)
        tally["hammerCurl"] += 1
        # Same curl, palm turned up: rotate by the remaining way to 180° on the thumb side.
        out_x.append(rotate_roll(arr, side * (180.0 - roll)))
        out_y.append("bicepCurl"); out_s.append(subj); out_src.append(src_name + "+supinated")
        tally["synthesised palm-up"] += 1
    xs = np.empty(len(out_x), dtype=object)
    for i, a in enumerate(out_x):
        xs[i] = a.astype(np.float32)
    np.savez_compressed(dst, x=xs, y=np.array(out_y), subject=np.array(out_s), source=np.array(out_src))
    print(tally)
    # Check: the synthesised curls now read palm-up.
    rolls = [grip_roll(a)[0] for a, l, s in zip(out_x, out_y, out_src) if l == "bicepCurl" and s.endswith("+supinated")]
    print(f"synthesised palm-up curls: median roll {np.median(rolls):.0f}°")


if __name__ == "__main__":
    main()
