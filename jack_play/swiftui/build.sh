#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Licence of the program this interface drives (jack_play, from rju-play).
#
# Builds "Jack Play.app": the SwiftUI interface of jack_play.
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

APP_NAME="Jack Play"
EXECUTABLE="JackPlay"
BUNDLE_ID="io.github.zinc75.jackappscollection.jackplay"
VERSION=$(cat VERSION 2>/dev/null || echo "0.0.0")
# VERSION is the version of rju-play; REVISION counts the releases of the macOS edition for that version.
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

echo "[4/5] Icon, helper and licences"
if [ -d Resources/Assets.xcassets ]; then
  tmp=$(mktemp -d)
  xcrun actool Resources/Assets.xcassets --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 15.0 --app-icon AppIcon --output-partial-info-plist "$tmp/partial.plist" >/dev/null
  rm -rf "$tmp"
else
  echo "      no Assets.xcassets yet: the application has no icon"
fi
HELPER="$here/../build/jack_play"
if [ -x "$HELPER" ]; then
  cp "$HELPER" "$APP/Contents/Helpers/jack_play"
  echo "      jack_play copied to Contents/Helpers"
else
  rmdir "$APP/Contents/Helpers"
  echo "      no ../build/jack_play: run ../build_universal.sh first to embed the program"
fi

echo "      licence texts"
# The GPL of jack_play, the licences of the libraries linked statically into it, and where the source is.
python3 -I - "$here/.." "$APP/Contents/Resources/Licenses" <<'PY'
import pathlib, re, shutil, sys
tool = pathlib.Path(sys.argv[1]).resolve()
libs = tool.parent / "libs"
out = pathlib.Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
REPO = "https://github.com/zinc75/jack-apps-collection-macos"
UPSTREAM = "https://github.com/rd--/rju"

shutil.copyfile(tool / "COPYING", out / "jack_play-COPYING.txt")

# (folder in libs/, name, licence, licence files)
LIBS = [
    ("libsndfile", "libsndfile", "LGPL-2.1-or-later", ["COPYING"]),
    ("libogg", "libogg", "BSD-3-Clause", ["COPYING"]),
    ("libvorbis", "libvorbis", "BSD-3-Clause", ["COPYING"]),
    ("flac", "FLAC (libraries)", "BSD-3-Clause", ["COPYING.Xiph"]),
    ("opus", "Opus", "BSD-3-Clause", ["COPYING"]),
    ("lame", "LAME", "LGPL-2.0-or-later", ["COPYING"]),
    ("mpg123", "mpg123", "LGPL-2.1", ["COPYING"]),
    ("libsamplerate", "libsamplerate", "BSD-2-Clause", ["COPYING"]),
]
rule = "=" * 72
parts = ["The jack_play program is linked statically with the libraries below. Their licence texts follow.\n"
         "The source of the exact versions used is at the addresses given, and in " + REPO + "\n"
         "(libs/<name>/upstream/), with the scripts that build them (libs/<name>/build_universal.sh).\n"]
for folder, name, licence, files in LIBS:
    readme = (libs / folder / "README.md").read_text(encoding="utf-8")
    version = re.search(r"^\| Version \| version ([^ (|]+)", readme, re.M).group(1)
    source = re.search(r"^\| Source \| (\S+)", readme, re.M).group(1)
    parts.append(f"\n{rule}\n{name} {version}, {licence}\nSource: {source}\n{rule}\n")
    for f in files:
        parts.append("\n" + (libs / folder / "upstream" / f).read_text(encoding="utf-8", errors="replace").rstrip() + "\n")
(out / "THIRD-PARTY-LICENSES.txt").write_text("".join(parts), encoding="utf-8")

(out / "SOURCE.txt").write_text(
    "Jack Play, macOS Edition\n\n"
    "This program is free software, under the GNU General Public License, version 3.\n"
    "The licence is in jack_play-COPYING.txt.\n\n"
    f"Source code of this edition (patches, build scripts, SwiftUI application and libraries): {REPO}\n"
    f"rju-play as published by Rohan Drape: {UPSTREAM}\n"
    "The libraries linked statically into the program are listed in THIRD-PARTY-LICENSES.txt.\n", encoding="utf-8")
PY

echo "[5/5] Ad hoc signature"
[ -d "$APP/Contents/Helpers" ] && codesign --force -s - "$APP/Contents/Helpers/jack_play"
codesign --force -s - "$APP"

echo "Built: $APP"
echo "Run:   open \"$APP\""
