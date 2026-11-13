#!/usr/bin/env python3
"""Converts the Microsoft RecoFit dataset into Rep Coach's calibrated *arm frame*.

Dataset: Morris, Saponas, Guillory & Kelner, "RecoFit: Using a Wearable Sensor to Find, Recognize,
and Count Repetitive Exercises", CHI 2014. https://github.com/microsoft/Exercise-Recognition-from-Wearable-Sensors
Licence: CDLA-Permissive-2.0 (trained models are "Results" and carry no restrictions).

Usage:
    python prepare_recofit.py exercise_data.50.0000_singleonly.mat recofit_armframe.npz

What it does (mirrors what the watch app does live):
  1. Gravity is tracked with a gyro-propagated complementary filter (like CoreMotion's sensor fusion),
     user acceleration = measured acceleration minus gravity, rotation in rad/s.
  2. The arm frame is learned from the data, like the app's calibration:
       forearm axis = gravity direction while walking (arms hanging),
       radial axis  = rotation axis of bicep curls (elbow flexion with a supinated grip),
       palm axis    = forearm x radial, signed so the palm faces up mid-curl.
  3. Signals are decimated to 25 Hz and stored per recording with the mapped exercise label.
The accelerometer sign convention cannot be recovered from data alone, but a global sign flip is
exactly a left/right-arm mirror image, which training removes with mirror augmentation.
"""
import math
import sys

import numpy as np
import scipy.io

SOURCE_RATE = 50
TARGET_RATE = 25

# RecoFit activity name -> Rep Coach ExerciseType raw value ("other" = not an exercise we track).
LABELS = {
    "Bicep Curl": "bicepCurl",
    "Two-arm Dumbbell Curl (both arms, not alternating)": "bicepCurl",
    "Alternating Dumbbell Curl": "bicepCurl",
    "Biceps Curl (band)": "bicepCurl",
    "Shoulder Press (dumbbell)": "shoulderPress",
    "Squat Rack Shoulder Press": "shoulderPress",
    "Lateral Raise": "lateralRaise",
    "Chest Press (rack)": "benchPress",
    "Dumbbell Row (knee on bench) (right arm)": "bentOverRow",
    "Dumbbell Row (knee on bench) (label spans both arms)": "bentOverRow",
    "Lawnmower (right arm)": "bentOverRow",
    "Squat": "squat",
    "Squat (hands behind head)": "squat",
    "Squat (arms in front of body, parallel to ground)": "squat",
    "Dumbbell Squat (hands at side)": "squat",
    "Squat (kettlebell / goblet)": "gobletSquat",
    "Lunge (alternating both legs, weight optional)": "lunge",
    "Walking lunge": "lunge",
    "Overhead Triceps Extension": "overheadTricepsExtension",
    "Overhead Triceps Extension (label spans both arms)": "overheadTricepsExtension",
    "Triceps extension (lying down)": "skullCrusher",
    "Triceps extension (lying down) (right arm)": "skullCrusher",
    "Kettlebell Swing": "kettlebellSwing",
    "Band Pull-Down Row": "latPulldown",
    "Pushups": "pushUp",
    "Pushup (knee or foot variation)": "pushUp",
    "Dip": "dip",
    "Triceps Kickback (knee on bench) (right arm)": "tricepsKickback",
    "Triceps Kickback (knee on bench) (label spans both arms)": "tricepsKickback",
    "Seated Back Fly": "reverseFly",
    "Sit-ups": "sitUp",
    "Sit-up (hands positioned behind head)": "sitUp",
    "Butterfly Sit-up": "sitUp",
    "Crunch": "sitUp",
    "Russian Twist": "russianTwist",
    "Burpee": "burpee",
    "Jumping Jacks": "jumpingJacks",
    # Everything else that moves the arm: lets the model say "not a tracked exercise".
    "Walk": "other", "Running (treadmill)": "other", "Elliptical machine": "other",
    "Rowing machine": "other", "Jump Rope": "other", "Non-Exercise": "other",
    "Dynamic Stretch (at your own pace)": "other", "Repetitive Stretching": "other",
    "Static Stretch (at your own pace)": "other", "Static stretch": "other",
    "Fast Alternating Punches": "other", "Medicine Ball Slam": "other", "Wall Ball": "other",
    "Box Jump (on bench)": "other", "Squat Jump": "other", "V-up": "other", "Plank": "other",
    "Side Plank Left side": "other", "Side Plank Right side": "other", "Power Boat pose": "other",
    "Wall Squat": "other", "Arm Band Adjustment": "other", "Rest": "other",
    "Dumbbell Deadlift Row": "other", "Lawnmower (left arm)": "other",
    "Dumbbell Row (knee on bench) (left arm)": "other",
    "Triceps Kickback (knee on bench) (left arm)": "other",
}
MAX_NON_EXERCISE_SECONDS_PER_SUBJECT = 150


def records(sd, j):
    for i in range(sd.shape[0]):
        c = sd[i, j]
        if c is None or (isinstance(c, np.ndarray) and c.size == 0):
            continue
        for r in (c if isinstance(c, np.ndarray) else [c]):
            yield i, r


def raw_signals(r):
    a = np.asarray(r.data.accelDataMatrix, dtype=float)
    g = np.asarray(r.data.gyroDataMatrix, dtype=float)
    if a.ndim != 2 or g.ndim != 2 or len(a) < 2 * SOURCE_RATE:
        return None
    n = min(len(a), len(g))
    return a[:n, 1:4], np.radians(g[:n, 1:4])  # accel in g, gyro rad/s


