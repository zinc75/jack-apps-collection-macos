# zita-njbridge

JACK clients (`zita-j2n` sender, `zita-n2j` receiver) that carry multichannel audio over an IP network with adaptive resampling (UDP or multicast).

## Upstream

| | |
|---|---|
| Project | zita-njbridge |
| Author | Fons Adriaensen |
| Source | https://kokkinizita.linuxaudio.org/linuxaudio/downloads/zita-njbridge-0.4.8.tar.bz2 |
| Version | version 0.4.8 (archive downloaded 2026-10-31); no git history upstream. |
| Archive | `zita-njbridge-0.4.8.tar.bz2` (not kept; download it again and compare the checksum) |
| SHA-256 | `101176a0bd407cab7bffd326e8d6886c1b65b212bc33f2efb97b03f926c47907` |
| Copy here | `upstream/` = the archive extracted with `tar -xf … --strip-components=1`, **unmodified** |

## Licence

GPL-3.0-or-later (`COPYING` is the GPL v3; source headers: "version 3 … or any later version").

Dependencies: JACK, zita-resampler (`libs/zita-resampler`).

## Install

Download `zita-njbridge-0.4.8-macOS.pkg` from the [Releases](https://github.com/zinc75/jack-apps-collection-macos/releases) page and open it. The package is signed and notarized by Apple. It installs `zita-j2n` and `zita-n2j` in `/usr/local/bin`, with their manual pages. JACK has to be installed.

## Use

Start the receiver on one Mac and the sender on the other, both with the IP address of the receiver and a port:

```
zita-n2j 192.168.1.20 9999
zita-j2n 192.168.1.20 9999
```

Then connect the JACK ports (`zita-j2n:in_1` ... and `zita-n2j:out_1` ...). `zita-n2j --info` prints the state of the link, and `man zita-njbridge` has the rest.

## State on macOS

Builds without any change to the sources, as universal binaries (arm64 and x86_64).

Tested between two Macs over direct gigabit Ethernet. With a JACK period of 256 the defaults are enough; with 1024, use `zita-n2j --buff 30` or more. Resampling between 48 kHz and 44.1 kHz keeps pitch and level exact. Other periods were not tested.

macOS has no `mlockall`, so both programs print "memory lock failed" at start. It is harmless.

## Layout

- `upstream/`: the original sources, never edited (changes go to `patches/` or to new files).
- `build_universal.sh`: builds the two universal programs and writes their licence texts (needs `libs/zita-resampler` built first).
- `VERSION`, `REVISION`: the upstream version and the number of this macOS edition.
