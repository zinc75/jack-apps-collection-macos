#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Licence of the library it builds (clthreads: the headers of the sources say GPL 2 or later).
# Builds clthreads as a static universal library (arm64 + x86_64) from upstream/.
# The upstream Makefile makes a Linux shared library (-Wl,-soname, -march=native, ldconfig): it is not used.
# Usage: build_universal.sh [output dir]    (default: libs/build)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../common.sh"
ub_setup "$here/upstream" "${1:-$here/../build}"
version=$(sed -n 's/^MAJVERS = \(.*\)/\1/p' "$UB_SRC/source/Makefile").$(sed -n 's/^MINVERS = \(.*\)/\1/p' "$UB_SRC/source/Makefile")

for arch in $UB_ARCHS; do
  dir=$UB_WORK/$arch
  rm -rf "$dir"; cp -R "$UB_SRC" "$dir"
  ub_patch "$dir"
  prefix=$UB_OUT/$arch
  mkdir -p "$prefix/lib" "$prefix/include"
  ( cd "$dir/source"
    objs=""
    for f in p_thread a_thread itc_mesg itc_ip1q itc_ctrl textmsg; do
      ub_env "$arch" clang++ -arch "$arch" -O2 -fPIC -Wall -D_REENTRANT -D_POSIX_PTHREAD_SEMANTICS "-DVERSION=\"$version\"" -I. -c "$f.cc" -o "$f.o"
      objs="$objs $f.o"
    done
    rm -f "$prefix/lib/libclthreads.a"
    ar rcs "$prefix/lib/libclthreads.a" $objs
    ranlib "$prefix/lib/libclthreads.a"
    cp clthreads.h "$prefix/include/" )
done
ub_merge
