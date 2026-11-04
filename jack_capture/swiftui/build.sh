#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Licence of the program this interface drives (jack_capture).
#
# Builds "Jack Capture.app": the SwiftUI interface of jack_capture.
#
#   ./build.sh            Release: universal (arm64 + x86_64), ad hoc signature
#   ./build.sh --debug    Debug: native architecture only, faster
#
# SwiftPM compiles the code; this script assembles the bundle (localisations, Info.plist, helper).
# It needs Xcode (swift 6, actool). DEVELOPER_DIR is set for this script only: the global
# xcode-select setting is not changed. Signing with a Developer ID, notarisation and the installer
# are not part of this script.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
cd "$here"

APP_NAME="Jack Capture"
EXECUTABLE="JackCapture"
BUNDLE_ID="io.github.zinc75.jackappscollection.jackcapture"
VERSION=$(cat VERSION 2>/dev/null || echo "0.0.0")
# VERSION is the version of jack_capture; REVISION counts the releases of the macOS edition for that version.
REVISION=$(cat REVISION 2>/dev/null || echo "0")
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
[ -d "$DEVELOPER_DIR" ] || { echo "error: Xcode not found at $DEVELOPER_DIR (set DEVELOPER_DIR)" >&2; exit 1; }

if [ "${1:-}" = "--debug" ]; then
  CONFIG=debug; ARCHS=(); LABEL="debug, native architecture"
else
  CONFIG=release; ARCHS=(--arch arm64 --arch x86_64); LABEL="release, universal"
fi
OUT="$here/build"
APP="$OUT/$APP_NAME.app"

echo "[1/5] Compiling ($LABEL)"
swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} 2>&1 | grep -v -E '^([0-9]+%:|\[[0-9]+/[0-9]+\]|Building for|Compiling|Write|Emitting|Linking|Applying)' || true
BIN=$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)
[ -x "$BIN/$EXECUTABLE" ] || { echo "error: $BIN/$EXECUTABLE was not built" >&2; exit 1; }

echo "[2/5] Assembling the bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp "$BIN/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION.$REVISION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "[3/5] Compiling the localisations (Localizable.xcstrings to .lproj)"
python3 -I - Resources/Localizable.xcstrings "$APP/Contents/Resources" <<'PY'
import json, pathlib, sys
catalog = json.loads(pathlib.Path(sys.argv[1]).read_text())
out = pathlib.Path(sys.argv[2])
strings = catalog.get("strings", {})
langs = {catalog.get("sourceLanguage", "fr")}
for entry in strings.values():
    langs.update(entry.get("localizations", {}).keys())
def esc(s): return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
for lang in sorted(langs):
    lines = []
    for key, entry in strings.items():
        value = entry.get("localizations", {}).get(lang, {}).get("stringUnit", {}).get("value", key)  # the key is the French text
        lines.append(f'"{esc(key)}" = "{esc(value)}";')
    d = out / f"{lang}.lproj"; d.mkdir(parents=True, exist_ok=True)
    (d / "Localizable.strings").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"      {lang}: {len(lines)} strings")
PY

echo "[4/5] Icon and helper"
if [ -d Resources/Assets.xcassets ]; then
  tmp=$(mktemp -d)
  xcrun actool Resources/Assets.xcassets --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 15.0 --app-icon AppIcon --output-partial-info-plist "$tmp/partial.plist" >/dev/null
  rm -rf "$tmp"
else
  echo "      no Assets.xcassets yet: the application has no icon"
fi
HELPER="$here/../build/jack_capture"
if [ -x "$HELPER" ]; then
  cp "$HELPER" "$APP/Contents/Helpers/jack_capture"
  echo "      jack_capture copied to Contents/Helpers"
else
  rmdir "$APP/Contents/Helpers"
  echo "      no ../build/jack_capture: run ../build_universal.sh first to embed the program"
fi

echo "[5/5] Ad hoc signature"
[ -d "$APP/Contents/Helpers" ] && codesign --force -s - "$APP/Contents/Helpers/jack_capture"
codesign --force -s - "$APP"

echo "Built: $APP"
echo "Run:   open \"$APP\""
