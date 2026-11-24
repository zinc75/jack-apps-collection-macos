#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Licence of the programs this interface drives (jconvolver and fconvolver, from jconvolver by Fons Adriaensen).
#
# Builds "Jack Convolver.app": the SwiftUI interface of jconvolver and fconvolver.
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

APP_NAME="Jack Convolver"
EXECUTABLE="JackConvolver"
BUNDLE_ID="io.github.zinc75.jackappscollection.jackconvolver"
VERSION=$(cat VERSION 2>/dev/null || echo "0.0.0")
# VERSION is the version of jconvolver; REVISION counts the releases of the macOS edition for that version.
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
# Release: no debug symbols and no local symbols in the executable (about 15 MB less; the signature comes after).
if [ "$CONFIG" = "release" ]; then strip -S -x "$APP/Contents/MacOS/$EXECUTABLE"; fi
# The resource bundles of the packages (MatrixKit: the picto of JackMoebius).
for resource_bundle in "$BIN"/*.bundle; do
  [ -d "$resource_bundle" ] && cp -R "$resource_bundle" "$APP/Contents/Resources/"
done
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION.$REVISION" "$APP/Contents/Info.plist"
# The revision of the package and the day it was built: the "About" window says them (the release is published the day it is built, or the next ones).
/usr/libexec/PlistBuddy -c "Delete :JACRevision" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :JACRevision string $REVISION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :JACBuildDate" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :JACBuildDate string $(date +%Y-%m-%d)" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "[3/5] Localisations (Localizable.xcstrings to .lproj)"
for table in Localizable InfoPlist; do
if [ -f Resources/$table.xcstrings ]; then
python3 -I - Resources/$table.xcstrings "$APP/Contents/Resources" $table <<'PY'
import json, pathlib, sys
catalog = json.loads(pathlib.Path(sys.argv[1]).read_text())
out = pathlib.Path(sys.argv[2])
table = sys.argv[3]
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
    (d / f"{table}.strings").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"      {table} {lang}: {len(lines)} strings")
PY
fi
done

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
for program in jconvolver fconvolver; do
  if [ -x "$here/../build/$program" ]; then
    cp "$here/../build/$program" "$APP/Contents/Helpers/$program"
    HELPERS=$((HELPERS + 1))
  fi
done
if [ "$HELPERS" -eq 2 ]; then
  echo "      jconvolver and fconvolver copied to Contents/Helpers"
else
  rm -rf "$APP/Contents/Helpers"
  echo "      the programs are not built: run ../build_universal.sh first (the libraries of libs/ before it)"
fi
echo "      licence texts"
# The GPL of jconvolver and the licences of the statically linked libraries come from ../build_universal.sh (build/licenses).
LIC="$APP/Contents/Resources/Licenses"
if [ -d "$here/../build/licenses" ]; then
  mkdir -p "$LIC"
  cp "$here/../build/licenses/jconvolver-COPYING.txt" "$here/../build/licenses/THIRD-PARTY-LICENSES.txt" "$LIC/"
  # The application itself also links libsamplerate (to bring an impulse response to the rate of the server); the programs do not.
  python3 -I - "$here/../../libs/libsamplerate" "$LIC/THIRD-PARTY-LICENSES.txt" <<'PY'
import pathlib, re, sys
lib = pathlib.Path(sys.argv[1]); target = pathlib.Path(sys.argv[2])
readme = (lib / "README.md").read_text(encoding="utf-8")
version = re.search(r"^\| Version \| version ([^ (|]+)", readme, re.M).group(1)
source = re.search(r"^\| Source \| (\S+)", readme, re.M).group(1)
rule = "=" * 72
text = target.read_text(encoding="utf-8")
text += (f"\n{rule}\nlibsamplerate {version}, BSD-2-Clause (linked into the application only)\nSource: {source}\n{rule}\n\n"
         + (lib / "upstream" / "COPYING").read_text(encoding="utf-8", errors="replace").rstrip() + "\n")
target.write_text(text, encoding="utf-8")
PY
  cat > "$LIC/SOURCE.txt" <<'TXT'
Jack Convolver, macOS Edition

This program is free software, under the GNU General Public License, version 3.
The licence is in jconvolver-COPYING.txt.

Source code of this edition (build scripts, SwiftUI application and libraries): https://github.com/zinc75/jack-apps-collection-macos
jconvolver as published by Fons Adriaensen: https://kokkinizita.linuxaudio.org/linuxaudio/
The libraries linked statically into the programs are listed in THIRD-PARTY-LICENSES.txt.
TXT
else
  echo "      no ../build/licenses: run ../build_universal.sh first"
fi

echo "[5/5] Ad hoc signature"
if [ -d "$APP/Contents/Helpers" ]; then
  for program in "$APP/Contents/Helpers/"*; do codesign --force -s - "$program"; done
fi
codesign --force -s - "$APP"

echo "Built: $APP"
echo "Run:   open \"$APP\""
