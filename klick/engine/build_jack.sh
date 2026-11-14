#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Licence of the program it builds (klick).
# Builds libklickjack.a, the JACK backend of the klick engine (libjack loaded at run time, see jack_api.hh) with the C interface of
# klick_jack.h, as one universal static library (arm64 + x86_64), and the test of the backend for each architecture.
# klick-tempo/klick/build_universal.sh and klick-tempo/klick/engine/build_engine.sh must have been run first, with this repository's
# libs/build as their libs build folder (the klick headers come from a copy of klick-tempo/klick/upstream with its patches applied,
# the test links klick-tempo/klick/build/libklickengine.a). The JACK headers come from
# $JACK_PREFIX/include (types only: libjack is not linked).
# Usage: build_jack.sh [libs build dir] [output dir]     (defaults: libs/build, klick/build)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
klick=$here/../klick-tempo/klick
. "$here/../../libs/common.sh"
ub_setup "$klick/upstream" "${1:-$here/../../libs/build}"
out=${2:-$here/../build}
mkdir -p "$out/tests"; out=$(cd "$out" && pwd)
jack_prefix=${JACK_PREFIX:-/usr/local}
boost=$(cd "$here/../../libs/boost/upstream" && pwd)
api_engine=$(cd "$klick/swiftui/Sources/CKlickEngine/include" && pwd)
api_jack=$(cd "$here/../swift/Sources/CKlickJack/include" && pwd)
engine_lib=$klick/build/libklickengine.a
[ -f "$engine_lib" ] || { echo "error: $engine_lib is missing, run klick-tempo/klick/engine/build_engine.sh first" >&2; exit 1; }
for p in "$klick"/patches/*.patch; do
  [ "$p" -nt "$engine_lib" ] && { echo "error: $(basename "$p") is newer than $engine_lib, rebuild the klick library first" >&2; exit 1; }
done

src=$UB_WORK/klick
cp -R "$UB_SRC" "$src"
ub_patch "$src"

for arch in $UB_ARCHS; do
  prefix=$UB_OUT/$arch
  work=$UB_WORK/$arch; mkdir -p "$work"
  objects=()
  for f in jack_api audio_interface_jack_dl transport_driver klick_jack; do
    cc=$here/$f.cc; [ -f "$cc" ] || cc=$here/$f.cpp
    ub_env "$arch" clang++ -arch "$arch" -std=c++11 -O2 -Wall -Wextra -DNDEBUG \
      -I"$here" -I"$klick/engine" -I"$api_engine" -I"$api_jack" -I"$src/src" -I"$jack_prefix/include" -I"$boost" -I"$prefix/include" \
      -c "$cc" -o "$work/$f.o"
    objects+=("$work/$f.o")
  done
  libtool -static -o "$work/libklickjack.a" "${objects[@]}"
  # The test links the library like an application would: the JACK backend first, then the engine of klick.
  thin=$work/libklickengine_thin.a
  lipo -thin "$arch" "$engine_lib" -output "$thin"
  ub_env "$arch" clang++ -arch "$arch" -std=c++11 -O2 -Wall -Wextra -DNDEBUG \
    -I"$here" -I"$jack_prefix/include" -I"$api_engine" -I"$api_jack" "$here/tests/jack_backend_test.cc" "$work/libklickjack.a" "$thin" \
    -framework AudioToolbox -framework CoreAudio -framework CoreFoundation -framework Accelerate -o "$out/tests/jack_backend_test_$arch"
  echo "built $out/tests/jack_backend_test_$arch"
done

lipo -create "$UB_WORK"/arm64/libklickjack.a "$UB_WORK"/x86_64/libklickjack.a -output "$out/libklickjack.a"
lipo -info "$out/libklickjack.a"
otool -L "$out/tests/jack_backend_test_arm64" | grep -i "libjack" && echo "WARNING: linked against libjack" || echo "not linked against libjack"
