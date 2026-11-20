# clthreads

Small C++ library of threads, semaphores and inter-thread messages (used by Aliki, jconvolver, jaaa, ebumeter…).

## Upstream

| | |
|---|---|
| Project | clthreads |
| Author | Fons Adriaensen |
| Source | https://kokkinizita.linuxaudio.org/linuxaudio/downloads/clthreads-2.4.2.tar.bz2 |
| Version | version 2.4.2 (archive downloaded 2026-10-31); no git history upstream. |
| Archive | `clthreads-2.4.2.tar.bz2`, attached to the release `2.4.2` of the repository named below |
| SHA-256 | `c659b14c0c4055c44432cb83060b95d30ae0c1ecc6f50d73968e239c100f7a31` |
| Copy here | `upstream/` = a Git submodule of [zinc75/clthreads-releases](https://github.com/zinc75/clthreads-releases), at tag `2.4.2` (commit `2a32c270fbfc7b942cd1de38f8f6a83bfa79cd39`): the files of the archive above, **unmodified** (clone with `--recurse-submodules`) |

That repository holds release snapshots, one commit per release; it is not a mirror, because Fons Adriaensen publishes release archives only and has no Git repository.

## Licence

**Inconsistent upstream**: `COPYING` is the LGPL v2.1, but the source headers (e.g. `clthreads.h`) say GPL "version 2 … or later". To be clarified with the author.

Dependencies: pthreads.

## State on macOS

- The sources compile on macOS as they are, as a universal static library (arm64 and x86_64): `build_universal.sh`.
- `P_sema` (`clthreads.h`) exists only on Linux (`#ifdef __linux__`), and nothing in clthreads or in jconvolver uses it. A program that does would need an implementation without unnamed POSIX semaphores, which macOS does not support (`sem_init` fails): the `__APPLE__` code in `zita-convolver.h` shows the author's approach.
- The `Makefile` builds a Linux `.so` (`-soname`, `ldconfig`, `-march=native`) and is not used here.


## Layout

- `upstream/`: the original sources, never edited (changes go to `patches/` or to new files).
- `patches/`: changes to the upstream sources, as unified diffs that apply with `git apply` from the `upstream/` directory.
- `build_universal.sh`: builds the static universal library.
