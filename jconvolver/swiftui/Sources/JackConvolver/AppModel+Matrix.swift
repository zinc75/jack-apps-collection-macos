// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import JConvolverKit
import SoundFileKit
import SwiftUI

/// A sound file of the list beside the matrix.
struct BinFile: Identifiable, Equatable {
    /// The whole path.
    let path: String
    let info: SoundFileInfo
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }

    static func == (a: BinFile, b: BinFile) -> Bool { a.path == b.path }
}

extension AppModel {
    private static let audioExtensions: Set<String> = ["wav", "wave", "aif", "aiff", "aifc", "caf", "flac", "ogg", "opus", "mp3", "w64", "rf64"]

    // MARK: The list of files

    /// The sound files of the folder of the configuration, and those the matrix uses from elsewhere.
    func loadBin() {
        var paths: [String] = []
        if fileURL != nil, let names = try? FileManager.default.contentsOfDirectory(atPath: configDirectory) {
            paths = names.filter { Self.audioExtensions.contains(($0 as NSString).pathExtension.lowercased()) && !$0.hasPrefix(".") }
                .map { (configDirectory as NSString).appendingPathComponent($0) }
        }
        if let document {
            for impulses in document.content.impulses.values {
                for impulse in impulses {
                    guard case .file(let file, _) = impulse.source else { continue }
                    let path = ConvConfig.path(of: file, directory: impulse.directory, configDirectory: configDirectory)
                    if !paths.contains(path) { paths.append(path) }
                }
            }
        }
        setBin(paths)
    }

    func addToBin(_ urls: [URL]) {
        setBin(Set(binFiles.map(\.path)).union(urls.map(\.path)).map { $0 })
    }

    private func setBin(_ paths: [String]) {
        let catalog = catalog
        let files = paths.compactMap { path in catalog.info(at: path).map { BinFile(path: path, info: $0) } }
        setBinFiles(files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }

    func chooseFilesForBin() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Choisissez des fichiers de réponses impulsionnelles.")
        if panel.runModal() == .OK { addToBin(panel.urls) }
    }

    func chooseFolderForBin() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = String(localized: "Choisissez un dossier de réponses impulsionnelles.")
        guard panel.runModal() == .OK, let folder = panel.url,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        addToBin(names.filter { Self.audioExtensions.contains(($0 as NSString).pathExtension.lowercased()) && !$0.hasPrefix(".") }
            .map { folder.appendingPathComponent($0) })
    }

    /// How many impulse responses of the matrix use a channel of this file.
    func uses(of file: BinFile) -> Int {
        guard let document else { return 0 }
        let directory = configDirectory
        var count = 0
        for impulses in document.content.impulses.values {
            for impulse in impulses {
                guard case .file(let path, _) = impulse.source else { continue }
                if ConvConfig.path(of: path, directory: impulse.directory, configDirectory: directory) == file.path { count += 1 }
            }
        }
        return count
    }

    /// What is chosen in the list, in the order of the list: the files by name and their channels in order, then the pulses.
    func orderedPicks() -> [Placeable] {
        var out: [Placeable] = []
        for file in binFiles {
            for channel in 1...max(1, file.info.channels) where picked.contains(.channel(path: file.path, channel: channel)) {
                out.append(.channel(path: file.path, channel: channel))
            }
        }
        if picked.contains(.dirac) { out.append(.dirac) }
        if picked.contains(.hilbert) { out.append(.hilbert) }
        return out
    }

    // MARK: Placing

    /// The path as the configuration says it: the name of the file when it is in the folder of the configuration, else the whole path.
    func storedPath(_ absolute: String) -> String {
        (absolute as NSString).deletingLastPathComponent == configDirectory ? (absolute as NSString).lastPathComponent : absolute
    }

    func plan(_ items: [Placeable], from pair: ConvPair, mode: PlacementMode) -> PlacementPlan {
        Placement.plan(items, from: pair, mode: mode, inputs: document?.inputCount ?? 0, outputs: document?.outputCount ?? 0)
    }

    /// Places what the plan says; the placed pairs become the selection.
    func apply(_ plan: PlacementPlan) {
        guard !plan.items.isEmpty else { return }
        let stored = PlacementPlan(items: plan.items.map { item in
            if case .channel(let path, let channel) = item.what { return .init(pair: item.pair, what: .channel(path: storedPath(path), channel: channel)) }
            return item
        }, left: plan.left)
        let partition = automaticHeader.partition
        var summary = (placed: 0, replaced: 0)
        edit(plan.items.count > 1 ? String(localized: "placement de \(plan.items.count) RI") : String(localized: "placement d'une RI")) {
            summary = $0.apply(stored, partition: partition)
        }
        let pairs = plan.items.map(\.pair)
        selection.select(from: ConvPair(input: pairs.map(\.input).min() ?? 0, output: pairs.map(\.output).min() ?? 0),
                         to: ConvPair(input: pairs.map(\.input).max() ?? 0, output: pairs.map(\.output).max() ?? 0))
        dropPlan = nil
    }

    /// Places what is chosen in the list, starting at the selected pair.
    func placePicked(mode: PlacementMode) {
        let items = orderedPicks()
        guard !items.isEmpty, document != nil else {
            message = String(localized: "Choisissez d'abord des éléments dans la liste de fichiers.")
            return
        }
        let b = selection.bounds
        apply(plan(items, from: ConvPair(input: b.firstInput, output: b.firstOutput), mode: mode))
    }

    // MARK: Emptying

    func clearSelection() {
        let pairs = selection.pairs.filter { !(document?.impulses(at: $0).isEmpty ?? true) }
        guard !pairs.isEmpty else { return }
        edit(String(localized: "RI retirées")) { d in pairs.forEach { d.clear($0) } }
    }

    func clearAll() {
        guard let document, document.placedPairs > 0 else { return }
        edit(String(localized: "matrice vidée")) { d in d.content.impulses = [:] }
    }

    // MARK: What a pair holds

    func label(of impulse: ConvImpulse) -> String {
        switch impulse.source {
        case .file(let path, let channel): return "\((path as NSString).lastPathComponent) · \(String(localized: "voie")) \(channel)"
        case .dirac: return String(localized: "Impulsion (Dirac)")
        case .hilbert: return String(localized: "Filtre de Hilbert")
        case .copy(let source): return String(localized: "Copie de l'entrée \(source.input + 1) → sortie \(source.output + 1)")
        }
    }

    /// The names that stand for an input and an output: the name in the file, else the number.
    func inputLabel(_ i: Int) -> String { document?.inputs[safe: i]?.name ?? String(localized: "Entrée \(i + 1)") }
    func outputLabel(_ o: Int) -> String { document?.outputs[safe: o]?.name ?? String(localized: "Sortie \(o + 1)") }

    /// The pairs with an error: they are outlined in red.
    var pairsInError: Set<ConvPair> { Set(problems.filter { $0.severity == .error }.compactMap(\.pair)) }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
