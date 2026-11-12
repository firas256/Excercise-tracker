# Training your own Core ML exercise model (optional)

Rep Coach works without this – the built-in classifier recognises exercises from biomechanical
prototypes and personalises itself every time you confirm or correct a set. Train a Core ML model only
if you want a fully data-driven classifier on top.

## 1. Collect data (no extra effort)

On the watch, **Settings › Save sensor data** is on by default. Every set you **save** in the set summary
sends its motion recording to the iPhone, labelled with the exercise you confirmed. Just train normally
and correct the exercise name whenever the guess is wrong – the label follows your correction (also if
you change it later in the iPhone History).

Aim for **5–10 sets per exercise**, ideally from a few different sessions.

## 2. Export

iPhone app › **Settings › Prepare export for Create ML** › share the `.zip` to your Mac (AirDrop, Files…).

Unzipped it looks like this – the layout Create ML's Activity Classifier expects:

```
TrainingData/
  bicepCurl/
    6F1C…csv
    9A0B…csv
  lateralRaise/
    …
```

Each CSV is one set at 50 Hz in the calibrated **arm frame** (independent of wrist/crown orientation):

| column | meaning |
|---|---|
| `timestamp` | seconds from the start of the set |
| `gravity_forearm`, `gravity_palm`, `gravity_radial` | unit gravity direction along forearm / out of palm / thumb side |
| `accel_forearm`, `accel_palm`, `accel_radial` | user acceleration (g) |
| `rotation_forearm`, `rotation_palm`, `rotation_radial` | angular velocity (rad/s) |

Folder names are the app's exercise identifiers (e.g. `bicepCurl`, `latPulldown`), which the watch maps
back to exercises when it reads the model's predictions.

## 3. Train in Create ML

1. Xcode › Open Developer Tool › **Create ML** › New Document › **Activity Classifier**.
2. **Training Data**: select the `TrainingData` folder.
3. **Features**: select all nine `gravity_*`, `accel_*`, `rotation_*` columns (not `timestamp`).
4. **Prediction Window Size**: `100` (2 seconds).
5. Train. Check the validation accuracy; add more sets for exercises it confuses.
6. **Output** › save the model as `ExerciseActivityClassifier.mlmodel`.

## 4. Add it to the watch app

Drag `ExerciseActivityClassifier.mlmodel` into Xcode, tick **ExerciseTracker Watch App** under
*Target Membership*, build and run. `CoreMLExerciseClassifier` finds it by name, reads the input names and
window size from the model, and `BlendedExerciseClassifier` mixes it (60 %) with the built-in classifier
(40 %). If the model is missing, nothing changes.

## Public datasets (advanced)

If you want to pre-train on other people's data, research datasets of wrist/forearm IMU gym exercises
exist (e.g. Microsoft Research's RecoFit data from *Morris et al., CHI 2014*). Their sensors, sampling
rates and axes differ from the Apple Watch, so you would need to resample to 50 Hz and rotate into the
arm frame above before training – and check each dataset's licence first.
