# zita-convolver

C++ library for real-time partitioned convolution (engine of jconvolver).

## Upstream

| | |
|---|---|
| Project | zita-convolver |
| Author | Fons Adriaensen |
| Source | https://kokkinizita.linuxaudio.org/linuxaudio/downloads/zita-convolver-4.0.3.tar.bz2 |
| Version | version 4.0.3 (archive downloaded 2026-10-31); no git history upstream. |
| Archive | `zita-convolver-4.0.3.tar.bz2`, attached to the release `4.0.3` of the repository named below |
| SHA-256 | `9aa11484fb30b4e6ef00c8a3281eebcfad9221e3937b1beb5fe21b748d89325f` |
| Copy here | `upstream/` = a Git submodule of [zinc75/zita-convolver-releases](https://github.com/zinc75/zita-convolver-releases), at tag `4.0.3` (commit `7b488aa75794f88ff1bb6941c07719cda1205cbe`): the files of the archive above, **unmodified** (clone with `--recurse-submodules`) |

That repository holds release snapshots, one commit per release; it is not a mirror, because Fons Adriaensen publishes release archives only and has no Git repository.

## Licence

GPL-3.0-or-later (`COPYING` is the GPL v3; source headers: "version 3 … or (at your option) any later version").

Dependencies: FFTW (`fftw3f`), pthreads.

## State on macOS

- The sources compile on macOS, as a universal static library (arm64 and x86_64): `build_universal.sh`, after the library of FFTW (`fftw3f`) is built in the same output folder. `zita-convolver.h` already contains an `__APPLE__` emulation of `sem_t` (mutex + condition variable), and the "vector mode" uses GCC vector extensions, which clang accepts on arm64. The `Makefile` builds a Linux `.so` and is not used here.
- One patch (`patches/0001-thread-init-hook.patch`) adds `Convproc::set_thread_init (fn, arg)`: an optional function, called at the start of each computation thread, in that thread. Without it nothing changes. On macOS the `SCHED_FIFO` attributes that `start_process ()` gives to these threads leave them in the time sharing band, because the policy is taken from the JACK thread, which is not in `SCHED_FIFO` there. `jconvolver` uses the hook to ask JACK for the time constraint that it gives to its own threads. With 24 or 48 busy processes on the Mac, `jconvolver` ran 64 convolutions of 4 seconds without a late cycle, where it stopped with "CPU overload" without the hook.

- A second patch (`patches/0002-128-channels.patch`) raises the limit of the convolver from 64 to 128 inputs and outputs (`MAXINP` and `MAXOUT`). They are constants of the class, so the size of `Convproc` changes: it is meant for a library linked statically, as here. A dense decoder of 100 inputs and 64 outputs (6400 filters of 512 samples) runs at about half of one core, with no late cycle at a JACK period of 256 frames.

## Layout

- `upstream/`: the original sources, never edited (changes go to `patches/` or to new files).
- `patches/`: changes to the upstream sources, as unified diffs that apply with `git apply` from the `upstream/` directory.
- `build_universal.sh`: builds the static universal library.
