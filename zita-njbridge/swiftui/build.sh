#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Licence of the programs this interface drives (zita-j2n and zita-n2j, from zita-njbridge).
#
# Builds "Zita Network Bridge.app": the SwiftUI interface of zita-njbridge.
#
#   ./build.sh            Release: universal (arm64 + x86_64), ad hoc signature
#   ./build.sh --debug    Debug: native architecture only, faster
#
# SwiftPM compiles the code; this script assembles the bundle (Info.plist, helpers, icon). It needs Xcode (swift 6, actool).
# DEVELOPER_DIR is set for this script only: the global xcode-select setting is not changed. Signing with a Developer ID,
# notarisation and the installer are not part of this script.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
cd "$here"

APP_NAME="Zita Network Bridge"
EXECUTABLE="ZitaNetworkBridge"
BUNDLE_ID="io.github.zinc75.jackappscollection.zitanjbridge"
VERSION=$(cat VERSION 2>/dev/null || echo "0.0.0")
# VERSION is the version of zita-njbridge; REVISION counts the releases of the macOS edition for that version.
REVISION=$(cat REVISION 2>/dev/null || echo "0")
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
[ -d "$DEVELOPER_DIR" ] || { echo "error: Xcode not found at $DEVELOPER_DIR (set DEVELOPER_DIR)" >&2; exit 1; }

if [ "${1:-}" = "--debug" ]; then
  CONFIG=debug; ARCHS=(); LABEL="debug, native architecture"
else
  CONFIG=release; ARCHS=(--arch arm64 --arch x86_64); LABEL="release, universal"
fi
# BUILD_OUT puts the application elsewhere (a copy to try while the previous one is open).
OUT="${BUILD_OUT:-$here/build}"
APP="$OUT/$APP_NAME.app"

echo "[1/5] Compiling ($LABEL)"
swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} 2>&1 | grep -v -E '^([0-9]+%:|\[[0-9]+/[0-9]+\]|Building for|Compiling|Write|Emitting|Linking|Applying)' || true
BIN=$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)
[ -x "$BIN/$EXECUTABLE" ] || { echo "error: $BIN/$EXECUTABLE was not built" >&2; exit 1; }

echo "[2/5] Assembling the bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp "$BIN/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
# The resource bundles of the packages (MatrixKit: the picto of JackMoebius).
for resource_bundle in "$BIN"/*.bundle; do
  [ -d "$resource_bundle" ] && cp -R "$resource_bundle" "$APP/Contents/Resources/"
done
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION.$REVISION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "[3/5] Localisations (Localizable.xcstrings to .lproj)"
if [ -f Resources/Localizable.xcstrings ]; then
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
else
  echo "      no Localizable.xcstrings yet: the texts are the French ones"
fi

echo "[4/5] Icon and helpers"
if [ -d Resources/Assets.xcassets ]; then
  tmp=$(mktemp -d)
  xcrun actool Resources/Assets.xcassets --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 15.0 --app-icon AppIcon --output-partial-info-plist "$tmp/partial.plist" >/dev/null
  rm -rf "$tmp"
else
  echo "      no Assets.xcassets yet: the application has no icon"
fi
HELPERS=0
for program in zita-j2n zita-n2j; do
  if [ -x "$here/../build/$program" ]; then
    cp "$here/../build/$program" "$APP/Contents/Helpers/$program"
    HELPERS=$((HELPERS + 1))
  fi
done
if [ "$HELPERS" -eq 2 ]; then
  echo "      zita-j2n and zita-n2j copied to Contents/Helpers"
else
  rm -rf "$APP/Contents/Helpers"
  echo "      the programs are not built: run ../build_universal.sh first (libs/zita-resampler before it)"
fi
echo "      licence texts: not written yet"

echo "[5/5] Ad hoc signature"
if [ -d "$APP/Contents/Helpers" ]; then
  for program in "$APP/Contents/Helpers/"*; do codesign --force -s - "$program"; done
fi
codesign --force -s - "$APP"

echo "Built: $APP"
echo "Run:   open \"$APP\""
