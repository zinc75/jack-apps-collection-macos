# Jack Convolver, SwiftUI front end

Building the Jack Convolver application from source. What the application does is described in [`../README.md`](../README.md).

Unofficial interface. `jconvolver` and `fconvolver` are by Fons Adriaensen.

## Requirements

- macOS 15 or later.
- Xcode (full install, not only the Command Line Tools), for Swift 6 and `actool`. The scripts set `DEVELOPER_DIR` for themselves, so `xcode-select` is left as it is.
- JACK installed (`/usr/local/lib/libjack.dylib` or `/opt/homebrew/lib/libjack.dylib`) to run the engine.

## Build

The application embeds a copy of `jconvolver` and `fconvolver`, and links libsndfile and libsamplerate statically, so the libraries and the programs are built first.

```
../../libs/<library>/build_universal.sh   # once: the static libraries (see ../../libs/)
../build_universal.sh                     # jconvolver, fconvolver and makemulti, universal, in ../build/
./build.sh                                # the application: build/Jack Convolver.app
```

`build.sh` produces a universal binary (arm64 and x86_64) signed ad hoc. Options:

```
./build.sh --debug    # native architecture only, with the debug aids
swift test            # unit tests of the logic
```

If `../build/jconvolver` or `../build/fconvolver` is missing, the application is still built, without the embedded programs.

`swift test` needs Xcode for XCTest: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

## Layout

- `Sources/JConvolverKit`: logic without any UI (the configuration files, what the programs print, the command lines, the engine process, the analysis of an impulse response, the problems of a configuration, the export), unit tested.
- `Sources/JackConvolver`: the SwiftUI application.
- `Sources/CJConvolverPty`, `Sources/CSamplerate`: a small C layer to run a program in a pseudo-terminal, and libsamplerate.
- `Tests`: unit tests of `JConvolverKit`.
- `Resources`: `Info.plist`, `Localizable.xcstrings` (French, English, German, Italian, Spanish) and the icon.
- `../../shared/PlotKit` (MIT): the plots of waveform, spectrum and phase.
- `../../shared/SoundFileKit` (MIT): the sound files, read with libsndfile (linked statically with its codecs).
- `../../shared/WaveformKit`, `MatrixKit`, `AppearanceKit`, `SessionKit` (MIT): the waveform, the glass and badges of the matrix, the look and the accent, the sessions in windows and in the menu bar.
- `../../shared/JackBridge` (MIT): the JACK client wrapper, which loads libjack by its full path.

The application needs macOS 15. It is developed and tested on macOS 26, where it uses Liquid Glass; the look used on macOS 15 has not been tested on a real system.

The debug build reads a few environment variables (`JACKCONVOLVER_*`) that drive the application without clicking, for screenshots and tests. They are compiled out of the release build.

## Licence

GPL-3.0, as the programs.
