# jack_play

Sound file player for JACK. This is `rju-play` 0.19 by Rohan Drape, built for macOS and installed as `jack_play`. It reads any file that libsndfile can open, resamples it with libsamplerate when its rate differs from the JACK server, and writes one JACK output port per channel of the file. With `-t` it follows the JACK transport, with `-l` it loops the file without a gap.

```
jack_play [options] sound-file...
```

The default JACK client name is `jack_play`, so the ports are `jack_play-<pid>:out_1`, `out_2`, and so on.

## Changes compared with upstream

**CLI.** The program is upstream's, with three small patches:

- The end of the file is played in full. Upstream closed the JACK client as soon as the last block had been read from disk, which cut the end of every file by the size of the ring buffer (about 85 ms with the default `-b`, more with a larger one).
- In transport mode, a start or a locate empties the ring buffer. Upstream played the audio read before the seek first, so after a start from the beginning the first block of the file was heard twice.
- The default client name is `jack_play` instead of `rju-play`.

Nothing else changes. It is a universal binary (arm64 and x86_64), linked statically with libsndfile (and its FLAC, Ogg Vorbis, Opus and MP3 codecs) and libsamplerate; only libjack stays dynamic.

## Build

The libraries are built first, from the root of the repository (see `libs/`), then:

```
jack_play/build_universal.sh
```

The result is `jack_play/build/jack_play`. `upstream/` is never modified: the script copies it, applies `patches/` and builds the copy. The upstream `Makefile` is not used, because it builds the whole suite.

## State on macOS

It builds and plays on Apple Silicon and, under Rosetta, as x86_64. Files are played to their exact length with any ring buffer size, and `-t` starts, stops and moves with the JACK transport.

## Patches

| Patch | |
|---|---|
| `0001-play-the-end-of-the-file.patch` | The end of the file is no longer cut. |
| `0002-empty-the-ring-buffer-on-seek.patch` | A transport seek no longer replays buffered audio. |
| `0003-default-client-name-jack_play.patch` | Default client name `jack_play`. Specific to this edition. |

## Upstream

| | |
|---|---|
| Project | rju (`rju-play`) |
| Author | Rohan Drape |
| Source | https://gitlab.com/rd--/rju (mirror: https://github.com/rd--/rju) |
| Version | tag `0.19` (2021-06-16) plus 19 commits, git `master` at commit `38a59ccc337367c2817b4b7e22e005a816f1fe9a` (2026-09-26) |
| Copy here | `upstream/` = a `git clone --recurse-submodules` of that commit with the `.git` files removed, **unmodified** |

The `cmd/r-common` folder is a submodule, `r-common` by the same author (https://gitlab.com/rd--/r-common), at commit `3b29186d24c5110e00ce80ab2fe9b5e79f835ff1` (2023-12-09).

## Licence

GPL-3.0 (`COPYING`). `rju.cabal` declares `GPL-3.0-only`; the sources say "gpl" without a version number.

## Layout

| | |
|---|---|
| `upstream/` | `rju` sources, with `r-common`, as published by Rohan Drape |
| `patches/` | changes for macOS, unified diffs against `upstream/` |
| `build_universal.sh` | builds the universal binary |
| `COPYING` | GPL v3 |
