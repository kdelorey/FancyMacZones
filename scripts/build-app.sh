#!/usr/bin/env bash
# Builds FancyMacZones.app into ./build.
#
#   scripts/build-app.sh            # release build, signed
#   scripts/build-app.sh --install  # also copy to /Applications and relaunch
#
# Signing: uses $SIGN_IDENTITY if set, otherwise the first "Apple Development"
# identity in the keychain, otherwise ad-hoc. A stable identity matters: macOS
# ties the Accessibility grant to the signature, so ad-hoc builds must be
# re-granted after every rebuild.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG=release
APP=build/FancyMacZones.app
INSTALL=false
[[ "${1:-}" == "--install" ]] && INSTALL=true

swift build -c "$CONFIG" --product FancyMacZones
BIN="$(swift build -c "$CONFIG" --show-bin-path)/FancyMacZones"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FancyMacZones"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -n1)"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
echo "Signing with: $SIGN_IDENTITY"
codesign --force --sign "$SIGN_IDENTITY" "$APP"

echo "Built $APP"

if $INSTALL; then
  pkill -x FancyMacZones 2>/dev/null || true
  rm -rf /Applications/FancyMacZones.app
  cp -R "$APP" /Applications/
  open /Applications/FancyMacZones.app
  echo "Installed to /Applications/FancyMacZones.app"
fi
