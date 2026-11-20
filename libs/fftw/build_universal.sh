#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Licence of the library it builds (FFTW).
# Builds FFTW (single precision, libfftw3f) as a static universal library (arm64 + x86_64) from upstream/.
# NEON on arm64; SSE2, AVX and AVX2 on x86_64 (FFTW picks the codelets at run time). No Fortran, no threads, no wisdom programs
# needed by the callers (they are built and ignored).
# Usage: build_universal.sh [output dir]    (default: libs/build)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../common.sh"
ub_setup "$here/upstream" "${1:-$here/../build}"
for arch in $UB_ARCHS; do
  if [ "$arch" = x86_64 ]; then simd="--enable-sse2 --enable-avx --enable-avx2"; else simd="--enable-neon"; fi
  ub_autotools "$arch" --enable-single --disable-fortran --disable-doc $simd
done
ub_merge
