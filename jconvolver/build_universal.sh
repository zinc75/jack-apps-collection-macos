#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Licence of the programs it builds (jconvolver, fconvolver, makemulti).
# Builds the three programs as universal binaries (arm64 + x86_64) from upstream/ and patches/, linked statically with
# zita-convolver, FFTW, clthreads and libsndfile (and its codecs). Only libjack stays dynamic, linked by its full path,
# and only jconvolver uses it.
# The upstream Makefile is not used: it builds one architecture at a time with the flags of the host.
# The libraries must be built first, with libs/<name>/build_universal.sh, in <libs build dir>: fftw, zita-convolver,
# clthreads, and libsndfile with its codecs.
# Usage: build_universal.sh [libs build dir] [output dir]
#        (defaults: libs/build, jconvolver/build)
# Environment: JACK_PREFIX = where the JACK headers and libjack are installed (default /usr/local).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../libs/common.sh"
ub_setup "$here/upstream" "${1:-$here/../libs/build}"
out=${2:-$here/build}
mkdir -p "$out"; out=$(cd "$out" && pwd)
jack_prefix=${JACK_PREFIX:-/usr/local}
version=$(sed -n 's/^VERSION *= *//p' "$UB_SRC/source/Makefile")
[ -n "$version" ] || { echo "error: no VERSION in upstream/source/Makefile" >&2; exit 1; }
for lib in libfftw3f libzita-convolver libclthreads libsndfile; do
  [ -f "$UB_OUT/arm64/lib/$lib.a" ] || { echo "error: build the library of $lib first (libs/*/build_universal.sh)" >&2; exit 1; }
done

# Expose only JACK to the compiler: other libraries installed next to it must not be picked up.
jack=$UB_WORK/jack
mkdir -p "$jack/include" "$jack/lib"
ln -s "$jack_prefix/include/jack" "$jack/include/jack"
ln -s "$jack_prefix/lib/libjack.dylib" "$jack/lib/libjack.dylib"

jc="jconvolver config jconfig audiofile dither sstring jclient"
fc="fconvolver config fconfig audiofile dither sstring"
mm="makemulti audiofile dither"

for arch in $UB_ARCHS; do
  prefix=$UB_OUT/$arch
  dir=$UB_WORK/jconv_$arch
  rm -rf "$dir"; cp -R "$UB_SRC" "$dir"
  ub_patch "$dir"
  mkdir -p "$UB_WORK/bin_$arch"
  sndfile_libs=$(ub_env "$arch" pkg-config --static --libs sndfile)
  ( cd "$dir/source"
    for f in $(echo "$jc $fc $mm" | tr ' ' '\n' | sort -u); do
      ub_env "$arch" clang++ -arch "$arch" -O2 -Wall -Wno-deprecated-declarations -DVERSION=\"$version\" \
        -I"$prefix/include" -I"$jack/include" -c "$f.cc" -o "$f.o"
    done
    # shellcheck disable=SC2046,SC2086
    ub_env "$arch" clang++ -arch "$arch" -o "$UB_WORK/bin_$arch/jconvolver" $(for f in $jc; do echo "$f.o"; done) \
      "$prefix/lib/libzita-convolver.a" "$prefix/lib/libfftw3f.a" "$prefix/lib/libclthreads.a" \
      -L"$prefix/lib" $sndfile_libs -L"$jack/lib" -ljack -lpthread -lm
    # shellcheck disable=SC2046,SC2086
    ub_env "$arch" clang++ -arch "$arch" -o "$UB_WORK/bin_$arch/fconvolver" $(for f in $fc; do echo "$f.o"; done) \
      "$prefix/lib/libzita-convolver.a" "$prefix/lib/libfftw3f.a" \
      -L"$prefix/lib" $sndfile_libs -lpthread -lm
    # shellcheck disable=SC2046,SC2086
    ub_env "$arch" clang++ -arch "$arch" -o "$UB_WORK/bin_$arch/makemulti" $(for f in $mm; do echo "$f.o"; done) \
      -L"$prefix/lib" $sndfile_libs -lm )
