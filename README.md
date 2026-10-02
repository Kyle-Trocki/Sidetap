# Sidetap

**Tap your desk. Your Mac responds.**

Sidetap is a fork of [Holo](https://github.com/JustinGamer191/Holo) by JustinGamer191.

Sidetap is an experimental native macOS utility that runs an action when you double-tap or triple-tap the desk around a MacBook. It listens through the Mac's microphone, checks locally that each sound is a tap on your desk, and counts the taps.

Sidetap began as zone-based: four zones around the MacBook, each with its own action. Calibration, diagnostics, and the zone accuracy test still use those zones, but actions no longer do, because counting taps proved more reliable than telling zones apart.

Calibration uses four broad zones so that Sidetap hears taps from all around the MacBook:

```text
                  Display side
Left Rear      ┌─────────────┐      Right Rear
               │   MacBook   │
Left Front     └─────────────┘      Right Front
                  Trackpad side
```

Sidetap is a research prototype. Automated DSP tests pass, but useful accuracy still has to be measured on each real MacBook, desk, room, and laptop position. No physical accuracy claim is made without a saved evaluation from that setup.

The requirement-by-requirement evidence ledger is in [ACCEPTANCE.md](ACCEPTANCE.md).

## What is implemented

- Double-tap and triple-tap gestures anywhere on the desk, each with its own action.
- Four fixed calibration zones: rear and front zones on each side of the MacBook.
- Explicitly armed calibration: ten accepted examples spread across each zone, 40 total, with clear retry guidance for weak, noisy, or clipped taps.
- A calibration-consistency check that identifies and can redo the weakest zone before saving.
- Adaptive streaming onset detection, sustained-sound rejection, and fixed 90 ms analysis windows that start 12 ms before each onset.
- Passive tap acoustics, an optional active acoustic probe, and a hybrid mode.
- Robust feature normalization, a regularized linear zone model backed by nearest-example novelty checks, ambiguity rejection, out-of-distribution rejection, and optional negative examples.
- A typing check that ignores taps within 300 ms of a physical key press or click, and a noise limit that pauses actions in a loud room.
- Location-based desk switching: each profile can be pinned to where its desk is, and Sidetap selects it automatically within 300 m.
- Per-profile actions: visual only, play a sound, copy, paste, or speak text, open a website, run a Shortcut, open an application or item, execute a shell command, or take a screenshot to the Desktop, the clipboard, or both. Both gestures default to visual-only until the user assigns a side effect.
- A guided held-out zone accuracy test of 60 double taps, with per-zone accuracy, latency, rejected counts, and a confusion matrix.
- Saved evaluation history is restored after relaunch and scoped to the desk profile that produced it.
- Signal diagnostics, labeled feature capture, approach comparison, JSON/CSV reports, and opt-in raw debug WAV capture.
- Sandboxed, local persistence. Raw audio is discarded by default.
- Capture always uses the built-in microphone, and the Active and Hybrid probe always uses the built-in speakers, whatever the system default is.

## Requirements

- macOS 14 or later.
- Xcode 26 is recommended for the current project. The app uses Liquid Glass button styles on macOS 26 and native bordered controls on older supported systems.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to regenerate `Sidetap.xcodeproj` from `project.yml`.
- A MacBook with a built-in microphone. Sidetap uses it even when AirPods or another input is the system default, so the calibrated signal path never changes.
- Active and Hybrid sensing also use the built-in speakers, even when another output is the system default. Passive sensing doesn't emit a probe.

## Build

Generate the Xcode project after changing `project.yml`:

```sh
xcodegen generate
```

Then open `Sidetap.xcodeproj`, select the `Sidetap` scheme, and run it on My Mac. A new install requests microphone permission when calibration begins or when the user explicitly presses Resume; it does not prompt merely because the window opened.

Use Xcode's normal **Sign to Run Locally** build when launching Sidetap. `CODE_SIGNING_ALLOWED=NO` is only for non-GUI verification; its stripped bundle lacks the audio-input entitlement and should not be launched. An ad-hoc local build loses its macOS permission grants whenever its binary changes. Selecting an Apple Development team gives macOS a stable signing identity across rebuilds, and so does `scripts/install_local.sh`, which signs each build with a fixed local certificate and installs it in `~/Applications` (see [CONTRIBUTING.md](CONTRIBUTING.md)). Within one build, Sidetap coalesces concurrent microphone starts and authorization requests, and its bundle prohibits duplicate app instances.

A non-signing command-line build is useful for CI or local verification:

```sh
xcodebuild \
  -project Sidetap.xcodeproj \
  -scheme Sidetap \
  -configuration Debug \
  -derivedDataPath /tmp/SidetapDerived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Calibration

1. Put the MacBook where it will remain during use. Moving or rotating it changes the acoustic path and invalidates the profile.
2. Open Calibration and describe the desk, surface, and MacBook position.
3. Keep Passive tap acoustics selected unless Diagnostics has compared the approaches on this exact setup.
4. Begin calibration. Sidetap prepares and arms the highlighted zone automatically.
5. Wait for Preparing to change to Listening, then make ten natural taps with a short pause between them. Spread the taps around the highlighted area instead of repeating one exact point.
6. Weak, masked, or clipped taps are not added; Sidetap explains whether to tap more firmly, wait for quiet, or use a lighter touch.
7. The zone disarms after ten accepted samples. Move to the next highlighted zone during the short transition; Sidetap arms it automatically. Sounds made during the transition are ignored. If listening is paused, use the visible Arm control after resuming.
8. Use Undo for the latest sample or Redo Zone if a set was inconsistent.
9. Review the leave-one-out calibration agreement. If it is weak, redo the identified zone before saving.
10. Save the 40-sample profile and assign an action to each gesture.

Talking, typing, touching the laptop, and room noise can be collected as negative examples after the four zones are complete. Talking is recommended: speak normally for a few seconds and Sidetap records only speech peaks that get past the impact gate. Negative examples intentionally do not have to pass the clean-tap quality gate. Only their feature vectors are persisted unless raw debug recording is separately enabled.

Profiles from the obsolete six-zone and nine-zone topologies are intentionally ignored. Recalibrate rather than trying to reinterpret old samples as new physical zones.

While calibration, an accuracy test, or a sensing comparison is active, unrelated sidebar destinations and profile switching are disabled. Cancel or finish the guided capture first. Pausing the microphone disarms every pending capture, including rejection training. Changing profiles never turns a paused microphone back on; explicitly starting a guided capture does resume it.

## Switching desks by location

If you use Sidetap at more than one desk, such as at home and at work, calibrate a profile at each desk. Sidetap then switches to the right one when you arrive.

1. Calibrate a desk and select its profile.
2. In the profile menu in the toolbar, choose **Use This Location for** the profile. The first time, macOS asks for location access.
3. Repeat at each desk. A new desk that you calibrate while location switching is on is pinned to where you are automatically.

Sidetap switches to a pinned profile only when the Mac is within 300 m of it. Anywhere else, Sidetap suggests setting up a new desk there, once per place, and keeps the current profile until you do. Sidetap ignores location fixes that are less precise than 300 m. It can't tell apart two desks in the same building. To remove a pin, choose **Forget Location for** the profile.

## Assigning actions

Actions contains two rows: one for a double tap and one for a triple tap. Changes save to the selected profile as they are made, and each configured action has an inline Test button.

- Visual only shows the gesture without a side effect.
- Play sound uses an available macOS system sound.
- Copy text writes the configured text to the pasteboard.
- Paste text sends ⌘V to the frontmost app. With no text configured, it pastes whatever is on the pasteboard. With text configured, it puts that text on the pasteboard, pastes it, and then restores the previous contents. macOS asks for Accessibility access the first time.
- Speak text uses the local speech synthesizer.
- Open website accepts HTTP or HTTPS addresses.
- Run Shortcut opens the named Shortcut through the system Shortcuts URL scheme.
- Open or focus app stores an app-scoped security bookmark for the application selected by the user.
- Open file or folder stores an app-scoped security bookmark for a user-selected item.
- Run shell command executes the configured command through `/bin/zsh` with Sidetap's sandbox permissions.
- Screenshot captures the full display.
- Screenshot selected area opens the same area selector as Command-Shift-4.

Both screenshot actions save a PNG file to the Desktop by default. Each one can copy to the clipboard instead, or do both. Saving to the Desktop uses a sandbox exception for that folder.

Gestures work anywhere on the desk. Taps no more than 0.45 seconds apart belong to one gesture. A triple tap runs its action at the third tap. A double tap runs its action about 0.7 seconds after the second tap, once it's clear that no third tap is coming. A single tap does nothing.

Each tap must still sound like a tap on the calibrated desk, so calibrate before you assign actions. Which zone a tap came from doesn't matter.

Sidetap ignores a tap in these cases, even when it sounds like one:

- A key press or trackpad click happened within 300 ms of it. Typing shakes the MacBook the same way a tap does.
- The room is too noisy. When the background level is above about ten times that of a quiet room, Sidetap runs no actions and the status bar says so.

Actions run only while Desk is selected. Calibration, profile editing, diagnostics, accuracy reports, and the Actions editor suppress automatic side effects; the editor's inline Test button remains explicit. Weak, clipped, noisy, or out-of-distribution sounds don't count as taps. A tap whose zone is unclear still counts. Shell commands run automatically once assigned, so commands should be safe to repeat and should not depend on an interactive terminal. macOS may request access when an action first opens a protected item or captures the screen. A Shortcut is the recommended way to compose multi-step workflows such as opening Claude and beginning a user-defined voice flow.

## Supported surfaces

The practical target is a stable, rigid desk where taps create repeatable resonances: solid wood, engineered wood, laminate, and similarly rigid tops are the best candidates. Glass, metal, hollow-core, very large, mechanically coupled, or heavily damped desks are experimental and require their own measured profile. Soft mats, moving laptop stands, and desks that shift under normal use are not supported assumptions.

Support is determined by a completed accuracy test on the exact setup, not by material name alone. No desk material is declared supported globally.

## Zone accuracy test

The Zone Accuracy Test, under Advanced, scores how well Sidetap tells the four zones apart. Actions no longer depend on that, so treat it as a diagnostic of the calibration, not of gestures. The app has no built-in test for gestures yet.

The test is separate from calibration and uses new taps. It guides fifteen double taps per zone, 60 total, and combines both taps of each double tap into one zone decision. Each zone must be armed, preventing movement and interface sounds from being counted before the user is ready. A detected event made while armed is included even if the classifier rejects it; rejected taps therefore count as incorrect. Response latency runs from the audio tap buffer's monotonic `AVAudioTime` host timestamp through feature extraction, the main-thread handoff, and classification.

The prototype acceptance targets are:

- At least 80% overall accuracy over a balanced session of 60 double taps.
- Median response latency below 200 ms.
- No crashes or unbounded memory growth during a 30-minute run.

The app saves each completed evaluation as JSON and CSV. Reports include per-zone accuracy, the four-by-four confusion matrix, a rejected column, confidence, and response latency. The newest saved report for the selected profile is restored after relaunch; reports from another desk are never shown as the current result. Reports from an obsolete topology are skipped. If either file cannot be saved, the screen identifies the result as memory-only. Invalid host-clock timestamps are exported as `INVALID` and prevent the latency target from passing. Calibration cross-validation is shown only as a diagnostic; it is not a substitute for held-out evaluation.

## Sensing approaches

Passive tap acoustics is the default and does not play sound. The feature extractor combines temporal shape, frequency bands, log-mel/MFCC-style coefficients, and any spatial differences exposed by the selected input channels.

Active acoustic probe emits a low-amplitude 15.5–21 kHz chirp every 120 ms and adds response-correlation features. Hybrid combines both feature sets. Laptop speakers, microphones, sample rates, hearing ranges, and desk geometry vary, so the probe may be filtered, ineffective, or faintly audible. It is never assumed to outperform passive sensing.

Before capture starts, Sidetap finds the built-in microphone and speakers by their Core Audio transport type and pins capture and the probe to them. The system default can stay on AirPods or a display. On macOS, an `AVAudioEngine` drives input and output through one I/O unit, so the probe runs on a second engine. If no built-in microphone exists, capture doesn't start. Active and Hybrid also need built-in speakers. If either engine stops after a device change, capture stops.

The bottom status bar explicitly says when the speaker probe is active.

Onset detection begins with a 0.75-second room-learning period, then adapts its noise floor while requiring a short, high-contrast onset. macOS delivers audio in 100 ms buffers, so the 90 ms analysis window starts 12 ms before the onset, wherever the onset falls in its buffer. A second gate reviews the complete 90 ms candidate and rejects events whose effective duration, late energy, and weak early concentration clearly resemble sustained speech. Rejected sustained events also update the adaptive floor during a 50 ms refractory period, preventing conversation from repeatedly re-arming capture. An accepted tap has no refractory period, so the next tap of a gesture is heard. A separate low-pass path keeps the high-frequency probe from triggering its own capture. Accepted windows retain the untouched full-band channels for active-response feature extraction.

Diagnostics can collect three taps per zone for each approach—36 samples total—and compare leave-one-out accuracy and DSP processing latency. Every set is explicitly armed. The highest measured score becomes the suggested strategy for the next calibration, but the result is bound to the desk profile on which it was measured and cannot silently influence another profile.

## Architecture

```text
AVAudioEngine input
  → adaptive impulse detector
  → 90 ms multichannel window
  → full-event impact / sustained-sound gate
  → passive / active feature extraction
  → regularized zone model + nearest-example rejection gates
  → tap check: a tap on this desk, whichever zone
  → noise limit and typing check
  → tap counter: double or triple tap
  → local action dispatcher
```

- `Sources/SidetapCore` contains the guided capture protocols, detector, FFT and feature extraction, classifier, persistence models, diagnostics, evaluation reporting, and WAV writer. It has no SwiftUI dependency.
- `Sources/SidetapApp` contains audio capture, app state, local action dispatch, and the native SwiftUI interface.
- `Sources/SidetapSoak` is a non-GUI synthetic DSP stress runner.
- `Sources/SidetapRouteCheck` is a non-GUI check of the current Core Audio input/output transport policy.
- `Tests/SidetapCoreTests` covers guided session totals and ordering, guided-capture quality gates, adaptive room-noise rejection, microphone-request coalescing, the chunked detector-to-classifier pipeline, injected active-probe recovery, shared-spectrum analysis, hardware-route policy, validated local-action planning, negative and ambiguity rejection, the tap counter and gesture actions, evaluation history, strict profile persistence, WAV output, and the exact four-zone topology.

Each detected window uses one shared power spectrum for classification, active-response bands, and diagnostics rather than repeating the same FFT. Capture generations discard observations queued by an audio route or strategy that has already been stopped.

The interface rationale and source research are in [DESIGN.md](DESIGN.md). The central rule is that system materials and Liquid Glass support navigation and controls; they are not decoration for content. The calibration map uses two continuous two-zone rails instead of four floating cards. The UI deliberately avoids neon gradients, bento metric cards, excessive rounded containers, filler metrics, and continuous ornamental motion.

## Privacy and storage

Audio processing happens on the Mac. Sidetap does not upload audio, features, profiles, or reports. An assigned website or application action can of course open that external destination.

By default:

- The detector retains only enough in-memory audio for pre-roll and one 90 ms analysis window.
- Raw windows are discarded after feature extraction.
- Profiles store feature vectors and classifier parameters, not recordings.
- Debug recording starts disabled on every launch.

Sidetap uses one application window because there is one microphone engine and one guided-session state. Closing that window terminates Sidetap, preventing microphone capture from continuing without its in-app activity indicator.

When Retain 90 ms debug recordings is enabled in Diagnostics, each detected window is saved locally as a float WAV until the user deletes it. The UI shows a persistent red privacy warning while retention is enabled. If captures remain after a relaunch, an orange saved-audio indicator and the delete control remain visible even though new audio is being discarded.

Application Support contains:

```text
Sidetap/Profiles/                 feature-only profile JSON
Sidetap/Evaluations/              JSON and CSV evaluation reports
Sidetap/approach-comparison.json  latest sensing comparison
Sidetap/DebugCaptures/            opt-in raw WAV windows only
```

Because the app is sandboxed, these paths live inside Sidetap's app container in normal signed builds.

## Automated verification

Most recent automated check, on macOS 26.6.2 with Xcode 26.3:

- Debug and Release app builds: passed with no source warnings.
- Static analyzer: passed.
- Unit tests: 73 passed, 0 failed, 0 skipped.
- Synthetic soak in `--fast` mode: 900,000 events in 327 seconds; 810,000/810,000 zone taps correct and 90,000/90,000 weak, noisy, clipped, schema-mismatched, or out-of-distribution challenges rejected; zero false accepts; RSS 7.1 → 7.6 MB (+0.5 MB).
- Read-only route check with AirPods as the system default: MacBook Pro Microphone and MacBook Pro Speakers both reported as built-in; Passive, Active, and Hybrid ready.

Measured on one MacBook Pro (14-inch, M2 Max) and desk. These are small samples from one setup, not a general accuracy claim:

- Zone accuracy test: 50 of 60 double taps correct (83%), with a 175 ms median response.
- Recorded gestures replayed through the detector and that profile: 19 of 20 double taps and 20 of 21 triple taps ran their action, and none ran the wrong one.
- Two minutes of loud-room audio (music and talking) produced no gestures. In 45 seconds of typing, the typing check removed all 38 detections.

Run the unit suite with:

```sh
xcodebuild \
  -project Sidetap.xcodeproj \
  -scheme Sidetap \
  -configuration Debug \
  -derivedDataPath /tmp/SidetapDerived \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Build and run the synthetic soak without opening the GUI:

```sh
xcodebuild \
  -project Sidetap.xcodeproj \
  -scheme SidetapSoak \
  -configuration Release \
  -derivedDataPath /tmp/SidetapSoakDerived \
  CODE_SIGNING_ALLOWED=NO \
  build

DYLD_FRAMEWORK_PATH=/tmp/SidetapSoakDerived/Build/Products/Release \
  /tmp/SidetapSoakDerived/Build/Products/Release/SidetapSoak --duration 1800
```

Add `--fast` to skip the waits between events. It then runs 500 events for each second of `--duration`, which is 900,000 at the default.

The synthetic runner exercises feature extraction, classification, rejection gates, finite-value checks, and resident-memory behavior. It does not exercise AVAudioEngine, microphone permissions, real room noise, physical desk variability, or action dispatch.

Check the current built-in hardware routes without opening Sidetap or requesting microphone access:

```sh
xcodebuild \
  -project Sidetap.xcodeproj \
  -scheme SidetapRouteCheck \
  -configuration Debug \
  -derivedDataPath /tmp/SidetapRouteDerived \
  CODE_SIGNING_ALLOWED=NO \
  build

DYLD_FRAMEWORK_PATH=/tmp/SidetapRouteDerived/Build/Products/Debug \
  /tmp/SidetapRouteDerived/Build/Products/Debug/SidetapRouteCheck
```

## Known limitations

- A profile is specific to one MacBook, surface, room arrangement, and laptop position. Sidetap always captures from the built-in microphone, because another input would change the sensing path.
- Built-in microphone APIs may expose one aggregate channel rather than independent physical array elements.
- Soft, unstable, very large, heavily damped, or noisy surfaces may not produce separable zones.
- Short consonants, laptop touches, dropped objects, and nearby impacts can resemble taps. The sustained-sound gate, the typing check, and profile-specific negatives reduce false positives but cannot guarantee none.
- Gestures offer two actions. A double tap responds about 0.7 seconds after its second tap, because Sidetap has to wait for a possible third.
- Light taps can be missed. The detector ignores a tap that peaks below a fixed minimum, and the second tap of a quick double tap is often lighter than the first.
- Calibration quality depends on consistent natural taps. The UI prevents unarmed sounds from being added, but it cannot know whether the user tapped the intended physical location.
- The active probe is experimental and can be filtered or audible on some hardware.
- The 80% and 200 ms targets apply to the zone accuracy test and must still be demonstrated with a real held-out session for each target setup. No built-in test scores gestures.
- Automated stress results do not replace a 30-minute live microphone and action-dispatch run on the target Mac.

## Before claiming the prototype is validated

For every supported Mac/desk combination:

1. Run Diagnostics in a representative quiet and noisy environment.
2. Calibrate all four zones with the final MacBook position.
3. Run a new balanced zone accuracy test and retain its JSON/CSV report.
4. Confirm at least 80% overall accuracy and median response below 200 ms.
5. Confirm that double and triple taps run their assigned actions in live use.
6. Run the live app for 30 minutes with representative taps, conversation, typing, laptop touches, and background noise while monitoring crashes, false triggers, and memory.

Until those physical checks are complete, Sidetap should be described as functional experimental software—not a proven acoustic input device.

## License

Sidetap is available under the [MIT License](LICENSE).
