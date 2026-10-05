# Contributing to Sidetap

Sidetap is a research prototype, so the easiest contributions to review are ones
that keep the DSP test suite green and respect the design: actions run on
gestures of two or more taps, and calibration learns from double and triple taps.

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

To run the app itself, install a signed build as described in the next
section. The `CODE_SIGNING_ALLOWED=NO` bundle lacks the audio-input entitlement
and should not be launched.

## Install a local build

To build Sidetap, sign it, and install it in `~/Applications`, run:

```sh
./scripts/install_local.sh
```

The script signs every build with the same certificate. macOS ties Microphone,
Accessibility, and Screen Recording grants to an app's signature, and an ad-hoc
signature changes with every build, so an ad-hoc build loses its grants each
time. The script installs outside `/tmp` because System Settings can't list an
app that runs from there.

Before you run the script for the first time, create a self-signed
code-signing certificate named `Sidetap Local Signing` in your login keychain.
Use the system's `/usr/bin/openssl`, because `security import` can't read the
files that OpenSSL 3 writes by default:

```sh
cat > /tmp/sidetap-cert.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Sidetap Local Signing
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config /tmp/sidetap-cert.cnf -keyout /tmp/sidetap-key.pem -out /tmp/sidetap-cert.pem
/usr/bin/openssl pkcs12 -export -name "Sidetap Local Signing" -passout pass:sidetap \
  -inkey /tmp/sidetap-key.pem -in /tmp/sidetap-cert.pem -out /tmp/sidetap.p12
security import /tmp/sidetap.p12 -P sidetap -T /usr/bin/codesign \
  -k ~/Library/Keychains/login.keychain-db
rm /tmp/sidetap-cert.cnf /tmp/sidetap-key.pem /tmp/sidetap-cert.pem /tmp/sidetap.p12
```

The first time `codesign` uses the certificate, macOS might ask for your login
password. Choose **Always Allow**. Keychain Access lists the certificate as not
trusted, which is expected for a self-signed certificate and doesn't stop
`codesign` from using it.

To sign with a different certificate, set `SIDETAP_SIGN_IDENTITY` to its name.

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

## Where things live

- `Sources/SidetapCore` — the detection engine: streaming detector, impact gate,
  FFT and feature extraction, classifier, calibration session, persistence
  models, and diagnostics. No SwiftUI dependency. Covered by `Tests/SidetapCoreTests`.
- `Sources/SidetapApp` — audio capture, app state, local action dispatch, and the
  SwiftUI interface.
- `Sources/SidetapSoak` and `Sources/SidetapRouteCheck` — non-GUI verification
  tools.

## Notes for pull requests

- Keep changes small, and run the unit suite before opening a PR.
- Sidetap has no zones. Nine-, six-, and four-zone layouts were tried and
  abandoned in favor of counting taps, so PRs should not reopen that decision.
- DSP changes should preserve the behavior pinned by `Tests/SidetapCoreTests`
  unless the PR is explicitly about changing that behavior.
