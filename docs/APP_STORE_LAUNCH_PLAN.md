# Rep Coach – App Store launch plan

Status key: ✅ done · 🔜 next · ⬜ to do. **Who:** *You* = only you can do it (accounts, devices,
decisions, real-world data); *Claude* = code, tests, docs, model work in a session.

The order matters: phases 0–1 unblock everything else, and the biggest unknown is **real-world
accuracy on a real watch** (phase 2), which only you can measure.

---

## Phase 0 – Accounts and decisions (≈1 day, *You*)

| # | Step | Status | Notes |
|---|---|---|---|
| 0.1 | Join the **Apple Developer Program** ($99/year) | ⬜ | Required to publish, and for HealthKit on device. Use the same Team ID in `Config/Local.xcconfig`. |
| 0.2 | Pick the **name** and check it's free (App Store Connect › My Apps › +) | ⬜ | Draft: "Rep Coach" (alternatives in [`app-store/listing.md`](app-store/listing.md)). |
| 0.3 | Final **bundle ID prefix** (e.g. `com.yourname.repcoach`) | ⬜ | Set `BUNDLE_ID_PREFIX` in `Config/Local.xcconfig`; it can't change after the first upload. |
| 0.4 | **Price model** (free / paid / free + optional purchase) | ⬜ | Health data can never be used for ads or sold, whatever the model. |
| 0.5 | **Turn on GitHub Pages** (repo Settings › Pages › branch `claude/quirky-mendel-t2w39x` (or `main`), folder `/docs`) | ⬜ | Publishes the privacy policy and support page the app links to. |
| 0.6 | Add a **support email** to `docs/privacy-policy.md` and `docs/support.md` | ⬜ | Placeholders are marked `[…]`. |
| 0.7 | Decide whether the **repo stays public** | ⬜ | It's public now. Fine for an open-source app; make it private if you'd rather not publish the code. |

## Phase 1 – Product and AI (*Claude* + your data)

### Done in this session
- ✅ Wrist-down: HealthKit workout session for calibration and workouts, Health access requested when
  needed, clear warning when it can't run, queued delivery to the iPhone (no lost steps).
- ✅ Personal body model from calibration: arm length (measured), forearm/upper arm/height estimates,
  personal shoulder-height and overhead angles, palm-turn range.
- ✅ Exercise recognition: grip check (palm up / thumb up / palm down per exercise), elbow-vs-shoulder
  pivot from your forearm/arm length, effort direction, direction-independent rep angles, Core ML model
  can't outvote exercises it never learned. Curl ↔ pushdown confusion fixed (16/16 test cases, 3 body
  sizes).
- ✅ Reps under half the required range aren't counted (with a distinct tap and a cue).
- ✅ Rep counting fix: presses/rows no longer lose the first or last rep (13 exercises × 8 variations).
- ✅ Live workout screen, set review and arm-motion replay on the iPhone.
- ✅ Pipeline to retrain on **your own recorded sets** (`ML/training/add_user_data.py`).
- ✅ **Checked against 13 real sets** from your watch (curls, raises, presses, squat, pec deck,
  pushdowns). Changes that came out of it: grip is a soft, *learnable* preference (some of your
  pushdowns look underhand), presses with the elbows forward are recognised (were guessed as squats),
  and on-device learning no longer creates rules from 1–2 noisy sets. The whole app pipeline now gets
  **10/13 right, and the right answer is in the top two for 13/13**, once it knows your palm-up range
  (from your calibration). Remaining misses: lateral vs front raise (look the same from the wrist) and
  one pushdown that looks exactly like your curls.
- ✅ Tried a **grip-aware AI model** (RecoFit curls split into palm-up vs hammer): equal on held-out
  RecoFit people, but worse on your real curls (your palm-up reads ~127°), so it was **not shipped** –
  see `ML/README.md`.

