# Contributing

Bug reports, fixes, translations and new languages are welcome. For a bigger change, open an issue first so the approach can be discussed.

## Bug reports

Open an issue with the macOS version, the JACK version, the tool, and the steps to reproduce. For a problem in the original program rather than in the macOS build or the interface, the upstream project is the place to report it (each tool's README links to it).

## Translations

The interfaces are in French, English, German, Italian and Spanish. French is the source language: the keys of the catalogs are the French texts. The German, Italian and Spanish translations were written without a native speaker, so corrections are especially welcome, and so are new languages.

Each application has a string catalog, `Localizable.xcstrings`, in its `Resources` folder:

| Application | Catalog |
|---|---|
| Jack Capture | `jack_capture/swiftui/Resources/Localizable.xcstrings` |
| Jack Play | `jack_play/swiftui/Resources/Localizable.xcstrings` |
| Klick | `klick/swift/Resources/Localizable.xcstrings`, and the one of the Klick Tempo core in `klick/klick-tempo/klick/swiftui/Resources/` (a [separate repository](https://github.com/zinc75/klick-tempo), also a submodule here) |
| Zita Network Bridge | `zita-njbridge/swiftui/Resources/Localizable.xcstrings` and `InfoPlist.xcstrings` |

To fix a translation, edit the value for your language in the catalog and open a pull request, or open an issue with the text as it reads now and the text you suggest. Xcode opens these files in its string catalog editor; they are also plain JSON.

To add a language, add its translations to each catalog, and its code to `CFBundleLocalizations` in the `Info.plist` of the application. `build.sh` writes one `.lproj` folder per language found in the catalog, so nothing else changes. A partial translation is fine: the missing texts show in French.

A few things to keep:

- `%@`, `%lld` and the like are replaced by values at runtime: keep them as they are, and keep their order or number them (`%1$@`).
- Names stay as they are: JACK, MIDI, BPM, xrun, and the names of the programs.
- Use the same terms as the other applications of the collection for the same thing, and the informal address where the language has one (tu, du).
- A text must not be assumed to be as short as the French one: windows and buttons have to fit a longer text.

## Code

Fork, branch from `main`, keep a change focused, and open a pull request with what changes and why. Commit messages are in English, one line, in the form `[jack-apps] <type>: <subject>` with a type among feat, fix, docs, build and chore.

The build scripts and the tests are described in the README of each tool and in its `swiftui/README.md`. Changes to the original sources of a tool go in its `patches/` folder as unified diffs: the `upstream/` folders are never edited.

## Licence

A contribution to a tool is under the licence of that tool. The shared packages in `shared/` are MIT, and the documentation is MIT.
