// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SoundFileKit

/// A line of a configuration text that has something to say: what jconvolver would refuse, what does not fit the matrix, a file that cannot be read.
public struct ConfLineProblem: Equatable, Sendable, Identifiable {
    /// Starts at 1.
    public var line: Int
    public var isError: Bool
    public var message: String
    public var id: String { "\(line):\(message)" }

    public init(line: Int, isError: Bool, message: String) { self.line = line; self.isError = isError; self.message = message }
}

/// What a text of configuration has wrong, line by line, as it stands (typed, or pasted from a mail), before it is applied.
public enum ConfTextAnalysis {
    /// - Parameters:
    ///   - configDirectory: where the files named without a path are looked for, when no `/cd` came before.
    ///   - fileInfo: the header of a sound file, nil when it cannot be read.
    ///   - jackRate: the sample rate of the server in real time, nil on sound files.
    public static func problems(in text: String, configDirectory: String, fileInfo: (String) -> SoundFileInfo?, jackRate: Double?) -> [ConfLineProblem] {
        var out: [ConfLineProblem] = []
        let (config, parsed) = ConvConfig.parse(text)
        out += parsed.map { ConfLineProblem(line: $0.line, isError: true, message: $0.message) }
        if config.convolver == nil, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(ConfLineProblem(line: 1, isError: true, message: String(localized: "Pas de ligne /convolver/new : ce n'est pas une configuration de jconvolver.")))
        }
        out += ConvDocument.make(from: config).issues.map { ConfLineProblem(line: $0.line, isError: true, message: $0.message) }
        for placement in config.placements {
            guard case .read(let r) = placement.kind else { continue }
            let path = ConvConfig.path(of: r.file, directory: placement.directory, configDirectory: configDirectory)
            guard let info = fileInfo(path) else {
                out.append(ConfLineProblem(line: placement.line, isError: true, message: String(localized: "Fichier introuvable ou illisible : \((r.file as NSString).lastPathComponent)")))
                continue
            }
            if r.channel < 1 || r.channel > info.channels {
                out.append(ConfLineProblem(line: placement.line, isError: true, message: String(localized: "La voie \(r.channel) n'est pas dans le fichier, qui en a \(info.channels).")))
            }
            if let jackRate, jackRate > 0, abs(info.sampleRate - jackRate) > 0.5 {
                out.append(ConfLineProblem(line: placement.line, isError: true, message: String(localized: "Le fichier est à \(Int(info.sampleRate)) Hz, JACK à \(Int(jackRate)) Hz.")))
            }
            if info.frames > 0, r.offset >= Int(info.frames) {
                out.append(ConfLineProblem(line: placement.line, isError: false, message: String(localized: "Le début (\(r.offset)) dépasse la fin du fichier.")))
            }
        }
        // One message per line and text, in the order of the file.
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }.sorted { $0.line < $1.line }
    }
}