### AI: next steps
| # | Step | Who | Status |
|---|---|---|---|
| 1.1 | **Recalibrate** with the new version (it measures your arm and your palm-up range – the range alone moved your sets from 8/13 to 10/13). | You | 🔜 |
| 1.2 | Keep recording with **Save sensor data** on and **correct every wrong guess before saving** (the label is whatever you confirm). Aim for **10+ sets per exercise**, over several days. Note your real rep count for a few sets. | You | 🔜 |
| 1.3 | Export again (iPhone Settings › Export my recordings) and share the .zip. First export (14 sets) received and used for testing; too few and too mixed to train the AI model on yet. | You | ✅ / ⬜ |
| 1.4a | Retrain with your data, report accuracy on your held-out sets, ship the model only if it's better on both RecoFit and your sets. | Claude | ⬜ |
| 1.4 | Ask **3–5 friends** of different builds to do the same (TestFlight, phase 4). One person's data makes the model fit *you*; others make it fit *users*. | You | ⬜ |
| 1.5 | **Kaggle "Gym Workout IMU Dataset"** – recorded on an *Apple Watch* (left wrist, 100 Hz, 164 sets, ~37 gym exercises incl. cable pushdowns, preacher curls, rear delt flies). Its licence is only visible with a Kaggle login: check it; if it allows commercial use (MIT / CC BY / CC0), download and share it. | You → Claude | ⬜ |
| 1.6 | **RecGym** (CC BY 4.0, wrist IMU, 10 people, 50 h, machines + cardio + "null") – the UCI copy is corrupt (first bytes zeroed); download it from Kaggle (needs a login) and share. Mainly improves rejecting non-exercise movement and machine exercises. Credit required in the app. | You → Claude | ⬜ |
| 1.7 | **MM-Fit** (smartwatch IMU, 10 exercises): no licence stated for the sensor data → only with written permission from the authors. | You (email) | ⬜ |
| 1.8 | Not usable: **StrengthSense** (commercial use forbidden), **MyoGym** (no download found). | – | – |

Datasets checked and their licences: see the table at the end.

### Product
| # | Step | Who | Priority |
|---|---|---|---|
| 1.9 | Real-device accuracy pass (phase 2.2) → fix what it finds | You + Claude | P0 |
| 1.10 | Watch complication (start workout / last workout) | Claude | P1 |
| 1.11 | Rest timer with a tap when rest is over; per-exercise target reps | Claude | P1 |
| 1.12 | Workout templates / routines; progress charts per exercise | Claude | P2 |
| 1.13 | Localisation (at least the App Store listing) | Claude | P2 |

## Phase 2 – Testing and debugging

### 2.1 Automated (runs on every push) – ✅ in place
- 58+ unit tests on Linux: rep counting (13 exercises × 8 variations), exercise recognition by grip at
  3 body sizes, too-short reps, calibration measurements, sync protocol.
- Simulator UI tests (iPhone + Watch): every screen, the live workout, set review, calibration and a
  full simulated watch workout. The job fails if any test fails, and uploads screenshots.
