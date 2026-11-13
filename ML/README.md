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

**Evaluation** (people the model never saw during training, 18 of 94): about 86–88 % of exercise sets
correct and ~95 % of non-exercise recordings rejected as `other`. Weakest pairs: bench press vs.
shoulder press, squat vs. goblet squat, lateral raise vs. reverse fly – they move the wrist almost
identically. Real accuracy on *your* watch is unknown until you try it; the personal classifier
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

The watch can save each confirmed set's motion (Settings › Save sensor data); the iPhone app exports
them (Settings › Prepare export for Create ML) as `TrainingData/<exercise>/<set>.csv` in the same arm
frame. Two options:

- **See how the model does on your sets:** `python ML/training/evaluate_csv.py out TrainingData/`
- **Train your own model in Create ML:** Xcode › Open Developer Tool › Create ML › Activity Classifier,
  choose the `TrainingData` folder, select the nine `gravity_*`, `accel_*`, `rotation_*` columns,
  prediction window 100. Save it as `ExerciseActivityClassifier.mlmodel`, replace the shipped model in
  the Watch App target. The app reads input names and window size from the model; for a model trained at
  50 Hz there is nothing else to change.

## Credits

D. Morris, T. S. Saponas, A. Guillory, I. Kelner. *RecoFit: Using a Wearable Sensor to Find, Recognize,
and Count Repetitive Exercises.* CHI 2014. Data: Microsoft Research, CDLA-Permissive-2.0.
