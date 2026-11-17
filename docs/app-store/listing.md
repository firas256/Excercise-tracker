# App Store listing – draft

Everything below is a draft to paste into App Store Connect. Check that the name is still free
(App Store Connect › My Apps › + › New App) before you settle on it. Character limits are Apple's.

## Basics
| Field | Value |
|---|---|
| Name (≤30) | **Rep Coach** – alternatives if taken: *Rep Coach: Lift Tracker*, *RepCoach – Gym Rep Counter* |
| Subtitle (≤30) | Auto rep counter for lifting |
| Primary category | Health & Fitness |
| Secondary category | Sports (optional) |
| Age rating | 4+ (questionnaire: no objectionable content, no medical/treatment information, no unrestricted web access) |
| Price | your decision (free / paid / free with optional purchase) |
| Requires | iPhone with iOS 17+, paired Apple Watch with watchOS 10+ |
| Privacy label | **Data Not Collected** (the app has no networking and sends nothing off the user's devices) |
| Privacy policy URL | https://firas256.github.io/Excercise-tracker/privacy-policy (after GitHub Pages is on) |
| Support URL | https://firas256.github.io/Excercise-tracker/support |
| Copyright | © 2026 _[your name]_ |

## Promotional text (≤170, can change any time)
Your Apple Watch counts every rep, recognises the exercise and coaches your form – and your iPhone
shows it all live, so you never twist your wrist mid-set.

## Description (≤4000)
Rep Coach turns your Apple Watch into a training partner that watches your form.

START, CALIBRATE, LIFT
Start a workout from your iPhone or watch. A one-minute guided calibration – shown and read aloud on
your iPhone – learns how you wear the watch and measures your arm. Then just lift: sets start
automatically when you move.

COUNTS EVERY REP
The watch counts reps as you go and taps your wrist on each one. Reps that cover less than half of
your full range don't count, and you'll feel the difference.

RECOGNISES THE EXERCISE
Curls, presses, raises, rows, pushdowns, squats and more – 29 exercises are recognised
automatically, others you pick with a tap. It tells a palm-up curl from a hammer curl or a rope
pushdown by how your wrist is turned, and it learns your form from every set you confirm.

COACHES YOUR FORM
After each set: range of motion, lifting and lowering tempo, partial or rushed reps, swinging, and
how much your speed dropped – a sign of how close you were to failure. Form checks use your own body:
your shoulder height, your overhead reach and your arm length, not an average person's.

FOLLOW ALONG ON YOUR IPHONE
A live 3-D view of your arm, the rep count, coaching cues, the rest timer and every control – on the
big screen, so your wrist stays where it should. Replay any set afterwards to see how you moved.

YOUR DATA STAYS YOURS
No account, no ads, no tracking. Workouts stay on your iPhone and Apple Watch and, if you allow it,
in Apple Health.

Rep Coach is a training aid, not a medical device. Rep counts, exercise recognition and form tips are
estimates from your watch's motion sensors.

## Keywords (≤100, comma-separated, no spaces needed)
rep counter,gym,lifting,strength,workout log,sets,reps,dumbbell,form,tempo,weights,tracker,bodybuilding

(Avoid other companies' trademarks. "Apple Watch" may appear in the description as above, not in
the name or keywords.)

## What's new (first version)
First release.

## App Review notes
- Rep Coach needs a paired Apple Watch: the watch's motion sensors count reps and recognise
  exercises; the iPhone shows the workout live and stores the history.
- To try it: on the iPhone tap **Start workout on Apple Watch** (or Start Workout on the watch),
  follow the five calibration poses shown on the iPhone, then do a few bicep curls with the watch
  arm. The rep count, exercise guess and live arm view appear on both devices.
- Without doing a workout: the empty Today screen offers **Load demo workout**, which fills the History
  with a sample workout so every screen can be seen.
- HealthKit: workouts are saved to Apple Health as Traditional Strength Training; heart rate and
  active energy are read during workouts and shown with them. The HealthKit workout session also lets
  the watch keep counting, tapping and updating the iPhone while the wrist is down. Health data is not
  used for advertising, not shared and not stored in iCloud.
- Background modes (watch): `workout-processing` for the HealthKit workout session;
  `physical-therapy` (extended runtime session) only as a fallback that keeps the motion sensors
  running if the user declines Health access – the app is a strength-training (strengthening
  exercise) tool.
- Demo video: _[link to a 1–2 minute screen recording of a real set]_

## Screenshots
Required sizes: iPhone 6.9" (1320 × 2868 portrait) and Apple Watch (e.g. Series 11 46 mm, 416 × 496,
or Ultra 3, 422 × 514). The **Simulator UI tests** workflow uploads full-resolution PNGs in the
`app-store-screenshots` artifact. Suggested picks:
- iPhone: live workout (ios-60), set review (ios-65), arm-motion replay (ios-26), Today with
  measurements (ios-11), set charts (ios-23), calibration guide (ios-50).
- Watch: live reps (watch-07), set summary (watch-08), calibration (watch-03), rest (watch-11).
