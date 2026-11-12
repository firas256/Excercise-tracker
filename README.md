# Rep Coach – Apple Watch exercise tracker

An Apple Watch + iPhone app that uses the watch's **accelerometer and gyroscope** to

- **guide a calibration** (5 held poses, with haptic feedback at every step),
- **count reps** live (a tap on every rep),
- **guess the exercise** (free weights *and* machines) and learn from your corrections,
- **give feedback** on range of motion, tempo (lifting vs. lowering), consistency, swinging and fatigue,
- save everything to the iPhone (history, per-rep charts) and to Apple Health.

Everything runs on-device. No account, no server.

---

## 1. What you need

| | |
|---|---|
| Mac | Xcode **15 or newer** (Xcode 16/26 recommended) |
| iPhone | iOS **17+**, paired with the watch |
| Apple Watch | watchOS **10+** (Series 6 or newer recommended) |
| Apple ID | A free Apple ID works for testing on your own devices (apps expire after 7 days). A paid developer account removes that limit. |

## 2. Download and open in Xcode

```bash
git clone -b claude/quirky-mendel-t2w39x https://github.com/firas256/Excercise-tracker.git
```

```bash
cd Excercise-tracker
```

```bash
open ExerciseTracker.xcodeproj
```

## 3. Signing (one time)

1. In Xcode, click the blue **ExerciseTracker** project in the left sidebar.
2. Select the **ExerciseTracker** target → **Signing & Capabilities** → choose your **Team** (add your Apple ID under Xcode › Settings › Accounts if needed).
3. Do the same for the **ExerciseTracker Watch App** target.
4. If Xcode says the bundle identifier is not available, open `Config/Base.xcconfig` and change `BUNDLE_ID_PREFIX = com.firas256` to something unique (e.g. `com.yourname.reps`). Both apps derive their IDs from it.

> **Free Apple ID and HealthKit:** if signing fails with a HealthKit/provisioning error, remove the
> **HealthKit** capability from *both* targets (Signing & Capabilities → click the ✕ next to HealthKit).
> The app keeps working: it switches to an extended-runtime session to keep the sensors on, it just
> won't record heart rate or save to the Health app.

## 4. Run it on your devices

1. Turn on **Developer Mode** on the iPhone (Settings › Privacy & Security) and on the watch (Settings › Privacy & Security on the watch). Restart when asked.
2. Connect the iPhone with a cable (the watch must be paired and unlocked, near the phone).
3. Pick the **ExerciseTracker** scheme and your iPhone at the top of Xcode and press **Run ▶︎**. This installs the iPhone app and the watch app.
   - To run/debug directly on the watch, pick the **ExerciseTracker Watch App** scheme and your watch.
4. The first launch of each app asks for every permission up front (Health on the watch and the phone; motion sensors need no prompt).

Tip: the iPhone app has **Settings › Add demo workout** so you can explore the history screens (also works in the Simulator).

## 5. Using it

