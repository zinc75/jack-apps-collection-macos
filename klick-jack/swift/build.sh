#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Licence of the program this interface drives (klick).
#
# Builds "Klick.app" of the collection: the core of Klick (the window, the engine) with the JACK backend added to CoreAudio.
#
#   ./build.sh            Release: universal (arm64 + x86_64), ad hoc signature
#   ./build.sh --debug    Debug: native architecture only, faster
#
# The bundle is assembled by the script of the core (../../klick/swiftui/build.sh), which takes its settings from the environment:
# this one only says what is different: the package, the output folder (klick-jack/build/Klick.app), the version of the
# edition, the strings of the JACK module and a notice about JACK. Needs ../build/libklickjack.a (engine/build_jack.sh) and what the
# core needs (klick/build_universal.sh, klick/engine/build_engine.sh). Signing with a Developer ID and the installer are not part of it.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
[ -f "$here/../build/libklickjack.a" ] || { echo "error: ../build/libklickjack.a is missing, run ../engine/build_jack.sh first" >&2; exit 1; }

export KLICK_PACKAGE_DIR="$here"
export KLICK_APP_NAME="Klick"
export KLICK_EXECUTABLE="Klick"
export KLICK_PRODUCT="KlickCollection"
export KLICK_BUNDLE_ID="io.github.zinc75.jackappscollection.klick"
export KLICK_OUT="$here/../build"
export KLICK_VERSION_DIR="$here"
export KLICK_HELPER="$here/../../klick/build/klick"
export KLICK_ASSETS="$here/Resources/Assets.xcassets"
export KLICK_EXTRA_CATALOGS="$here/Resources/Localizable.xcstrings"
export KLICK_NOTICE="$here/NOTICE.txt"
exec "$here/../../klick/swiftui/build.sh" "$@"
