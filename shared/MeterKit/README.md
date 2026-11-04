# MeterKit

The level meters of the Jack Apps Collection for macOS interfaces, as a Swift package (macOS 15, SwiftUI).

- `ChannelMeter`: the level, the held peak and the clip mark of one channel, and how a meter settles after a new reading (`following`: the level rises at once and falls a little at a time).
- `MeterScale`: how a level in dBFS is spread over a bar. The package has no scale of its own: each tool gives the one it follows (IEC, EBU, linear …).
- `MeterBars`: one bar per channel, with the peak, the clip mark and a graduated scale under it; two columns from 17 channels.

The package knows nothing about JACK or about any tool: the application gives it levels between 0 and 1, from whatever source (the console meter of a program, the process callback of a JACK client).

Licence: MIT (see `LICENSE`), so that applications of any licence can use it. It contains no code derived from a tool: the scales, which come from other programs, stay in the applications that use them.
