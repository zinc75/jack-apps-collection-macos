#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Licence of the library it builds (zita-convolver).
# Builds zita-convolver as a static universal library (arm64 + x86_64) from upstream/. Needs libs/fftw built first
# (libfftw3f in the same output directory).
# The upstream Makefile makes a Linux shared library (-Wl,-soname, -march=native, ldconfig): it is not used. The vector mode
# uses the GCC vector extensions, which clang accepts: SSE on x86_64, NEON on arm64.
# Usage: build_universal.sh [output dir]    (default: libs/build)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../common.sh"
ub_setup "$here/upstream" "${1:-$here/../build}"

for arch in $UB_ARCHS; do
  [ -f "$UB_OUT/$arch/include/fftw3.h" ] || { echo "error: libs/fftw is not built in $UB_OUT/$arch (run libs/fftw/build_universal.sh first)" >&2; exit 1; }
  dir=$UB_WORK/$arch
  rm -rf "$dir"; cp -R "$UB_SRC" "$dir"
  ub_patch "$dir"
  prefix=$UB_OUT/$arch
  mkdir -p "$prefix/lib" "$prefix/include"
  ( cd "$dir/source"
    ub_env "$arch" clang++ -arch "$arch" -O2 -fPIC -Wall -ffast-math -funroll-loops -D_REENTRANT -D_POSIX_PTHREAD_SEMANTICS \
      -DENABLE_VECTOR_MODE -I. -I"$prefix/include" -c zita-convolver.cc -o zita-convolver.o
    rm -f "$prefix/lib/libzita-convolver.a"
    ar rcs "$prefix/lib/libzita-convolver.a" zita-convolver.o
    ranlib "$prefix/lib/libzita-convolver.a"
    cp zita-convolver.h "$prefix/include/" )
done
ub_merge
