# Jack Play, SwiftUI front end

Building the Jack Play application from source. What the application does is described in [`../README.md`](../README.md).

Unofficial interface. `jack_play` is `rju-play` by Rohan Drape.

## Requirements

- macOS 15 or later.
- Xcode (full install, not only the Command Line Tools), for Swift 6 and `actool`. The scripts set `DEVELOPER_DIR` for themselves, so `xcode-select` is left as it is.
- JACK installed (`/usr/local/lib/libjack.dylib` or `/opt/homebrew/lib/libjack.dylib`) to run the application.

## Build

The application embeds a copy of the `jack_play` program, and links libsndfile statically for the waveform, so the libraries and the program are built first.

```
../../libs/<library>/build_universal.sh   # once: the static libraries (see ../../libs/)
../build_universal.sh                     # jack_play, universal, in ../build/
./build.sh                                # the application: build/Jack Play.app
```

`build.sh` produces a universal binary (arm64 and x86_64) signed ad hoc. Options:

```
./build.sh --debug    # native architecture only, with the debug aids
swift test            # unit tests of the logic
```

If `../build/jack_play` is missing, the application is still built, without the embedded program.

`swift test` needs Xcode for XCTest: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`. The tests that need a JACK server start one of their own (`jackd` with the dummy driver) and leave the server in use alone.

## Layout

- `Sources/JackPlayKit`: logic without any UI (the program and its messages, the file, the connections, the levels, the state of the player), unit tested.
- `Sources/JackPlay`: the SwiftUI application.
- `Sources/CSndfile`: libsndfile for the Swift code.
- `Tests`: unit and integration tests of `JackPlayKit`.
- `Resources`: `Info.plist` and `Localizable.xcstrings` (French, English, German, Italian, Spanish).
- `../../shared/WaveformKit` (MIT): the peaks and the drawing of the waveform.
- `../../shared/MatrixKit` (MIT): glass, badges and points of the outputs matrix, shared with the other tools.
- `../../shared/MeterKit` (MIT): level meters and scales.
- `../../shared/AppearanceKit` (MIT): dark, system or light look, and the accent.
- `../../shared/JackBridge` (MIT): the JACK client wrapper, which loads libjack by its full path, and the search of the application behind each client.

The application needs macOS 15. It is developed and tested on macOS 26, where it uses Liquid Glass; the look used on macOS 15 has not been tested on a real system.

The debug build reads a few environment variables (`JACKPLAY_*`) that drive the application without clicking, for screenshots and tests. They are compiled out of the release build.

## Licence

GPL-3.0, as `jack_play`.