done
for t in jconvolver fconvolver makemulti; do
  lipo -create "$UB_WORK/bin_arm64/$t" "$UB_WORK/bin_x86_64/$t" -output "$out/$t"
  strip -x "$out/$t"
  lipo -info "$out/$t"
done

# The licence of the programs as they are distributed, the licences of the libraries linked statically into them, and where the
# source is. jconvolver says "version 2 or any later version", zita-convolver "version 3 or any later version": the programs
# contain both, so they are distributed under version 3 of the GPL.
python3 -I - "$here" "$out/licenses" <<'PY'
import pathlib, re, shutil, sys
tool = pathlib.Path(sys.argv[1]).resolve()
libs = tool.parent / "libs"
out = pathlib.Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
REPO = "https://github.com/zinc75/jack-apps-collection-macos"
UPSTREAM = "https://kokkinizita.linuxaudio.org/linuxaudio/"

gpl3 = (libs / "zita-convolver" / "upstream" / "COPYING").read_text(encoding="utf-8", errors="replace").rstrip()
(out / "jconvolver-COPYING.txt").write_text(
    "jconvolver, fconvolver and makemulti are by Fons Adriaensen, under the GNU General Public License, version 2 or (at your\n"
    "option) any later version. They are linked with zita-convolver, which is under version 3 or any later version: the programs of\n"
    "this edition are distributed under version 3 of the GNU General Public License, whose text follows.\n\n"
    + "-" * 72 + "\n\n" + gpl3 + "\n", encoding="utf-8")

# (folder in libs/, name, licence, licence files)
LIBS = [
    ("zita-convolver", "zita-convolver", "GPL-3.0-or-later", ["COPYING"]),
    ("fftw", "FFTW", "GPL-2.0-or-later", ["COPYING"]),
    ("clthreads", "clthreads", "GPL-2.0-or-later (the source headers; COPYING is the LGPL 2.1)", ["COPYING"]),
    ("libsndfile", "libsndfile", "LGPL-2.1-or-later", ["COPYING"]),
    ("libogg", "libogg", "BSD-3-Clause", ["COPYING"]),
    ("libvorbis", "libvorbis", "BSD-3-Clause", ["COPYING"]),
    ("flac", "FLAC (libraries)", "BSD-3-Clause", ["COPYING.Xiph"]),
    ("opus", "Opus", "BSD-3-Clause", ["COPYING"]),
    ("lame", "LAME", "LGPL-2.0-or-later", ["COPYING"]),
    ("mpg123", "mpg123", "LGPL-2.1", ["COPYING"]),
]
rule = "=" * 72
parts = ["The programs are linked statically with the libraries below. Their licence texts follow.\n"
         "The source of the exact versions used is at the addresses given, and in " + REPO + "\n"
         "(libs/<name>/upstream/), with the scripts that build them (libs/<name>/build_universal.sh).\n"]
for folder, name, licence, files in LIBS:
    readme = (libs / folder / "README.md").read_text(encoding="utf-8")
    version = re.search(r"^\| Version \| version ([^ (|,]+)", readme, re.M).group(1)
    source = re.search(r"^\| Source \| (\S+)", readme, re.M).group(1)
    parts.append(f"\n{rule}\n{name} {version}, {licence}\nSource: {source}\n{rule}\n")
    for f in files:
        parts.append("\n" + (libs / folder / "upstream" / f).read_text(encoding="utf-8", errors="replace").rstrip() + "\n")
(out / "THIRD-PARTY-LICENSES.txt").write_text("".join(parts), encoding="utf-8")

(out / "SOURCE.txt").write_text(
    "jconvolver, fconvolver and makemulti, macOS Edition\n\n"
    "These programs are free software, under the GNU General Public License, version 3 (see jconvolver-COPYING.txt for why).\n\n"
    f"Source code of this edition (patches, build scripts and libraries): {REPO}\n"
    f"jconvolver as published by Fons Adriaensen: {UPSTREAM}\n"
    "The libraries linked statically into the programs are listed in THIRD-PARTY-LICENSES.txt.\n", encoding="utf-8")
PY
echo "licence texts in $out/licenses"
