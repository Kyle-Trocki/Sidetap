# Contributing to Sidetap

Sidetap is a research prototype, so the easiest contributions to review are ones
that keep the DSP test suite green and respect the four-zone design.

## Setup

You need macOS 14 or later, Xcode (26 recommended), and
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
```

The Xcode project is generated from `project.yml`. After changing `project.yml`
— or adding or removing source files — regenerate it:

```sh
xcodegen generate
```

## Build and test

A non-signing command-line build is the quickest way to verify a change:

```sh
xcodebuild \
  -project Sidetap.xcodeproj \
  -scheme Sidetap \
  -configuration Debug \
  -derivedDataPath /tmp/SidetapDerived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run the unit suite with the same invocation, replacing `build` with `test`.

To run the app itself, use Xcode's normal **Sign to Run Locally** build. The
`CODE_SIGNING_ALLOWED=NO` bundle lacks the audio-input entitlement and should
not be launched (see the README's Build section).

## Soak runner

The synthetic DSP stress runner exercises detection, feature extraction,
classification, and rejection without the GUI or a microphone:

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

## Route check

Check the current built-in hardware routes without opening Sidetap or requesting
microphone access:

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

## Offline replay

Retain evaluation feature vectors by running a new Accuracy Test in the app,
then replay its saved JSON against a freshly trained classifier:

```sh
swift run SidetapReplay \
  --profile path/to/profile.json \
  --evaluation path/to/evaluation.json
```

Add `--json` for machine-readable output. Reports created before feature
retention show reduced coverage, and their missing attempts remain incorrect in
the replay denominator. For future WAV replay investigations, enable **Retain
90 ms debug recordings** before the Accuracy Test and preserve the entire
`Sidetap/DebugCaptures` directory alongside the profile and evaluation JSON.

## Where things live

- `Sources/SidetapCore` — the detection engine: streaming detector, impact gate,
  FFT and feature extraction, classifier, persistence models, diagnostics, and
  evaluation reporting. No SwiftUI dependency. Covered by `Tests/SidetapCoreTests`.
- `Sources/SidetapApp` — audio capture, app state, local action dispatch, and the
  SwiftUI interface.
- `Sources/SidetapSoak`, `Sources/SidetapReplay`, and `Sources/SidetapRouteCheck` —
  non-GUI verification tools.

## Notes for pull requests

- Keep changes small, and run the unit suite before opening a PR.
- The four-zone topology is intentional. Six- and nine-zone layouts were tried
  and abandoned (see the README), so PRs should not reopen that decision.
- DSP changes should preserve the behavior pinned by `Tests/SidetapCoreTests`
  unless the PR is explicitly about changing that behavior.