def track_gravity(acc, gyro, dt=1.0 / SOURCE_RATE, gain=0.02):
    """Gravity direction (pointing down) in sensor frame. Standard IMU convention: at rest the
    accelerometer reads +1 g *up*, so the measured gravity direction is -acc."""
    n = len(acc)
    out = np.empty((n, 3))
    gx, gy, gz = -acc[0] / max(np.linalg.norm(acc[0]), 1e-6)
    for i in range(n):
        wx, wy, wz = gyro[i]
        # dg/dt = -w x g  (a world-fixed vector seen from the rotating sensor)
        cx, cy, cz = wy * gz - wz * gy, wz * gx - wx * gz, wx * gy - wy * gx
        gx, gy, gz = gx - cx * dt, gy - cy * dt, gz - cz * dt
        ax, ay, az = acc[i]
        an = math.sqrt(ax * ax + ay * ay + az * az)
        if 0.7 < an < 1.3:
            k = gain
            gx, gy, gz = (1 - k) * gx - k * ax / an, (1 - k) * gy - k * ay / an, (1 - k) * gz - k * az / an
        norm = math.sqrt(gx * gx + gy * gy + gz * gz)
        gx, gy, gz = gx / norm, gy / norm, gz / norm
        out[i] = (gx, gy, gz)
    return out


def learn_arm_frame(sd, acts):
    """Forearm axis from walking, radial axis from curl rotation, palm = forearm x radial."""
    fs = []
    for _, r in records(sd, acts.index("Walk")):
        sig = raw_signals(r)
        if sig is None:
            continue
        g = track_gravity(*sig)
        m = g.mean(0)
        fs.append(m / np.linalg.norm(m))
    forearm = np.mean(fs, 0)
    forearm /= np.linalg.norm(forearm)

    cov = np.zeros((3, 3))
    palm_votes = []
    for name in ["Bicep Curl", "Two-arm Dumbbell Curl (both arms, not alternating)"]:
        for _, r in records(sd, acts.index(name)):
            sig = raw_signals(r)
            if sig is None:
                continue
            acc, gyro = sig
            w = gyro - np.outer(gyro @ forearm, forearm)
            cov += w.T @ w
            g = track_gravity(acc, gyro)
            horizontal = np.abs(g @ forearm) < 0.3
            if horizontal.sum() > 20:
                gp = g[horizontal] - np.outer(g[horizontal] @ forearm, forearm)
                palm_votes.append(-gp.mean(0))  # palm faces up mid-curl -> gravity leaves the back of the hand
    _, vecs = np.linalg.eigh(cov)
    radial = vecs[:, -1]
    radial -= (radial @ forearm) * forearm
    radial /= np.linalg.norm(radial)
    palm = np.cross(radial, forearm)  # so that forearm x palm = radial
    if np.mean(palm_votes, 0) @ palm < 0:
        palm, radial = -palm, -radial
    return forearm, palm, np.cross(forearm, palm)


def decimate(x, factor):
    n = (len(x) // factor) * factor
    return x[:n].reshape(-1, factor, x.shape[1]).mean(1)


def main(src, dst):
    m = scipy.io.loadmat(src, squeeze_me=True, struct_as_record=False)
    acts = list(m["exerciseConstants"].activities)
    sd = m["subject_data"]
    assert int(m["Fs"]) == SOURCE_RATE
    forearm, palm, radial = learn_arm_frame(sd, acts)
    print("arm frame (sensor coords): forearm", forearm.round(3), "palm", palm.round(3), "radial", radial.round(3))
    R = np.stack([forearm, palm, radial])  # rows: arm-frame axes

    rng = np.random.default_rng(0)
    out_x, out_y, out_s, out_src = [], [], [], []
    non_ex_used = {}
    factor = SOURCE_RATE // TARGET_RATE
    trim = SOURCE_RATE  # drop 1 s at both ends (getting into position)
    for j, name in enumerate(acts):
        label = LABELS.get(name)
        if label is None:
            continue
        for subject, r in records(sd, j):
            sig = raw_signals(r)
            if sig is None:
                continue
            acc, gyro = sig
            if name == "Non-Exercise":
                used = non_ex_used.get(subject, 0.0)
                if used > MAX_NON_EXERCISE_SECONDS_PER_SUBJECT or rng.random() < 0.5:
                    continue
                non_ex_used[subject] = used + len(acc) / SOURCE_RATE
            g = track_gravity(acc, gyro)
            user = acc + g  # physical linear acceleration in g (acc = a - g_vec)
            arm = np.concatenate([g @ R.T, user @ R.T, gyro @ R.T], axis=1)[trim:-trim]
            if len(arm) < 3 * SOURCE_RATE:
                continue
            arm = decimate(arm, factor)
            arm[:, 0:3] /= np.linalg.norm(arm[:, 0:3], axis=1, keepdims=True)
            out_x.append(arm.astype(np.float32))
            out_y.append(label)
            out_s.append(int(subject))
            out_src.append(name)
    x = np.empty(len(out_x), dtype=object)
    x[:] = out_x
    np.savez_compressed(dst, x=x, y=np.array(out_y), subject=np.array(out_s), source=np.array(out_src),
                        rate=TARGET_RATE, frame=R)
    labels, counts = np.unique(out_y, return_counts=True)
    secs = {l: sum(len(a) for a, yy in zip(out_x, out_y) if yy == l) / TARGET_RATE for l in labels}
    for l, c in zip(labels, counts):
        print(f"{l:26s} recordings={c:4d} minutes={secs[l] / 60:6.1f}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
