# WaveformKit

The waveform of a sound file for the Jack Apps Collection for macOS interfaces, as a Swift package (macOS 15, SwiftUI).

- `PeakAccumulator`: builds the peaks of a file from its samples, given block after block whatever their size (the lowest and the highest sample of each of 4096 slices of the file, for each channel).
- `WaveformPeaks`: the result. Values are kept as they are in the file, beyond full scale included: nothing is normalised, so the levels of the channels stay comparable.
- `SampleSource`: what gives the samples of a file, and moves to a frame so that a part of the file can be read. `AVFoundationSampleSource` reads what the system reads (WAV, AIFF, CAF, FLAC, MP3, not Ogg); an application can give a source of its own, with libsndfile for instance. `MemorySampleSource` is for tests and previews.
- `WaveformLoader` and `WaveformModel`: read a source in the background, with progress and cancellation. A big file, or one with many channels, is cut into parts that are read and measured at the same time, each by a thread with a source of its own (up to 8, fewer for a small file, or the number you give); the result is the same as with a single thread. The model is observable: `finishedPeaks` is nil until the whole file has been read, and `progress` says how far it is (`peaks` holds what has been read so far, with gaps while the parts are read at once).
- `WaveformView`: one lane per channel, all at the same scale (1.0 fills half a lane), what has been played in the colour the application gives, a line at the position, and a click or a drag that asks to move there. A mark shows where a channel goes beyond full scale.
- `TimeRuler`, `TimeRulerView` and `TimeFormat`: the graduations above the waveform (a round step chosen so that labels never touch), and times written as `m:ss`.

The package knows nothing about playing a file or about any tool: the application gives the view the position, from whatever drives the playback (the JACK transport, a player), and takes the position asked by a click. The bars are not drawn again when only the position moves.

Licence: MIT (see `LICENSE`), so that applications of any licence can use it. It reads no file format by itself: a source that links a library such as libsndfile belongs to the application that links it.