- **Accessibility audit** (Apple's `performAccessibilityAudit`) on every main iPhone screen, in light
  and dark mode: contrast, VoiceOver labels, tap targets, Dynamic Type, clipped text. Text colours are
  a WCAG-AA palette (`iOSApp/Views/Theme.swift`, 4.5:1 for text, also on tinted badges and buttons).
- **Release build** check: the App Store configuration builds and contains both privacy manifests
  and all required Info.plist keys.
- Core ML model check: the shipped model reproduces its PyTorch source.

### 2.2 On your devices (*You*) – the most important part
Use this checklist for each item: ✅ works / ❌ what happened.

**Counting and recognition** (3 sets each, ~10 reps; note the watch's count and guess):
bicep curl, hammer curl, triceps pushdown (bar and rope), shoulder press, lateral raise, front raise,
bench press, lat pulldown, seated row, squat, deadlift, plus any exercise you do regularly.
Target before launch: counts within ±1 on 90 % of sets; correct exercise (after 3 reps) on 80 %+ of
sets for curls/presses/raises/pushdowns.

**Workout flow:** start from iPhone; start from watch; calibrate from the watch home screen; skip a
pose; "use last calibration"; end a set from the iPhone; save/discard from both; end the workout from
the phone; workout appears in History and Apple Health.

**Conditions:** wrist down for a whole set (taps + iPhone updates continue); iPhone locked / app in
background, then reopened (catches up); iPhone out of Bluetooth range for a set; watch on the other
wrist / crown on the other side (recalibrate); Health access denied (orange warning, still counts);
Low Power Mode; a 60-minute workout (watch battery use – target ≤ 15 %); phone call during a workout.

**Devices:** the oldest and newest iPhone and Apple Watch you can borrow; watchOS 10 and the latest.

**Upgrade path:** install the previous TestFlight build, record workouts, install the new build –
everything still there.

### 2.3 TestFlight beta (*You*, 2–3 weeks)
Internal testing (you) → external group (friends, 10–50 people; needs a short Beta App Review).
Ask testers to note wrong counts/guesses and to export their recordings for 1.4.
Watch crash reports in Xcode › Window › Organizer › Crashes and TestFlight feedback.

## Phase 3 – UI and polish

| # | Step | Who | Priority |
|---|---|---|---|
| 3.1 | Fix every issue the accessibility audit reports | Claude | P0 |
| 3.2 | VoiceOver walkthrough of a whole workout on the iPhone; Larger Text at the largest size; Dark Mode | You (check) + Claude (fix) | P0 |
| 3.3 | Final app icon (1024 × 1024, no transparency) for iPhone and watch | You / designer | P0 |
| 3.4 | Onboarding: say clearly that an Apple Watch is required and why Health access matters | Claude | P0 |
| 3.5 | Watch: check every screen in Always-On (dimmed) state and on the smallest watch size | You (check) + Claude (fix) | P1 |
| 3.6 | Empty and error states (no watch paired, watch app not installed, Health unavailable) | Claude | P1 |

## Phase 4 – App Store Connect (*You*, with drafts from Claude)

| # | Step | Status |
|---|---|---|
| 4.1 | Create the app record; register both bundle IDs; enable **HealthKit** for both App IDs | ⬜ |
| 4.2 | Privacy: **Data Not Collected**; privacy policy URL | ⬜ (draft ready) |
| 4.3 | Age rating questionnaire (4+), category Health & Fitness, price, countries | ⬜ |
| 4.4 | Name, subtitle, description, keywords, promotional text | ✅ draft in [`app-store/listing.md`](app-store/listing.md) |
| 4.5 | Screenshots: iPhone 6.9" and Apple Watch – full-resolution PNGs from the UI-test run (`app-store-screenshots` artifact); optionally add captions/frames | ⬜ |
| 4.6 | Review notes + a 1–2 minute **demo video** of a real set (reviewers may not lift weights) | ⬜ (notes drafted) |
| 4.7 | Archive in Xcode (Product › Archive, scheme *ExerciseTracker*, which includes the watch app) › Distribute › App Store Connect | ⬜ |
| 4.8 | Export compliance | ✅ `ITSAppUsesNonExemptEncryption = NO` |

## Phase 5 – Submission and review risks

| Risk | Guideline | Mitigation |
|---|---|---|
| HealthKit use not clear to the user | 5.1.3 | Usage strings say why; About › Privacy explains it; review notes explain it. ✅ |
| Health data in iCloud | 5.1.3(ii) | The app uses no iCloud storage. Device backups are user-controlled. ✅ |
| Background mode `physical-therapy` questioned | 2.5.4 | It's only a fallback when Health access is declined; explained in review notes. If rejected: remove it (the HealthKit session covers everyone who allows Health access). |
| Medical claims | 1.4.1 | "Training aid, not a medical device" in the app and listing; no injury/health claims. ✅ |
| Accuracy claims in the listing | 2.3.1 | Claims match what the app does (29 auto-detected, others manual). ✅ |
| Reviewer can't test without a watch / gym | 2.1 | Demo workout in the empty Today screen, demo video, clear notes. |
| Placeholder / developer-only content | 2.1 | Release builds hide Create ML instructions and "Add demo workout". ✅ |
| Privacy manifest / required-reason APIs | 5.1.1 | `PrivacyInfo.xcprivacy` in both apps (UserDefaults CA92.1), checked by CI. ✅ |

## Phase 6 – Launch and after

1. Submit with **manual release**; when approved, release on a day you can watch for problems.
2. Week 1: crash reports (Organizer), reviews, support issues; ship a fix update if needed.
3. Every 4–8 weeks: retrain the model on new consented recordings (testers / volunteers) and ship it
   in an update. *Never* collect users' recordings without explicit opt-in – that would change the
   privacy label.
4. Roadmap candidates: complications, routines, progress charts, more exercises, localisation.

---

## Datasets checked (November 2026)

| Dataset | Sensor | Licence | Commercial use | Verdict |
|---|---|---|---|---|
| RecoFit (Microsoft) | forearm IMU, 94 people, 50 Hz | CDLA-Permissive-2.0 | ✅ (models are "Results") | in use |
| RecGym (UCI 1128 / Kaggle) | wrist IMU 20 Hz + capacitance, 10 people, 11 workouts + null | CC BY 4.0 | ✅ with credit | wanted – UCI zip corrupt, get from Kaggle |
| Gym Workout IMU Dataset (Kaggle) | **Apple Watch SE**, left wrist, 100 Hz, 164 sets, ~37 exercises | not readable without login | ❓ | check licence (1.5) |
| MM-Fit | smartwatch IMU (TicWatch Pro), 10 exercises | video CC BY 4.0; sensor data unstated | ❓ | ask authors |
| StrengthSense | Movesense IMUs incl. wrists, daily strength activities | non-commercial only | ❌ | no |
| MyoGym | Myo armband (forearm), 30 exercises | no public download found | ❓ | no |
| Your own recordings | your Apple Watch | yours | ✅ | best data there is (1.1–1.3) |
