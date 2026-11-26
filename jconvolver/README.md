<div align="center">

  ![macOS](https://img.shields.io/badge/macOS-15.0%2B-lightgrey?logo=apple)
  ![Architectures](https://img.shields.io/badge/arm64%20%7C%20x86__64-universal-blue)
  ![License](https://img.shields.io/badge/license-GPL--3.0-green)
  [![Buy me a coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-FFDD00?logo=buymeacoffee&logoColor=000000)](https://www.buymeacoffee.com/zinc75)

  <img src="screenshots/icon.png" width="192" alt="Jack Convolver icon">
  <h1>Jack Convolver</h1>
  <p>A native macOS interface for <code>jconvolver</code> and <code>fconvolver</code>, the JACK convolution engine by Fons Adriaensen, and the three programs built for macOS.</p>
  <p>
    <img src="../assets/notarized-badge.png" width="15" alt="">
    <strong>Signed &amp; notarized by Apple</strong>
  </p>

  <img src="screenshots/matrix.png" width="760" alt="Jack Convolver with the matrix of an ambisonic encoder of order 5">

</div>

---

`jconvolver` is a matrix of convolutions in real time: any number of JACK inputs, any number of outputs, and an impulse response for each pair that needs one. It is used for reverbs, for decoders of Ambisonics, for the correction of loudspeakers and rooms, and for filter banks. The matrix is written in a text file, which tells where each impulse response comes from, with its gain and its delay. Its description is in `README.CONFIG`, and the examples of the author are installed with the programs.

Two more programs come with it. `fconvolver` does the same processing on sound files, without JACK. `makemulti` assembles single channel files into one multichannel file, for the impulse responses.

This edition raises the limit of the matrix from 64 to 128 inputs and 128 outputs, and gives the computation threads the real-time scheduling that macOS needs (see below).

Jack Convolver is an unofficial interface for these programs. It is part of Jack Apps Collection for macOS.

## Install

<p align="center"><a href="https://github.com/zinc75/jack-apps-collection-macos/releases/download/jconvolver-v1.1.0-macOS-2/JackConvolver-1.1.0-macOS-2.pkg"><img src="../assets/install-jackconvolver.svg" width="386" alt="Install Jack Convolver"></a></p>

Download `JackConvolver-1.1.0-macOS-2.pkg` from the [Releases](https://github.com/zinc75/jack-apps-collection-macos/releases?q=jconvolver) page and open it. It installs the application in `/Applications/Jack Apps Collection/` and the programs `jconvolver`, `fconvolver` and `makemulti` in `/usr/local/bin`, with the description of the configuration files, the examples and the licences in `/usr/local/share/doc/jconvolver`.

It needs macOS 15 or later, and [JACK](https://jackaudio.org/downloads/) installed. The programs alone, for macOS 11 and later, are in `jconvolver-1.1.0-macOS.pkg`, on the same page.

The application looks for a newer version once a day and offers to install it. The package is checked (checksum, signature and notarization) before it opens in the Installer. "Check for Updates…" in the application menu looks at once, and a box in the update panel turns the daily check off.

To build from source instead, see [`swiftui/README.md`](swiftui/README.md). To build only the programs, build the libraries of `libs/` (`fftw`, `zita-convolver`, `clthreads`, `libsndfile` and its codecs), then run `build_universal.sh` here.

## Use Jack Convolver with JackMate and JackMoebius

I also develop JackMate ([site](https://jackmate.app), [GitHub](https://github.com/zinc75/JackMate)) and JackMoebius ([site](https://jackmoebius.io), [GitHub](https://github.com/zinc75/JackMoebius)), which are not part of this repository.

JackMate is the simplest way to [install a notarized JACK](https://jackmate.app/install-jack-macos.html#one-clic-method-from-jackmate) and to [start it](https://jackmate.app/guide/configuration.html) without the command line. It shows every client in a [patchbay](https://jackmate.app/guide/patchbay.html), where the connections of Jack Convolver can be made too, and its [studios](https://jackmate.app/guide/studios.html) save a whole setup, the server settings and the connections, to restore in one click. JackMate is free and open source.

JackMoebius is the modern replacement for JackRouter on macOS: it exposes applications that only speak CoreAudio as JACK clients, one per application and in both directions. Together, JackMoebius and Jack Convolver can put an application without native JACK support through a reverb or a decoder: JackMoebius brings its sound into JACK, Jack Convolver processes it, and the result goes back to the application. JackMoebius is a commercial app, with a 14-day trial.

## The application

Jack Convolver edits the configuration of `jconvolver` as a matrix: each cell connects an input to an output, and an impulse response dropped on a cell fills it. The engine runs in real time on JACK, or on a sound file with `fconvolver`, without JACK. The configuration stays an ordinary `jconvolver` file, which the application reads and writes as upstream defines it. Each configuration is a session with its own window, and a session keeps running when its window is closed, from the menu bar.

The screenshots use the filters of an ambisonic encoder of order 5 (36 inputs, 36 outputs, from six filters), and impulse responses of the Sala dei Concerti in Parma, of a chapel and of Santa Lucia, recorded and published by Fons Adriaensen with the examples of `jconvolver`.

### Place the impulse responses

Files are dropped on the cells. The list on the left gives the channels of each file, and the number of places where it is used. A response that is used in several places is written once in the configuration: in the encoder below, the hollow cells are copies of the filled ones. A small card under the pointer says what a cell holds, and the cell that is selected has a light frame, so that it does not look like one that holds a response.

<p align="center">
  <img src="screenshots/matrix.png" width="760" alt="The matrix of an ambisonic encoder of order 5, with the card of a cell">
</p>

<br>

The same responses are listed in a table, to set the gain, the delay, the start and the length of all of them, or of the selection, at once: the value replaces the ones that are there, or is added to them.

<p align="center">
  <img src="screenshots/table.png" width="760" alt="The table of a room made of a reverberation tail and four sources of early reflections">
</p>

<br>

### Look at a response

Any response that comes from a file can be inspected, alone or with others to compare them. The waveform shows the start of the attack (60 dB under the peak) and the useful end (90 dB under it). The spectrum is smoothed in fractions of an octave. The phase can be unwrapped and stripped of its delay, which leaves the phase of the system itself, or shown as a group delay in milliseconds. The responses that `jconvolver` generates (a Dirac, a Hilbert filter) have no file and cannot be drawn.

<div align="center">
<table>
<tr>
<td align="center"><img src="screenshots/time.png" width="380" alt="Early reflections of the Sala dei Concerti"><br><sub>Early reflections of a concert hall, with the markers</sub></td>
<td align="center"><img src="screenshots/frequency.png" width="380" alt="The six filters of the encoder"><br><sub>The six filters of the encoder, one per order, in 1/12 octave</sub></td>
</tr>
<tr>
<td align="center"><img src="screenshots/phase.png" width="380" alt="Phase of an encoder filter"><br><sub>Phase of one filter, unwrapped, delay removed</sub></td>
<td align="center"><img src="screenshots/group-delay.png" width="380" alt="Group delay of the same filter"><br><sub>Group delay of the same filter</sub></td>
</tr>
</table>
</div>

<br>

### Truncate, fade, convert

These three are done on the curve, and no other tool of the collection does them.

The part of the file that the engine reads is set by two handles on the curve, or by typing the values. They are written in the `.conf` file as the start and the length of the response, and the file itself is not touched. Two buttons put them at the start of the attack and at the useful end.

<p align="center">
  <img src="screenshots/truncation.png" width="760" alt="Truncation of the response of a chapel, from the attack to the useful end">
</p>

<br>

A fade on the rise and on the fall of the part that is read, a tapered window, keeps the truncation from ending on a step. The preview shows the response with the fade, the rest at zero, and the original in gray. "Apply..." writes a new audio file that the configuration reads in place of the original, which is not modified, and says which other responses of the matrix read the same channel of the same file: they keep the original.

<p align="center">
  <img src="screenshots/fade.png" width="760" alt="Preview of a tapered window on the response of a chapel">
</p>

<br>

A file that is not at the rate of the JACK server is reported, with a button that converts it. The copy is written next to the file with the best converter of libsamplerate, put in the matrix in place of the original, and the start and the length of each response are recomputed for the new rate. Before keeping it, the conversion can be compared with the original: both are drawn, and the residual curve shows the difference of the two spectra in twelfths of an octave, 0.54 dB at most here. Rejecting it undoes everything.

<div align="center">
  <img src="screenshots/convert.png" width="760" alt="A converted response compared with the original">
  <br><br>
  <img src="screenshots/residual.png" width="760" alt="The residual spectrum of the conversion">
</div>

### Problems are found before the engine starts

Files that are missing, files at another rate than the server, channels that a file does not have, port names used twice, a latency compensation longer than a response, more ports than JACK allows: each is said in plain words, with the way to fix it when there is one. When the files of a configuration are not where it says, but next to it, the application finds them.

<div align="center">
  <img src="screenshots/problems.png" width="640" alt="The list of problems of a configuration">
  <br><br>
  <img src="screenshots/find-files.png" width="640" alt="Files found next to the configuration">
</div>

### In real time, or on a file

In real time, the ports of the engine are JACK ports named in the configuration, and connected at start to the clients that it names. The connections can also be made in the application while the engine runs: they apply at once, and when it stops they can be written in the configuration. The load of JACK, the load of the engine and the xruns are shown under the window.

<p align="center">
  <img src="screenshots/connections.png" width="760" alt="The connections of the engine, with its load and its xruns">
</p>

<br>

On a file, `fconvolver` reads an audio file and writes the convolved one, and the result is shown with its waveform, ready to open or to play.

<p align="center">
  <img src="screenshots/file-mode.png" width="760" alt="A sound file processed by fconvolver">
</p>

<br>

### The configuration file

The configuration is shown by parts (the header, the ports and connections) or as the whole file, which can be edited, or replaced by one that was received. A file that has not been modified is written as it was read. The three values that `jconvolver` reserves its memory with (the partition, the maximum length, the density) can follow the responses that are placed, and the computed values stay shown next to the ones that are written.

<p align="center">
  <img src="screenshots/config-text.png" width="760" alt="The text of a configuration file, with its colours">
</p>

<br>

A configuration can be exported as one audio file that holds all its responses, and a configuration file that refers to it, to send them as they are. A response that is used in several places is written once, the original files are not touched, and the two files can come in a `.zip`. The gain, the delay, the start and the length can also be applied to the samples.

<p align="center">
  <img src="screenshots/export.png" width="760" alt="Export of a portable version">
</p>

<br>

### Settings

<div align="center">
<table>
<tr>
<td align="center"><img src="screenshots/launch.png" width="380" alt="Launch options"><br><sub>Launch options</sub></td>
<td align="center"><img src="screenshots/configuration.png" width="380" alt="The header of a configuration"><br><sub>Header of a configuration</sub></td>
</tr>
<tr>
<td align="center"><img src="screenshots/port-names.png" width="380" alt="The names of the JACK ports"><br><sub>Names of the JACK ports</sub></td>
<td align="center"><img src="screenshots/display.png" width="380" alt="Appearance"><br><sub>Appearance</sub></td>
</tr>
</table>
</div>

<br>

## From the command line

The three programs can be used without the application. They are in `/usr/local/bin`, and the description of the configuration file (`README.CONFIG`) and the examples are in `/usr/local/share/doc/jconvolver`.

`jconvolver` runs in real time on JACK. It takes a configuration file, which says which impulse response goes from which input to which output: write your own, or start from an example in the `config-files` folder. Start JACK, then give it the file:

```
jconvolver my-room.conf
```

The examples are there to try. `hilbert.conf` needs no impulse response file, for instance:

```
jconvolver /usr/local/share/doc/jconvolver/config-files/hilbert.conf
```

Several other examples need impulse response files that are not installed: the configuration file says where to download them, and its `/cd` line is the folder where they have to be.

Connect the ports in a patchbay, such as the one of [JackMate](https://jackmate.app/guide/patchbay.html). Stop `jconvolver` with Control-C. A plain `kill` ends it in the middle of a cycle of JACK, which makes an xrun for every client of the server.

`fconvolver` does the same processing on sound files, without JACK, with the same configuration file:

```
fconvolver my-room.conf input.wav output.wav
```

`makemulti` assembles single channel files into one multichannel file, for the impulse responses:

```
makemulti --wav --24bit left.wav right.wav room.wav
```

## Changes compared with upstream

**CLI.** The programs are built from the sources of the author, as universal binaries, with these changes:

- The computation threads of `zita-convolver` get a time constraint from JACK. On macOS the `SCHED_FIFO` policy that `zita-convolver` asks for leaves them in the time sharing band, and on a loaded Mac they run late. With 24 or 48 busy processes on the Mac, 64 convolutions of 4 seconds ran without a late cycle, where the original stopped with "CPU overload". `zita-convolver` gets an optional function, called at the start of each of its threads, and `jconvolver` uses it to ask JACK for the time constraint.
- The matrix goes up to 128 inputs and 128 outputs (the limit is 64 upstream), in `zita-convolver` and in `makemulti`. A decoder of 100 inputs and 64 outputs, with 6400 filters of 512 samples, runs at about half of one core at a JACK period of 256 frames. JACK needs enough ports for this: its limit is set with the `-p` option of `jackd`.

- A line `/input/name` or `/output/name` can name several ports to connect, not only one (`README.CONFIG` says so). Older versions of `jconvolver` connect only the first and ignore the others.
- `jconvolver` prints the name that JACK gave to its client, which JACK may have changed to avoid a clash, so that a program that starts it can find its ports.

**Application.** `jconvolver` has no graphical interface upstream. Jack Convolver is new code, under the same licence as the programs. It starts the programs of this edition, reads what they print, and reads and writes their configuration files as upstream defines them: a configuration written by the application runs with the Linux version too, apart from the ports beyond the first on a line, which that version ignores.

## History

An installer of jconvolver 0.9.2 for macOS was published in 2012 by Matthias Kronlachner, [in this post](https://www.matthiaskronlachner.com/posts/jconvolver-0-9-2-for-mac-os-x/). He noted that the computation threads could be late on macOS. His multichannel plug-ins, [mcfx](https://github.com/kronihias/mcfx), include a convolver that reads the same configuration files.

## Support

jconvolver is free and open source. If this build saves you time, you can buy me a coffee: it helps pay the Apple Developer account ($99 a year) that keeps the installers signed and notarized.

[![Buy me a coffee](../assets/buymeacoffee-button.svg)](https://www.buymeacoffee.com/zinc75)

## Upstream

| | |
|---|---|
| Project | jconvolver |
| Author | Fons Adriaensen |
| Source | https://kokkinizita.linuxaudio.org/linuxaudio/downloads/jconvolver-1.1.0.tar.bz2 |
| Version | version 1.1.0 (archive downloaded 2026-10-31); no git history upstream. Configuration files are described in `upstream/README.CONFIG`; examples in `upstream/config-files/`. |
| Archive | `jconvolver-1.1.0.tar.bz2`, attached to the release `1.1.0` of the repository named below |
| SHA-256 | `ac5a11372d7325929c86966c7d2288a9276e65c43b29a50017c37a5e660ed80d` |
| Copy here | `upstream/` = a Git submodule of [zinc75/jconvolver-releases](https://github.com/zinc75/jconvolver-releases), at tag `1.1.0` (commit `623efebf2de92dd81ac540487987c2d161ee3a2e`): the files of the archive above, **unmodified** (clone with `--recurse-submodules`) |

That repository holds release snapshots, one commit per release; it is not a mirror, because Fons Adriaensen publishes release archives only and has no Git repository.

## Licence

The sources of `jconvolver` say GPL version 2 or any later version. The programs are linked with `zita-convolver`, which is under version 3 or any later version, so the programs of this edition are distributed under version 3 of the GPL. The libraries linked into them (FFTW, `clthreads`, libsndfile and its codecs) have their own licences, listed in the package.

## State on macOS

The application needs macOS 15. It is developed and tested on macOS 26, where it uses Liquid Glass; the look used on macOS 15 has not been tested on a real system.

The three programs run on arm64 and on x86_64, from macOS 11. `jconvolver` and `fconvolver` need `zita-convolver`, FFTW and libsndfile, `jconvolver` also `clthreads` and JACK; they are linked statically, and only `libjack` stays dynamic.

macOS has no `mlockall`, which `jconvolver` calls at start to keep its memory in RAM: the call is left out, so that it does not print a warning. In a run of 100 seconds with a large matrix, `jconvolver` did not wait for a page of memory once after its start.

Tested on macOS, on arm64 and on x86_64 (under Rosetta).

## Layout

- `upstream/`: the original sources, never edited (a Git submodule).
- `patches/`: changes to the upstream sources, as unified diffs.
- `swiftui/`: the Jack Convolver application, see its [README](swiftui/README.md).
- `build_universal.sh`: builds the three programs and writes their licence texts (needs the libraries of `libs/` built first).
- `VERSION`, `REVISION`: the upstream version and the number of this macOS edition.
