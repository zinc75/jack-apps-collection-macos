// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A way to find again files that a configuration names in a folder that is not on this machine: the files of the same names are in a folder next
/// to the configuration file (or in one of its folders).
public struct PathProposal: Identifiable, Sendable, Equatable {
    /// The folder that the configuration looks in (the `/cd` that was in force, or the folder of the absolute paths).
    public var from: String
    /// The folder where files of the same names were found, relative to the folder of the configuration; empty for that folder itself.
    public var to: String
    /// The names (as the configuration writes them) found there, and those that are still missing.
    public var found: [String]
    public var missing: [String]
    /// The impulse responses that would change: those whose file is among `found`.
    public var places: [ConvProblem.Place]
    public var id: String { from }

    public var isInConfigurationFolder: Bool { to.isEmpty }
}

public enum PathResolver {
    /// The proposals for the files of a document that cannot be found, one for each folder that the configuration looks in.
    ///
    /// For each such folder the candidates are the folder of the configuration, its folders down to two levels, and the end of the old folder put
    /// after the folder of the configuration (`/Users/bob/IR/hall` gives `hall` and `IR/hall`); the one that holds the most of the files by name is
    /// proposed, the folder of the configuration itself when two hold as many.
    ///
    /// - Parameters:
    ///   - fileExists: whether a file is there (given its path).
    ///   - subfolders: the names of the folders in a folder.
    public static func proposals(for document: ConvDocument, configDirectory: String, fileExists: (String) -> Bool,
                                 subfolders: (String) -> [String]) -> [PathProposal] {
        struct Missing { var place: ConvProblem.Place; var name: String }
        var byFolder: [String: [Missing]] = [:]
        var order: [String] = []
        for pair in document.content.impulses.keys.sorted() {
            for (index, impulse) in document.impulses(at: pair).enumerated() {
                guard case .file(let file, _) = impulse.source else { continue }
                let resolved = ConvConfig.path(of: file, directory: impulse.directory, configDirectory: configDirectory)
                guard !fileExists(resolved) else { continue }
                // An absolute path names a folder of its own; a relative one the folder in force.
                let folder = file.hasPrefix("/") ? (file as NSString).deletingLastPathComponent : (impulse.directory ?? configDirectory)
                let name = file.hasPrefix("/") ? (file as NSString).lastPathComponent : file
                if byFolder[folder] == nil { order.append(folder) }
                byFolder[folder, default: []].append(Missing(place: ConvProblem.Place(pair: pair, index: index), name: name))
            }
        }
        // The folders that can be looked in, relative to the folder of the configuration.
        var candidates: [String] = [""]
        var frontier: [String] = [""]
        for _ in 0..<2 {
            var next: [String] = []
            for relative in frontier {
                let path = relative.isEmpty ? configDirectory : (configDirectory as NSString).appendingPathComponent(relative)
                for name in subfolders(path).sorted() where !name.hasPrefix(".") && candidates.count < 600 {
                    let child = relative.isEmpty ? name : relative + "/" + name
                    candidates.append(child)
                    next.append(child)
                }
            }
            frontier = next
        }
        var out: [PathProposal] = []
        for folder in order {
            let items = byFolder[folder] ?? []
            let names = Array(Set(items.map(\.name))).sorted()
            // The end of the old folder put after the folder of the configuration.
            let parts = folder.split(separator: "/").map(String.init)
            var local = candidates
            for count in 1...max(1, min(3, parts.count)) where parts.count >= count {
                local.append(parts.suffix(count).joined(separator: "/"))
            }
            var best: (relative: String, found: Int)?
            for relative in local {
                let base = relative.isEmpty ? configDirectory : (configDirectory as NSString).appendingPathComponent(relative)
                let found = names.filter { fileExists((base as NSString).appendingPathComponent($0)) }.count
                if found > (best?.found ?? 0) { best = (relative, found) }
            }
            guard let best else { continue }
            let base = best.relative.isEmpty ? configDirectory : (configDirectory as NSString).appendingPathComponent(best.relative)
            let foundNames = names.filter { fileExists((base as NSString).appendingPathComponent($0)) }
            out.append(PathProposal(from: folder, to: best.relative, found: foundNames, missing: names.filter { !foundNames.contains($0) },
                                    places: items.filter { foundNames.contains($0.name) }.map(\.place)))
        }
        return out
    }

    /// Puts the files in the folders that were found: the impulse responses lose the `/cd` and name their file from the folder of the configuration,
    /// so that the configuration does not depend on the machine any more.
    public static func apply(_ proposals: [PathProposal], to document: inout ConvDocument) {
        for proposal in proposals {
            for place in proposal.places {
                guard var impulse = document.impulses(at: place.pair).indices.contains(place.index) ? document.impulses(at: place.pair)[place.index] : nil,
                      case .file(let file, let channel) = impulse.source else { continue }
                let name = file.hasPrefix("/") ? (file as NSString).lastPathComponent : file
                let relative = proposal.to.isEmpty ? name : (proposal.to as NSString).appendingPathComponent(name)
                impulse.source = .file(path: relative, channel: channel)
                impulse.directory = nil
                document.replace(impulse, at: place.index, of: place.pair)
            }
        }
    }
}
