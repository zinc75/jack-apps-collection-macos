// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import JConvolverKit
import SoundFileKit

/// What a fade applies to: the response that is edited, the part of its file that is read, and what else reads the same channel.
struct FadeContext {
    var target: DetailTarget
    var path: String
    var channel: Int
    /// The part that is read, in frames of the file: its start and its length (the length that is really read when the response reads to the end).
    var start: Int
    var length: Int
    var fadeIn: Int
    var fadeOut: Int
    var info: SoundFileInfo
    /// The other responses of the matrix that read the same channel of the same file: they keep the original.
    var others: [DetailTarget]
}

extension AppModel {
    /// Whether a fade is typed for the response that is edited.
    var hasFadeDraft: Bool { fadeIn > 0 || fadeOut > 0 }

    func resetFade() { fadeIn = 0; fadeOut = 0 }

    func fadeContext() -> FadeContext? {
        guard let target = detail, let document, let impulse = impulse(of: target), case .file(let file, let channel) = impulse.source else { return nil }
        let path = ConvConfig.path(of: file, directory: impulse.directory, configDirectory: configDirectory)
        guard let info = catalog.info(at: path), info.frames > 0 else { return nil }
        let zone = ImpulseFade.used(offset: impulse.offset, length: impulse.length, total: Int(info.frames))
        guard !zone.isEmpty else { return nil }
        let fade = ImpulseFade.clamped(fadeIn: fadeIn, fadeOut: fadeOut, length: zone.count)
        var others: [DetailTarget] = []
        for pair in document.content.impulses.keys.sorted() {
            for (index, other) in (document.content.impulses[pair] ?? []).enumerated() {
                let place = DetailTarget(pair: pair, index: index)
                guard place != target, case .file(let f, let c) = other.source, c == channel,
                      ConvConfig.path(of: f, directory: other.directory, configDirectory: configDirectory) == path else { continue }
                others.append(place)
            }
        }
        return FadeContext(target: target, path: path, channel: channel, start: zone.lowerBound, length: zone.count, fadeIn: fade.fadeIn, fadeOut: fade.fadeOut,
                           info: info, others: others)
    }

    /// The name of the file that applying the fade writes, with its extension.
    func fadeFileName(_ context: FadeContext) -> String {
        ImpulseFade.fileName(original: context.path, channel: context.channel, start: context.start, length: context.length,
                             fadeIn: context.fadeIn, fadeOut: context.fadeOut, ext: ImpulseFade.output(for: context.info).fileExtension)
    }

    /// The folder where the file is put by default: a new one next to the original, named for the day and the minute.
    func fadeDefaultFolder(_ context: FadeContext) -> URL {
        let parent = URL(fileURLWithPath: context.path).deletingLastPathComponent()
        let base = ImpulseFade.folderName(for: Date())
        var candidate = parent.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(base)-\(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }

    /// Writes the file with the fade and makes the response read it: one step of the history, which gives the response back its file (the new file stays).
    func applyFade(_ context: FadeContext, to destination: URL) async throws {
        let source = URL(fileURLWithPath: context.path)
        let channel = context.channel, start = context.start, length = context.length, fadeIn = context.fadeIn, fadeOut = context.fadeOut
        try await Task.detached(priority: .userInitiated) {
            try ImpulseFade.write(source: source, channel: channel, offset: start, length: length, fadeIn: fadeIn, fadeOut: fadeOut, to: destination)
        }.value
        // The new file holds only the part that was read, on one channel: the start and the length are gone, the gain and the delay stay.
        let directory = configDirectory
        let named = destination.path.hasPrefix(directory + "/") ? String(destination.path.dropFirst(directory.count + 1)) : destination.path
        edit(String(localized: "fondu appliqué")) { document in
            guard var impulse = document.impulses(at: context.target.pair).indices.contains(context.target.index)
                    ? document.impulses(at: context.target.pair)[context.target.index] : nil else { return }
            impulse.source = .file(path: named, channel: 1)
            impulse.directory = nil
            impulse.offset = 0
            impulse.length = 0
            document.replace(impulse, at: context.target.index, of: context.target.pair)
        }
        resetFade()
        loadBin()
    }

    /// A folder asked for when the one that was chosen cannot be written to.
    func chooseFadeFolder(near original: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: original).deletingLastPathComponent()
        panel.message = String(localized: "Choisissez le dossier où écrire le fichier avec le fondu.")
        panel.prompt = String(localized: "Choisir")
        return panel.runModal() == .OK ? panel.url : nil
    }
}
