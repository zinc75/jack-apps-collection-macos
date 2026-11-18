# zita-resampler

C++ library for sample-rate conversion (also the engine of zita-njbridge and ebumeter's true-peak).

## Upstream

| | |
|---|---|
| Project | zita-resampler |
| Author | Fons Adriaensen |
| Source | https://kokkinizita.linuxaudio.org/linuxaudio/downloads/zita-resampler-1.11.2.tar.xz |
| Version | version 1.11.2, released 2023-08-30 (archive downloaded 2026-10-31); no git history upstream. Documentation in `upstream/docs/`. |
| Archive | `zita-resampler-1.11.2.tar.xz` (not kept; download it again and compare the checksum) |
| SHA-256 | `aa5c54e696069af26f3f1fed4a963113cc1237cddfd57ae5842abcb1acd5492c` |
| Copy here | `upstream/` = the archive extracted with `tar -xf … --strip-components=1`, **unmodified** |

## Licence

GPL-3.0-or-later (`COPYING` is the GPL v3; source headers: "version 3 … or (at your option) any later version").

Dependencies: none.

## State on macOS

- Since 1.11.2 there is optimised ARM64 NEON code (contributed by Nicolas Belin): enable `-DENABLE_NEON` instead of `-DENABLE_SSE2` when compiling for arm64.
- The upstream `Makefile` builds a Linux `.so` (`-Wl,-soname`, `-march=native`): `build_universal.sh` builds a static library per architecture and joins them with `lipo` instead (SSE2 on x86_64, NEON on arm64).


## Layout

- `upstream/`: the original sources, never edited (changes go to `patches/` or to new files).
- `patches/`: changes to the upstream sources, as unified diffs that apply with `git apply` from the `upstream/` directory.
- `build_universal.sh`: builds the static universal library.
