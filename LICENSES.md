# Licences

Each tool keeps the licence of its upstream. A patch to a file is under the licence of that file. The licence is read from the files of the version kept here, not only from the project page.

| Component | Licence (from the files) | Notes |
|---|---|---|
| jack_capture 0.9.73+ | GPL-2.0-or-later | `COPYING` is the GPL v2; source headers: "or any later version" |

## New code

- Everything derived from an existing tool (patches, build scripts, `swiftui/` front ends, ported engines) has the licence of that tool; scripts state it in an `SPDX-License-Identifier` line.
- Documentation: MIT (`LICENSES/MIT.txt`).
- Code that is not derived from a tool has a `LICENSE` file in its directory.
- There is deliberately no `LICENSE` file at the root: it would suggest that one licence covers the whole repository.

## Combining

Code under GPL-2.0-or-later can be combined with GPL-3.0 code in a GPL-3.0 program. GPL-2.0-only code cannot, and must be checked before reuse. Programs of this repository are separate from JackMate (MIT): no GPL code is linked into JackMate; it only starts these tools as separate programs.
