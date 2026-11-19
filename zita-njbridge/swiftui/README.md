# Zita Network Bridge, SwiftUI front end

Building the Zita Network Bridge application from source. What the application does is described in [`../README.md`](../README.md).

Unofficial interface. `zita-j2n` and `zita-n2j` are `zita-njbridge` by Fons Adriaensen.

## Requirements

- macOS 15 or later.
- Xcode (full install, not only the Command Line Tools), for Swift 6 and `actool`. The scripts set `DEVELOPER_DIR` for themselves, so `xcode-select` is left as it is.
- JACK installed (`/usr/local/lib/libjack.dylib` or `/opt/homebrew/lib/libjack.dylib`) to run the application.

## Build

The application embeds a copy of the two programs, so the library they link and the programs are built first.

```
../../libs/zita-resampler/build_universal.sh   # once: the static library
../build_universal.sh                          # zita-j2n and zita-n2j, universal, in ../build/
./build.sh                                     # the application: build/Zita Network Bridge.app
```

`build.sh` produces a universal binary (arm64 and x86_64) signed ad hoc. Options:

```
./build.sh --debug    # native architecture only, with the debug aids
swift test            # unit tests of the logic
```

If `../build/zita-j2n` or `../build/zita-n2j` is missing, the application is still built, without the embedded programs.

`swift test` needs Xcode for XCTest: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`. The tests that need a JACK server start one of their own (`jackd` with the dummy driver, under a name of its own) and leave the server in use alone.

## Layout

- `Sources/ZitaBridgeKit`: logic without any UI (the command of each program, the reading of the state of the receiver, the settings and their checks, the addresses of the Mac, the ping, the buffer advice, the JACK connections), unit tested.
- `Sources/CZitaPty`: the small C function that starts a program in a pseudo-terminal.
- `Sources/ZitaNetworkBridge`: the SwiftUI application.
- `Tests`: unit and integration tests of `ZitaBridgeKit`, some of them on the real programs.
- `Resources`: `Info.plist`, `Localizable.xcstrings` and `InfoPlist.xcstrings` (French, English, German, Italian, Spanish) and the icon.
- `../../shared/MatrixKit` (MIT): glass, badges and points of the matrices, shared with the other tools.
- `../../shared/AppearanceKit` (MIT): dark, system or light look, the accent, the "About" panel and the menus.
- `../../shared/JackBridge` (MIT): the JACK client wrapper, which loads libjack by its full path, and the connections that the application keeps.

The application needs macOS 15. It is developed and tested on macOS 26, where it uses Liquid Glass; the look used on macOS 15 has not been tested on a real system.

The debug build reads a few environment variables (`ZITABRIDGE_*`) that drive the application without clicking, for screenshots and tests. They are compiled out of the release build.

## Licence

GPL-3.0-or-later, as `zita-njbridge`.
