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

## Applications

| Icon | Name | Description | Notarized package |
|---|---|---|---|
| <a href="jack_capture/"><img src="jack_capture/screenshots/icon.png" width="64" alt="Jack Capture icon"></a> | [Jack Capture](jack_capture/) | Records JACK audio to a file. An interface for `jack_capture` by Kjetil Matheussen ([upstream](https://github.com/kmatheussen/jack_capture)). | [Download 0.9.73](https://github.com/zinc75/jack-apps-collection-macos/releases/download/jack_capture-v0.9.73-macOS-2/JackCapture-0.9.73-macOS-2.pkg) |

<div align="center">
  <a href="jack_capture/"><img src="jack_capture/screenshots/recording.png" width="640" alt="Jack Capture recording"></a>
</div>

## About this repository

Each tool keeps its original sources untouched in `upstream/`, with the changes needed for macOS as patches in `patches/`. Fixes that are not specific to this repository are sent to the original authors.

## Support

Jack Apps Collection is free and open source. If it saves you time, you can buy me a coffee: it helps pay the Apple Developer account ($99 a year) that keeps the installers signed and notarized.

[![Buy me a coffee](https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=&slug=zinc75&button_colour=FFDD00&font_colour=000000&font_family=Lato&outline_colour=000000&coffee_colour=ffffff)](https://www.buymeacoffee.com/zinc75)

## Licence

Each tool keeps the licence of its original project, see [`LICENSES.md`](LICENSES.md). The documentation is MIT-licensed.
