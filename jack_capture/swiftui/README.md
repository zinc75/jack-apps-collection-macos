# Jack Capture, SwiftUI front end

Building the Jack Capture application from source. What the application does is described in [`../README.md`](../README.md).

Unofficial interface. `jack_capture` is by Kjetil Matheussen.

## Requirements

- macOS 15 or later.
- Xcode (full install, not only the Command Line Tools), for Swift 6 and `actool`. The scripts set `DEVELOPER_DIR` for themselves, so `xcode-select` is left as it is.
- JACK installed (`/usr/local/lib/libjack.dylib` or `/opt/homebrew/lib/libjack.dylib`) to run the application.

## Build

The application embeds a copy of the `jack_capture` program, so that program is built first.

```
../../libs/<library>/build_universal.sh   # once: the static libraries (see ../../libs/)
../build_universal.sh                     # jack_capture, universal, in ../build/
./build.sh                                # the application: build/Jack Capture.app
```

`build.sh` produces a universal binary (arm64 and x86_64) signed ad hoc. Options:

```
./build.sh --debug    # native architecture only, with the debug aids
swift test            # unit tests of the logic
```

If `../build/jack_capture` is missing, the application is still built, without the embedded program.

`swift test` needs Xcode for XCTest: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

## Layout

- `Sources/JackCaptureKit`: logic without any UI (recorder state, command line, source checks, level tracking), unit tested.
- `Sources/JackCapture`: the SwiftUI application.
- `Tests`: unit tests of `JackCaptureKit`.
- `Resources`: `Info.plist`, `Localizable.xcstrings` (French, English, German, Italian, Spanish) and the application icon.
- `../../shared/MatrixKit` (MIT): the source matrix (glass, badges, points, frozen panes), shared with the other tools.
- `../../shared/MeterKit` (MIT): level meters and scales.
- `../../shared/JackBridge` (MIT): the JACK client wrapper, which loads libjack by its full path.

The application needs macOS 15. It is developed and tested on macOS 26, where it uses Liquid Glass; the look used on macOS 15 has not been tested on a real system.

The debug build reads a few environment variables (`JACKCAPTURE_*`) that drive the application without clicking, for screenshots and tests. They are compiled out of the release build.

## Licence

GPL-2.0-or-later, as `jack_capture`.
