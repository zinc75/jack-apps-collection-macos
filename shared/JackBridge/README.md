# JackBridge

A small Swift package that talks to libjack, loaded at run time with `dlopen` (nothing is linked against it, so an application using it starts even when JACK is not installed).

- `CJackBridge`: the C layer (`JackBridge.c`, `JackBridge.h`). It looks for `libjack.dylib` by absolute path (`/usr/local/lib`, `/opt/homebrew/lib`), because a bare name is not found and relative paths are refused by the hardened runtime.
- `JackBridge`: `JackBridgeWrapper`, the Swift side: client lifecycle, ports and connections, callbacks, transport, sample rate and buffer size.

The code comes from JackMate (© 2026 Éric Bavu, MIT), copied on 2026-11-01 from JackMate 2.2.0. Two changes: the Swift file imports the C module `CJackBridge`, and the error messages are plain English strings instead of keys of the JackMate string catalogue (the application using the package translates them if it shows them).

The package is under the MIT licence so that applications of any licence can use it. Applications that use it must be signed with the hardened runtime and the entitlement `com.apple.security.cs.disable-library-validation`, otherwise a libjack of another team is refused.

Added here, not in the JackMate copy: level meters (`jm_meter_register`, `jm_meter_take_peak`, `registerMeterPorts`, `takeMeterPeak`). A client registers input ports ("in1", "in2", …); the process callback keeps the highest absolute sample of each in an atomic (no lock, no allocation), and the reader takes and resets it. It serves the level preview of the Jack Capture interface, which opens a client of its own for that.