1. On the watch: **Start Workout**.
2. **Calibrate** – follow the five instructions (arm hanging down, forward palm-down, palm-up, out to the side, overhead). For each pose the watch waits until you move into it and become **still**, holds for ~1 s, then buzzes ✔︎ and moves on. A different buzz means the pose didn't look right – adjust and hold again. (You can turn off "calibrate every workout" in the watch settings.)
3. **Lift.** Movement starts a set automatically. The watch taps on every rep (a double tap means the rep was flagged, e.g. partial or rushed). After ~3 reps it shows its guess, e.g. *"Bicep Curl? 92%"*.
   - Swipe left to **lock an exercise** (useful for machines like the leg press where your hands don't move).
   - Swipe right for **End Set / End Workout**.
4. Rest ~5 s and the set ends. Confirm or **correct the exercise and rep count**, add the weight, read the feedback. Every confirmation teaches the classifier your form.
5. End the workout. It syncs to the iPhone (History tab: range-of-motion, tempo and speed charts per rep) and to Apple Health.

## 6. How the "AI" part works

**Is there a ready-made model?** I looked for a pre-trained, publicly available Core ML model that recognises
gym exercises from Apple Watch motion data and didn't find a usable one: existing work is research datasets/code
for other sensors, or apps without a reusable model. So the app takes a three-layer approach that works out of the box,
and you **don't need to record training data**:

1. **Built-in classifier (works immediately).** Each set is summarised by 14 orientation-independent
   features (forearm angle at start/turnaround, grip/palm direction, dominant rotation axis, vertical and
   push/pull hand travel, start-high/low, tempo…) computed in the calibrated *arm frame*. A Gaussian
   classifier compares them against biomechanical prototypes of 29 exercises.
2. **Learns from you automatically.** Whenever you confirm or correct a set, that exercise's prototype is
   updated with your data (Bayesian update), so recognition adapts to your form, your machines and your
   grip – without a separate recording session.
3. **Optional Core ML model.** The watch can save each confirmed set's sensor data; the iPhone exports it
   in the folder layout Create ML expects. Train an *Activity Classifier* in Create ML, drop
   `ExerciseActivityClassifier.mlmodel` into the watch target, and it's blended in automatically.
   See [`ML/README.md`](ML/README.md).

Honest limits: some pairs move the wrist almost identically (lateral vs. front raise, bench press vs. lat
pulldown vs. goblet squat) – the watch will often get the family right and learn the rest from your
corrections. Exercises where the hands are fixed (leg press, leg extension/curl, pull-ups, push-ups, dips)
should be picked manually; counting is best-effort.

**Rep counting.** Four candidate signals are derived (gravity-based forearm angle, gyro rotation,
vertical travel, push/pull travel). The most rhythmic one (autocorrelation) is chosen and each
there-and-back cycle is counted with hysteresis. Velocity thresholds split each rep into lifting and
lowering phases, and zero-velocity updates give accurate travel distances.

**Feedback.** Partial reps (vs. your best reps in the set), incomplete top/bottom for curls, raises and
triceps work (absolute angles from calibration), rushed lifting or lowering, swinging, inconsistent range,
and speed loss across the set (a velocity-based-training fatigue indicator).

## 7. Supported exercises

| Free weights | Machines & cables | Bodyweight |
|---|---|---|
| Bicep curl, hammer curl, shoulder press, lateral raise, front raise, upright row, shrug, bench press, dumbbell fly, bent-over row, deadlift, Romanian deadlift, barbell squat, goblet squat, lunge, overhead triceps extension, skull crusher, kettlebell swing | Lat pulldown, seated cable row, chest press machine, pec deck / cable fly, triceps pushdown, leg press*, leg extension*, leg curl* | Pull-up*, push-up*, dip* |

\* hands stay fixed – choose these manually on the watch; counting is best-effort.

## 8. Project layout

```
ExerciseTracker.xcodeproj   Xcode project (iPhone app embeds the Watch app)
Shared/                     Platform-independent motion core used by both apps
  Math/                     Vectors, quaternions, DSP helpers
  Model/                    Exercises, workouts, calibration profile, features
  Processing/               Calibration engine, rep detector, classifier, feedback, live tracker
WatchApp/                   watchOS app (CoreMotion, HealthKit, haptics, SwiftUI)
iOSApp/                     iPhone app (history, charts, settings, export)
Config/                     Bundle-ID prefix, entitlements, Info.plist keys
Tests/                      Unit tests for the core (simulated curls, presses, rows, …)
ML/                         How to train your own Core ML model
scripts/                    Project generator, icon generator
```

## 9. Tests

The motion core has no Apple-only dependencies, so its tests run anywhere Swift runs:

```bash
swift test
```

They simulate physically consistent arm motion for 13 exercises and check rep counts, tempo, range of
motion, partial-rep/rushed-rep feedback, calibration for different ways of wearing the watch, and
classification. GitHub Actions runs these tests and builds both apps on every push.

## 10. Troubleshooting

- **"Unable to install … watch app"**: unlock the watch, keep it on the charger next to the phone, and run the *Watch App* scheme once directly.
- **Reps not counted**: make sure the set is rhythmic and the watch is snug. For fixed-hand machines, lock the exercise first (swipe left during the workout).
- **Wrong exercise**: correct it in the set summary – it learns. Reset learning in watch Settings if it ever gets confused.
- **Bundle identifier errors**: change `BUNDLE_ID_PREFIX` in `Config/Base.xcconfig`.
