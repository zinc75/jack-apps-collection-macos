#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Licence of the library it builds (zita-resampler).
# Builds zita-resampler as a static universal library (arm64 + x86_64) from upstream/.
# The upstream Makefile makes a Linux shared library (-Wl,-soname, -march=native): it is not used. The SIMD code is
# chosen per architecture: SSE2 on x86_64, the NEON code added in 1.11.0 on arm64.
# Usage: build_universal.sh [output dir]    (default: libs/build)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../common.sh"
ub_setup "$here/upstream" "${1:-$here/../build}"

for arch in $UB_ARCHS; do
  if [ "$arch" = x86_64 ]; then simd=-DENABLE_SSE2; else simd=-DENABLE_NEON; fi
  dir=$UB_WORK/$arch
  rm -rf "$dir"; cp -R "$UB_SRC" "$dir"
  ub_patch "$dir"
  prefix=$UB_OUT/$arch
  mkdir -p "$prefix/lib" "$prefix/include"
  ( cd "$dir/source"
    for f in resampler vresampler resampler-table cresampler; do
      ub_env "$arch" clang++ -arch "$arch" -O2 -fPIC -ffast-math -D_REENTRANT -D_POSIX_PTHREAD_SEMANTICS $simd -I. -c "$f.cc" -o "$f.o"
    done
    rm -f "$prefix/lib/libzita-resampler.a"
    ar rcs "$prefix/lib/libzita-resampler.a" resampler.o vresampler.o resampler-table.o cresampler.o
    ranlib "$prefix/lib/libzita-resampler.a"
    rm -rf "$prefix/include/zita-resampler"
    mkdir -p "$prefix/include/zita-resampler"
    cp zita-resampler/*.h "$prefix/include/zita-resampler/" )
done
ub_merge
