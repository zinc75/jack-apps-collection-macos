# SoundFileKit

Sound files for the Jack Apps Collection for macOS interfaces, read with libsndfile, as a Swift package (macOS 15).

- `SoundFile`: opens a sound file and reads it. libsndfile reads WAV, RF64, W64, AIFF, CAF, FLAC, Ogg Vorbis, Opus and MP3, among others. It is a `SampleSource` of `WaveformKit`, so that the waveform of any of these files can be drawn, and it can move to a frame without reading what comes before.
- `SoundFileInfo`: what libsndfile says about a file (channels, rate, frames, container, encoding, bits, whether the format loses information), and its format code, to write a file in the same format.
- `CSndfile`: libsndfile itself, for an application that has to write files.

The package does not build libsndfile: it links the static universal libraries of `libs/build/universal` (libsndfile and the codecs it needs), which are built with the `build_universal.sh` of each library. An application that depends on it also needs the headers of that folder, with `-Xcc -I<libs>/include` in the Swift settings of its targets.

An instance of `SoundFile` has one position in the file and is not safe for several threads at once: each thread opens the file again.

Licence: MIT (see `LICENSE`), so that applications of any licence can use it. libsndfile is under the LGPL; the application that links it carries its notice.
