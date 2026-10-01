#!/bin/bash

# Builds Sidetap, signs it with a fixed local identity, and installs it in
# ~/Applications.
#
# macOS ties permission grants (Microphone, Accessibility, Screen Recording)
# to an app's signature. An ad-hoc signature changes with every build, so each
# rebuild silently loses its grants. Signing every build with the same
# certificate keeps them. The app is installed outside /tmp because System
# Settings can't list an app that runs from there.
#
# One-time setup: create a self-signed code-signing certificate named
# "Sidetap Local Signing" in your login keychain. See CONTRIBUTING.md.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
identity="${SIDETAP_SIGN_IDENTITY:-Sidetap Local Signing}"
derived_data="/tmp/SidetapDerived"
built_app="$derived_data/Build/Products/Debug/Sidetap.app"
installed_app="$HOME/Applications/Sidetap.app"
lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

if ! security find-certificate -c "$identity" >/dev/null 2>&1; then
  echo "No certificate named \"$identity\" in your keychain. See CONTRIBUTING.md." >&2
  exit 1
fi

cd "$repo_root"
xcodebuild \
  -project Sidetap.xcodeproj \
  -scheme Sidetap \
  -configuration Debug \
  -derivedDataPath "$derived_data" \
  -quiet \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  build

# Sign nested code first, then the app itself with its entitlements.
find "$built_app/Contents" \( -name "*.dylib" -o -name "*.framework" \) -print0 |
  xargs -0 codesign --force --sign "$identity"
codesign --force --sign "$identity" --entitlements Config/Sidetap.entitlements "$built_app"

osascript -e 'quit app "Sidetap"' >/dev/null 2>&1 || true
mkdir -p "$HOME/Applications"
rm -rf "$installed_app"
ditto "$built_app" "$installed_app"

# Keep LaunchServices pointing at the installed copy, not the build folder.
"$lsregister" -u "$built_app" >/dev/null 2>&1 || true
"$lsregister" -f "$installed_app"

codesign --verify --strict "$installed_app"
open "$installed_app"
echo "Installed and opened $installed_app, signed as \"$identity\"."
