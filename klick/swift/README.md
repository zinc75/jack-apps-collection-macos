# Klick: the application with JACK

The Swift package of Klick of the collection: the core of Klick Tempo (`../klick-tempo/`) with the JACK backend added to CoreAudio. The interface itself is in the core; this package adds the JACK page and options, the connections list and the transport status.

## Build

You need Xcode (swift 6; `DEVELOPER_DIR` is set for the commands below, the global `xcode-select` setting is not changed) and [JACK](https://jackaudio.org/downloads/) installed. In this order, from the root of the repository:

```
libs/<name>/build_universal.sh                              the libraries
klick/klick-tempo/klick/build_universal.sh libs/build       klick and libklick.a
klick/klick-tempo/klick/engine/build_engine.sh libs/build   the engine of the core
klick/engine/build_jack.sh                                  the JACK backend, klick/build/libklickjack.a
klick/swift/build.sh                                        klick/build/Klick.app
```

`build.sh --debug` builds for the native architecture only, faster. The core is a Git submodule: clone with `--recurse-submodules`.

In a debug build, `KLICK_FRESH=1` starts without the saved settings, `KLICK_BACKEND=jack` plays on JACK from the start, `KLICK_PAGE=output` opens a page, `KLICK_FOLLOW=1` turns on the following of the transport and `KLICK_LIVE=1` opens the simplified view.

## Tests

```
klick/swift/run_tests.sh
```

starts a JACK server of its own (`kltest`, dummy driver) and a fake JackMoebius daemon, then runs the tests of the module, those that need a server included. The server in use is never touched. It needs `jackd`, `jack_lsp` and `jack_capture`.

## Structure

- `Sources/CKlickJack`: the C interface of the JACK backend (`klick_jack.h`) and the link settings of its static library.
- `Sources/KlickJack`: the backend (`JackBackend`), its page and menu (`JackInterface`), the ports (`JackPort`) and the transport (`JackTransport`: its state and the badge).
- `Sources/KlickCollection`: the application, a few lines: its name, its colour and the backends it offers. The bundle makes it `Klick`.
- `Tests/KlickJackTests`: the tests of the module.
- `Resources/`: the strings of the JACK module and the icon of this application.
- `build.sh`: assembles the bundle with the script of the core.
