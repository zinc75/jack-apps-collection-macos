<div align="center">

  <h1>Jack Apps Collection for macOS</h1>
  <p>Useful JACK tools for macOS, and native graphical interfaces for them.</p>
  <p>
    <img src="assets/notarized-badge.png" width="15" alt="">
    <strong>Signed &amp; notarized by Apple</strong>
  </p>
  <p>
    <a href="https://www.buymeacoffee.com/zinc75"><img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-FFDD00?logo=buymeacoffee&logoColor=000000" alt="Buy me a coffee"></a>
  </p>

</div>

---

Tools are built for Apple Silicon and Intel, and get a SwiftUI application where it makes sense. They are added one at a time, as they are finished.

## Tools

| Icon&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; | Name | Description | CLI | GUI | Notarized package |
|---|---|---|---|---|---|
| <a href="jack_capture/"><img src="jack_capture/screenshots/icon.png" width="96" alt="Jack Capture icon"></a> | [Jack Capture](jack_capture/) | Records JACK audio to a file. An interface for `jack_capture` by Kjetil Matheussen ([upstream](https://github.com/kmatheussen/jack_capture)). | ✓ | ✓ | [Download 0.9.73](https://github.com/zinc75/jack-apps-collection-macos/releases/download/jack_capture-v0.9.73-macOS-5/JackCapture-0.9.73-macOS-5.pkg) |
| <a href="klick/"><img src="klick/screenshots/icon.png" width="96" alt="Klick icon"></a> | [Klick](klick/) | A metronome with tempo maps that plays in JACK and can follow the JACK transport. An interface for `klick` by Dominic Sacré ([upstream](https://github.com/dsacre/klick)). The same application without JACK is [Klick Tempo](https://github.com/zinc75/klick-tempo). | ✓ | ✓ | [Download 0.13.0](https://github.com/zinc75/jack-apps-collection-macos/releases/download/klick-v0.13.0-macOS-3/Klick-0.13.0-macOS-3.pkg) |
| <a href="jack_play/"><img src="jack_play/screenshots/icon.png" width="96" alt="Jack Play icon"></a> | [Jack Play](jack_play/) | Plays sound files and playlists in JACK, with no gap between files, and connects each channel where you choose. An interface for `jack_play`, the `rju-play` player by Rohan Drape ([upstream](https://github.com/rd--/rju)). | ✓ | ✓ | [Download 0.19](https://github.com/zinc75/jack-apps-collection-macos/releases/download/jack_play-v0.19-macOS-3/JackPlay-0.19-macOS-3.pkg) |
| <a href="zita-njbridge/"><img src="zita-njbridge/screenshots/icon.png" width="96" alt="Zita Network Bridge icon"></a> | [Zita Network Bridge](zita-njbridge/) | Carries multichannel audio between two Macs over a network, with adaptive resampling. An interface for `zita-njbridge` (`zita-j2n` and `zita-n2j`) by Fons Adriaensen ([upstream](https://kokkinizita.linuxaudio.org/linuxaudio/)). | ✓ | ✓ | [Download 0.4.8](https://github.com/zinc75/jack-apps-collection-macos/releases/download/zita-njbridge-v0.4.8-macOS/ZitaNetworkBridge-0.4.8-macOS.pkg) |

<div align="center">
  <a href="jack_capture/"><img src="jack_capture/screenshots/recording.png" width="640" alt="Jack Capture recording"></a>
  <br><em>Jack Capture</em>
</div>

---

<div align="center">
  <a href="klick/"><img src="klick/screenshots/live.png" width="640" alt="Klick driven by the JACK transport"></a>
  <br><em>Klick</em>
</div>

---

<div align="center">
  <a href="jack_play/"><img src="jack_play/screenshots/play.png" width="640" alt="Jack Play playing an 8 channel file"></a>
  <br><em>Jack Play</em>
</div>

---

<div align="center">
  <a href="zita-njbridge/"><img src="zita-njbridge/screenshots/link.png" width="460" alt="Zita Network Bridge, a link that sends and receives"></a>
  <br><em>Zita Network Bridge</em>
</div>

## About this repository

Each tool keeps its original sources untouched in `upstream/`, with the changes needed for macOS as patches in `patches/`. Fixes that are not specific to this repository are sent to the original authors.

Some folders are Git submodules, each fixed at a given commit of its own repository:

| Submodule | What it is |
|---|---|
| `jack_capture/upstream` | `jack_capture` by Kjetil Matheussen, from its [official repository](https://github.com/kmatheussen/jack_capture), unmodified |
| `jack_play/upstream` | `rju` (`rju-play`) by Rohan Drape, from its [repository](https://github.com/rd--/rju), unmodified, with its own `r-common` submodule |
| `klick/klick-tempo` | [klick-tempo](https://github.com/zinc75/klick-tempo), the core of Klick and the same application without JACK, in its own repository |
| `klick/klick-tempo/klick/upstream` | `klick` by Dominic Sacré, from its [official repository](https://github.com/dsacre/klick), unmodified, inside klick-tempo |
| `libs/libogg/upstream` | `libogg` by Xiph.Org, from its [official repository](https://github.com/xiph/ogg), at the tag of the release used, unmodified |

Clone with `git clone --recurse-submodules`, or run `git submodule update --init --recursive` in a clone made without it.

## Support

Jack Apps Collection is free and open source. If it saves you time, you can buy me a coffee: it helps pay the Apple Developer account ($99 a year) that keeps the installers signed and notarized.

[![Buy me a coffee](https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=&slug=zinc75&button_colour=FFDD00&font_colour=000000&font_family=Lato&outline_colour=000000&coffee_colour=ffffff)](https://www.buymeacoffee.com/zinc75)

## Licence

Each tool keeps the licence of its original project, see [`LICENSES.md`](LICENSES.md). The documentation is MIT-licensed.
