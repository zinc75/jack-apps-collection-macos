# Klick: the JACK backend of the engine

The engine of klick plays on an audio backend that it knows only through an interface. CoreAudio is built into the core (`klick-tempo/`); this folder is the JACK backend, built as one static library with a C interface (`../swift/Sources/CKlickJack/include/klick_jack.h`) that the Swift module `KlickJack` uses.

## What it does

- Opens one output port, `Klick:out`, in a JACK server. It never starts a server: without one, the backend refuses and says so.
- Loads libjack at run time, from a full path (`/usr/local/lib`, `/opt/homebrew/lib`), so nothing is linked against it and the program starts on a Mac without JACK.
- Lists the input ports of the server, connects and disconnects the output, and reads the latency that JACK announces.
- Follows the JACK transport: what plays waits for the transport to roll and stops with it. It can also be the timebase master of the transport, and the simple metronome takes the tempo and meter of another timebase master (`transport_driver.*`, an extension of the engine, see `klick-tempo/klick/engine/klick_engine_extension.hh`).

## Build

You need Xcode (`DEVELOPER_DIR` is set by the script only) and [JACK](https://jackaudio.org/downloads/) installed (only its headers are used to build). From the root of the repository, in this order:

```
libs/<name>/build_universal.sh                           the libraries (see libs/)
klick/klick-tempo/klick/build_universal.sh libs/build    klick and libklick.a
klick/klick-tempo/klick/engine/build_engine.sh libs/build   the engine of the core
klick/engine/build_jack.sh                               klick/build/libklickjack.a and the test
```

## Tests

`tests/run_jack_tests.sh` starts a JACK server of its own (`kltest`, dummy driver, 48 kHz, blocks of 512), runs the test of the backend on each architecture, then records the clicks with `jack_capture` and checks their spacing. It never touches the server in use. It needs `jackd`, `jack_lsp` and `jack_capture`.

## Files

- `jack_api.*`: the functions of libjack, found by `dlsym`.
- `audio_interface_jack_dl.*`: the audio interface of klick on JACK.
- `transport_driver.*`: the extension that ties the engine to the transport.
- `klick_jack.cpp`: the C interface.
- `build_jack.sh`, `tests/`.
