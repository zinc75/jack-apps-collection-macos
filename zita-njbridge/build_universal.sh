#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Licence of the programs it builds (zita-njbridge).
# Builds zita-j2n and zita-n2j as universal binaries (arm64 + x86_64) from upstream/ and patches/, linked
# statically with zita-resampler. Only libjack stays dynamic, linked by its full path.
# The upstream Makefile is not used: it builds one architecture at a time with the flags of the host.
# The library must be built first: libs/zita-resampler/build_universal.sh, in <libs build dir>.
# Also writes the licence texts that go with the programs, in <output dir>/licenses.
# Usage: build_universal.sh [libs build dir] [output dir]
#        (defaults: libs/build, zita-njbridge/build)
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
[ -f "$UB_OUT/arm64/lib/libzita-resampler.a" ] || { echo "error: build libs/zita-resampler first (libs/zita-resampler/build_universal.sh)" >&2; exit 1; }

# Expose only JACK to the compiler: other libraries installed next to it must not be picked up.
jack=$UB_WORK/jack
mkdir -p "$jack/include" "$jack/lib"
ln -s "$jack_prefix/include/jack" "$jack/include/jack"
ln -s "$jack_prefix/lib/libjack.dylib" "$jack/lib/libjack.dylib"

j2n="zita-j2n netdata jacktx nettx pxthread lfqueue zsockets"
n2j="zita-n2j netdata jackrx netrx pxthread lfqueue zsockets"

for arch in $UB_ARCHS; do
  prefix=$UB_OUT/$arch
  dir=$UB_WORK/njb_$arch
  rm -rf "$dir"; cp -R "$UB_SRC" "$dir"
  ub_patch "$dir"
  mkdir -p "$UB_WORK/bin_$arch"
  ( cd "$dir/source"
    for f in $(echo "$j2n $n2j" | tr ' ' '\n' | sort -u); do
      ub_env "$arch" clang++ -arch "$arch" -O2 -Wall -Wno-deprecated-declarations -DVERSION=\"$version\" \
        -I"$prefix/include" -I"$jack/include" -c "$f.cc" -o "$f.o"
    done
    # shellcheck disable=SC2046
    ub_env "$arch" clang++ -arch "$arch" -o "$UB_WORK/bin_$arch/zita-j2n" $(for f in $j2n; do echo "$f.o"; done) \
      -L"$jack/lib" -ljack -lpthread -lm
    # shellcheck disable=SC2046
    ub_env "$arch" clang++ -arch "$arch" -o "$UB_WORK/bin_$arch/zita-n2j" $(for f in $n2j; do echo "$f.o"; done) \
      "$prefix/lib/libzita-resampler.a" -L"$jack/lib" -ljack -lpthread -lm )
done
for t in zita-j2n zita-n2j; do
  lipo -create "$UB_WORK/bin_arm64/$t" "$UB_WORK/bin_x86_64/$t" -output "$out/$t"
  strip -x "$out/$t"
  lipo -info "$out/$t"
done

# The GPL of zita-njbridge, the licence of the library linked statically into it, and where the source is.
python3 -I - "$here" "$out/licenses" <<'PY'
import pathlib, re, shutil, sys
tool = pathlib.Path(sys.argv[1]).resolve()
libs = tool.parent / "libs"
out = pathlib.Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
REPO = "https://github.com/zinc75/jack-apps-collection-macos"
UPSTREAM = "https://kokkinizita.linuxaudio.org/linuxaudio/"

shutil.copyfile(tool / "upstream" / "COPYING", out / "zita-njbridge-COPYING.txt")

rule = "=" * 72
readme = (libs / "zita-resampler" / "README.md").read_text(encoding="utf-8")
version = re.search(r"^\| Version \| version ([^ (|,]+)", readme, re.M).group(1)
source = re.search(r"^\| Source \| (\S+)", readme, re.M).group(1)
text = ("The zita-n2j program is linked statically with the library below. Its licence text follows.\n"
        "The source of the exact version used is at the address given, and in " + REPO + "\n"
        "(libs/zita-resampler/upstream/), with the script that builds it (libs/zita-resampler/build_universal.sh).\n"
        f"\n{rule}\nzita-resampler {version}, GPL-3.0-or-later\nSource: {source}\n{rule}\n\n"
        + (libs / "zita-resampler" / "upstream" / "COPYING").read_text(encoding="utf-8", errors="replace").rstrip() + "\n")
(out / "THIRD-PARTY-LICENSES.txt").write_text(text, encoding="utf-8")

(out / "SOURCE.txt").write_text(
    "zita-njbridge, macOS Edition\n\n"
    "This program is free software, under the GNU General Public License, version 3 or (at your option) any later version.\n"
    "The licence is in zita-njbridge-COPYING.txt.\n\n"
    f"Source code of this edition (build scripts and libraries): {REPO}\n"
    f"zita-njbridge as published by Fons Adriaensen: {UPSTREAM}\n"
    "The library linked statically into zita-n2j is listed in THIRD-PARTY-LICENSES.txt.\n", encoding="utf-8")
PY
echo "licence texts in $out/licenses"
