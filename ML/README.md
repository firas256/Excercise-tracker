# Exercise recognition model

The watch app ships `WatchApp/ML/ExerciseActivityClassifier.mlpackage`, a small neural network that
recognises exercises from wrist motion. It is blended with the app's personal classifier, which
learns from every set you confirm or correct.

## What it is

| | |
|---|---|
| Architecture | 1-D CNN, 5 conv layers + global pooling, ~84k parameters (Core ML ML Program) |
| Input | 9 arm-frame channels × 128 samples (5.12 s at 25 Hz): gravity direction, user acceleration (g), rotation rate (rad/s) along forearm / palm / radial axes |
| Output | Probabilities for 20 exercises + `other` (walking, cardio, stretching, fidgeting…) |
| Training data | [RecoFit](https://github.com/microsoft/Exercise-Recognition-from-Wearable-Sensors) (Microsoft Research): 94 people, forearm-worn accelerometer + gyroscope, 50 Hz |
| Licence of the data | CDLA-Permissive-2.0 – trained models are "Results" with no restrictions |

Exercises it knows: bicep curl, shoulder press, lateral raise, bench press, bent-over row, squat,
goblet squat, lunge, overhead triceps extension, skull crusher, kettlebell swing, lat pulldown,
push-up, dip, triceps kickback, reverse fly, sit-up/crunch, Russian twist, burpee, jumping jacks.
Other exercises in the app are recognised by the personal classifier only.

**Evaluation** on people the model never saw during training (18 of 94): **88 %** of exercise sets
correct, 92 % of non-exercise recordings rejected as `other`. 100 %: burpee, dip, jumping jacks,
kettlebell swing, overhead triceps extension, Russian twist, sit-up, triceps kickback; 86–94 %: bicep
curl, shoulder press, lunge, goblet squat, lat pulldown, squat; weakest: bent-over row (47 %), lateral
raise (57 %, confused with reverse fly), bench press (75 %, confused with shoulder press), push-up (77 %).
Those pairs move the wrist almost identically. Real accuracy on *your* watch is unknown until you try it; the personal classifier
takes over more as you confirm sets.

## How the data was made to look like the watch

RecoFit used a different sensor in a different position, so the recordings are converted into the
same calibrated **arm frame** the app uses (`ML/training/prepare_recofit.py`):

1. Gravity is tracked with a gyro-propagated complementary filter (like CoreMotion's sensor fusion);
   user acceleration = measurement − gravity.
2. Forearm axis = gravity direction while walking with arms hanging.
3. Roll around the forearm is anchored on two grip-robust cues: lateral raises rotate about the thumb
   axis, and in triceps kickbacks gravity points to the thumb side at full extension (they agree within
   10°). An earlier version used curls as the anchor, but RecoFit's curls are mostly hammer-style, which
   put the frame 90° off – caught by running the model on the app's own simulated sets.
4. Signals are decimated to 25 Hz; the app does the same on the watch.

Training (`ML/training/train_model.py`) adds augmentation for what differs between people and
devices: left/right arm (mirror), how the strap sits (±45° roll, occasional quarter turns for grip),
tempo (0.6–1.4× with physically consistent scaling), wrist vs. forearm placement (up to 2× acceleration),
and sensor noise.

## Rebuild the model

```bash
pip install torch coremltools numpy scipy
```

```bash
curl -L -o singleonly.mat https://media.githubusercontent.com/media/microsoft/Exercise-Recognition-from-Wearable-Sensors/main/exercise_data.50.0000_singleonly.mat
```

```bash
python ML/training/prepare_recofit.py singleonly.mat recofit_armframe.npz
```

```bash
python ML/training/train_model.py recofit_armframe.npz out --epochs 30
```

Then copy `out/ExerciseActivityClassifier.mlpackage` into `WatchApp/ML/`. Training takes about
30 minutes on a laptop CPU.

## Use your own recordings

The watch can save each confirmed set's motion (watch Settings › Save sensor data); the iPhone app
exports them (Settings › Export my recordings) as `TrainingData/<exercise>/<set>.csv` in the same
calibrated arm frame.

- **See how the model does on your sets:** `python ML/training/evaluate_csv.py out TrainingData/`
- **Retrain with them** (they're repeated `--weight` times; ~30 % are held back and reported
  separately, so you see accuracy on sets of yours the model never saw; exercises the shipped model
  doesn't know become new classes once there are `--min-sets` sets of them):

```bash
python ML/training/add_user_data.py recofit_armframe.npz RepCoach-TrainingData.zip merged.npz
```

```bash
python ML/training/train_model.py merged.npz out --also-test user-holdout
```

  Ship the result only if *both* the RecoFit held-out people and your held-out sets do at least as
  well as the current model, then regenerate the CI fixtures:
  `python ML/training/make_fixtures.py out ML/training/fixtures` and copy
  `out/ExerciseActivityClassifier.mlpackage` to `WatchApp/ML/`.

Labels in your export are whatever was confirmed after each set, so a set saved with a wrong guess
carries a wrong label. Check unusual ones (e.g. with `evaluate_csv.py`) before training, and prefer
10+ sets per exercise from several days – a handful of sets mostly teaches the model one session's
quirks.

## Experiments that weren't shipped

**Grip-aware curls (November 2026).** RecoFit labels every curl "bicep curl", but measured in the arm
frame 69 of its 101 curl recordings are thumb-up (hammer curls) and only ~10 clearly palm-up.
`relabel_curls.py` splits them by measured grip (and turns hammer curls into palm-up ones by rotating
90° about the forearm), and `train_model.py --grip-aware` keeps the grip through augmentation.
Held-out RecoFit people: same overall accuracy (87.6 % vs 87.9 % of exercise sets), hammer curls 15/15.
But on real sets from a user whose palm-up reads ~127° (forearms rarely turn the full 180°), it
called one of two curls a lateral raise, where the shipped grip-blind model got both right. Grip is
therefore judged in the app (`GripModel`), against each user's *own* calibrated palm-up range, and the
model stays grip-tolerant. Revisit with more real recordings from people with different forearm ranges.

## Credits

D. Morris, T. S. Saponas, A. Guillory, I. Kelner. *RecoFit: Using a Wearable Sensor to Find, Recognize,
and Count Repetitive Exercises.* CHI 2014. Data: Microsoft Research, CDLA-Permissive-2.0.
