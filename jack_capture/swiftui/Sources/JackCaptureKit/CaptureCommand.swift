// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// A call to jack_capture: where to run it, its arguments, and the connections the application
/// makes itself when jack_capture cannot (several sources into one channel).
public struct CaptureCommand: Equatable, Sendable {
    public struct Connection: Equatable, Sendable {
        public var source: String
        public var destination: String
    }

    /// Folder to run in; a leading "~" is the home folder.
    public var directory: String
    /// Arguments after the program name, one element per word, not quoted.
    public var arguments: [String]
    public var connections: [Connection]

    /// How the call reads in a terminal: `cd`, the program with its quoted arguments, and the
    /// `jack_connect` lines the application stands for.
    public var displayText: String {
        var out = "cd \(Self.displayDirectory(directory))\n" + (["jack_capture"] + arguments.map(Self.display)).joined(separator: " ")
        if !connections.isEmpty {
            out += "\n# several sources in one channel: the application connects the ports itself (JACK adds them)\n"
            out += connections.map { "jack_connect \(Self.display($0.source)) \(Self.display($0.destination))" }.joined(separator: "\n")
        }
        return out
    }

    private static let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.,:+=%@/-")

    /// Words that are safe bare stay bare; the others are put between double quotes.
    private static func display(_ word: String) -> String {
        word.isEmpty || word.unicodeScalars.contains(where: { !plain.contains($0) }) ? quote(word) : word
    }

    private static func quote(_ word: String) -> String { "\"" + escaped(word) + "\"" }

    /// The folder as typed in a terminal, with a backslash before each character the shell would
    /// otherwise interpret (the way a terminal writes a dropped folder); the leading "~" is left bare
    /// so that the shell expands it.
    private static func displayDirectory(_ path: String) -> String {
        let bare = CharacterSet.alphanumerics.union(plain)
        var out = ""
        for (i, scalar) in path.unicodeScalars.enumerated() {
            if !(i == 0 && scalar == "~") && !bare.contains(scalar) { out.append("\\") }
            out.unicodeScalars.append(scalar)
        }
        return out
    }

    private static func escaped(_ word: String) -> String {
        var s = ""
        for c in word {
            if "\\\"$`".contains(c) { s.append("\\") }
            s.append(c)
        }
        return s
    }

    /// The command for the given settings and server sample rate.
    /// `inputConnections` tells, for each input port of the graph, what is connected to it: a channel fed
    /// by an input port receives that (jack_capture itself does so for a single `-p`; for the explicit
    /// connections the application lists them).
    public init(settings s: CaptureSettings, sampleRate: Int = 48_000, inputConnections: [String: [String]] = [:]) {
        var a = ["-c", String(s.channels)]
        if s.jackClientName != CaptureSettings.programClientName { a += ["-jn", s.jackClientName] }

        // jack_capture connects ports by position (-p), one source per channel. Without chosen sources
        // nothing is connected (-mc): the program's own default is not relied on, as it connects nothing
        // on some setups. Several sources in a channel, or a channel left empty among others, are
        // left to explicit connections.
        let perChannel = (0..<s.channels).map { $0 < s.sources.count ? s.sources[$0] : [] }
        let anySource = perChannel.contains { !$0.isEmpty }
        var conns: [Connection] = []
        if !s.autoConnect || !anySource {
            a.append("-mc")
        } else {
            if perChannel.allSatisfy({ $0.count == 1 }) {
                for ports in perChannel { a += ["-p", ports[0]] }
            } else {
                a.append("-mc")
                for (i, ports) in perChannel.enumerated() {
                    let destination = "\(s.jackClientName):input\(i + 1)"
                    for p in ports {
                        for source in inputConnections[p] ?? [p] { conns.append(Connection(source: source, destination: destination)) }
                    }
                }
            }
        }

        switch s.format {
        case .mp3: a += ["-mp3", "-mp3b", String(s.mp3Bitrate)]
        case .ogg: a += ["-f", "ogg", "-oq", String(format: "%.2f", Double(s.oggQuality) / 100)]
        case .opus: a += ["-f", "opus"]
        default:
            if s.format != .wav { a += ["-f", s.format.rawValue] }
            if let bits = s.depth.bitsOption, s.format.depths.contains(s.depth) { a += ["-b", bits] }
        }

        switch s.startMode {
        case .immediately: break
        case .transport: a.append("-jt")
        case .freewheel: a.append("-jf")
        }
        if s.scheduledStop { a += ["-d", String(max(1, s.durationSeconds))] }
        if s.timemachine { a += ["-tm", "-tmpb", String(s.timemachineSeconds)] }
        if s.writesTimeFile { a.append("-S") }
        if s.rotatesFiles { a += ["-Rf", String(max(1, s.rotationSeconds) * sampleRate)] }
        if s.bufferSeconds != 4 { a += ["-B", String(s.bufferSeconds)] }
        if s.oscEnabled { a += ["-O", String(s.oscPort)] }

        if s.numbering {
            // jack_capture tries <prefix>01.<ext>, 02, … until a name is free (two digits with -z 1).
            a += ["-fp", s.baseName + "_", "-z", "1"]
        } else {
            a.append("\(s.baseName).\(s.format.fileExtension)")
        }

        arguments = a
        connections = conns
        directory = s.folder
    }
}
