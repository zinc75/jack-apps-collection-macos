#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Licence of the program it builds (rju-play, installed as jack_play).
# Builds jack_play as a universal binary (arm64 + x86_64) from upstream/ and patches/,
# linked statically with libsndfile and its codecs (FLAC, Ogg Vorbis, Opus, MP3) and with libsamplerate.
# Only libjack stays dynamic, linked by its full path.
# The upstream Makefile is not used: it builds the whole suite, and rju-play needs only a few of the
# r-common sources. The patches change cmd/rju-play.c.
# The libraries must be built first, with libs/<name>/build_universal.sh, in <libs build dir>.
# Usage: build_universal.sh [libs build dir] [output dir]
#        (defaults: libs/build, jack_play/build)
# Environment: JACK_PREFIX = where the JACK headers and libjack are installed (default /usr/local).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../libs/common.sh"
ub_setup "$here/upstream" "${1:-$here/../libs/build}"
out=${2:-$here/build}
mkdir -p "$out"; out=$(cd "$out" && pwd)
jack_prefix=${JACK_PREFIX:-/usr/local}

# Expose only JACK to the compiler: other libraries installed next to it must not be picked up.
jack=$UB_WORK/jack
mkdir -p "$jack/include" "$jack/lib"
ln -s "$jack_prefix/include/jack" "$jack/include/jack"
ln -s "$jack_prefix/lib/libjack.dylib" "$jack/lib/libjack.dylib"

# rju-play includes jack-client.c, jack-port.c, jack-transport.c and sf-sndfile.c itself (from the
# r-common submodule, which is part of upstream/cmd/r-common); the others are compiled separately.
common="file memory observe-signal ringbuffer ringbuffer-fd"

for arch in $UB_ARCHS; do
  prefix=$UB_OUT/$arch
  dir=$UB_WORK/jack_play_$arch
  rm -rf "$dir"; cp -R "$UB_SRC" "$dir"
  ub_patch "$dir"
  libs=$(ub_env "$arch" pkg-config --static --libs sndfile samplerate)
  cflags="-arch $arch -O2 -Wall -std=c11 -D_POSIX_C_SOURCE=200809 -I$prefix/include -I$jack/include"
  ( cd "$dir/cmd"
    srcs="rju-play.c"
    for c in $common; do srcs="$srcs r-common/c/$c.c"; done
    # shellcheck disable=SC2086
    ub_env "$arch" clang $cflags $srcs -o jack_play \
      -arch "$arch" -L"$prefix/lib" -L"$jack/lib" $libs -ljack -lpthread -lm )
  mkdir -p "$UB_WORK/bin_$arch"
  cp "$dir/cmd/jack_play" "$UB_WORK/bin_$arch/jack_play"
done

lipo -create "$UB_WORK"/bin_arm64/jack_play "$UB_WORK"/bin_x86_64/jack_play -output "$out/jack_play"
strip -x "$out/jack_play"
lipo -info "$out/jack_play"
