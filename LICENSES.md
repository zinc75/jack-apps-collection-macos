# Licences

Each tool keeps the licence of its upstream. A patch to a file is under the licence of that file. The licence is read from the files of the version kept here, not only from the project page.

| Component | Licence (from the files) | Notes |
|---|---|---|
| jack_capture 0.9.73+ | GPL-2.0-or-later | `COPYING` is the GPL v2; source headers: "or any later version" |
| libsndfile 1.2.2 | LGPL-2.1-or-later | `COPYING`, header of `src/sndfile.c` |
| libogg 1.3.6 | BSD-3-Clause | |
| libvorbis 1.3.7 | BSD-3-Clause | |
| FLAC 1.5.0 | BSD-3-Clause (libraries) | the `flac` and `metaflac` programs are GPL-2.0-or-later and are not built here |
| Opus 1.6.1 | BSD-3-Clause | |
| LAME 4.0 | LGPL-2.0-or-later | `COPYING` is the LGPL v2; header says "or any later version" |
| mpg123 1.33.7 | LGPL-2.1 | |
| liblo 0.36 | LGPL-2.1-or-later | `COPYING` is the LGPL v2.1; header says "any later version" |

## New code

- Everything derived from an existing tool (patches, build scripts, `swiftui/` front ends, ported engines) has the licence of that tool; scripts state it in an `SPDX-License-Identifier` line.
- Documentation: MIT (`LICENSES/MIT.txt`).
- Code that is not derived from a tool has a `LICENSE` file in its directory.
- `shared/`: Swift packages by Éric Bavu, under MIT (each has a `LICENSE` file), so that front ends of any licence can use them. A front end that uses them keeps the licence of its tool: MIT code can be included in GPL code, not the other way round.
- There is deliberately no `LICENSE` file at the root: it would suggest that one licence covers the whole repository.

## Combining

Code under GPL-2.0-or-later can be combined with GPL-3.0 code in a GPL-3.0 program. GPL-2.0-only code cannot, and must be checked before reuse. Programs of this repository are separate from JackMate (MIT): no GPL code is linked into JackMate; it only starts these tools as separate programs.
