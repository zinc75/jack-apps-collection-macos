// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A pair of an input and an output of the matrix. Both start at 0 (the configuration files start at 1).
public struct ConvPair: Hashable, Comparable, Sendable {
    public var input: Int
    public var output: Int
    public init(input: Int, output: Int) { self.input = input; self.output = output }
    public static func < (a: ConvPair, b: ConvPair) -> Bool { (a.input, a.output) < (b.input, b.output) }
}

/// An impulse response placed on a pair.
public struct ConvImpulse: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// A channel of a sound file; the channel starts at 1, as in the file.
        case file(path: String, channel: Int)
        /// A single sample.
        case dirac
        /// A Hilbert filter of this length.
        case hilbert(length: Int)
        /// The impulse responses of another pair, shared (the configuration file says it with `/impulse/copy`).
        case copy(of: ConvPair)
    }

    public var source: Source
    /// Linear gain (not dB). The configuration files say it this way, and so it comes back as it was.
    public var gain: Double
    /// Samples of silence put before the impulse response.
    public var delay: Int
    /// Frames skipped at the start of the file (a file only).
    public var offset: Int
    /// Frames used, 0 for all of them (a file only).
    public var length: Int
    /// The folder in which a file is looked for, as the last `/cd` said it; nil for the folder of the configuration file.
    public var directory: String?

    public init(source: Source, gain: Double = 1, delay: Int = 0, offset: Int = 0, length: Int = 0, directory: String? = nil) {
        self.source = source
        self.gain = gain
        self.delay = delay
        self.offset = offset
        self.length = length
        self.directory = directory
    }

    /// The gain in dB; -infinity for a gain of 0.
    public var gainDB: Double {
        get { gain > 0 ? 20 * log10(gain) : -.infinity }
        set { gain = pow(10, newValue / 20) }
    }
}

/// What a port has in the file: a name of its own, and the ports to connect it to.
public struct ConvPortSpec: Equatable, Sendable {
    public var name: String?
    public var connections: [String]
    public init(name: String? = nil, connections: [String] = []) { self.name = name; self.connections = connections }
    public init(name: String? = nil, connection: String?) { self.init(name: name, connections: connection.map { [$0] } ?? []) }
    /// The first port: the one that every version of jconvolver connects.
    public var connection: String? {
        get { connections.first }
        set { connections = newValue.map { [$0] } ?? [] }
    }
    /// Whether the file has to say something about this port.
    public var isCustom: Bool { name != nil || !connections.isEmpty }
}

/// The three numbers of `/convolver/new`.
public struct ConvHeader: Equatable, Sendable {
    public var partition: Int
    public var maxLength: Int
    public var density: Double?
    public init(partition: Int, maxLength: Int, density: Double? = nil) {
        self.partition = partition
        self.maxLength = maxLength
        self.density = density
    }
}

/// The matrix of convolutions of a configuration file, as the application edits it: the inputs and outputs, the impulse
/// responses on each pair, and the few settings of the file.
///
/// A document that was read from a file and is not changed is written back as the file was, comments and spacing included.
/// Once it is changed, it is written again as a whole, in a regular order (the comments after the first command are lost).
@dynamicMemberLookup
public struct ConvDocument: Equatable, Sendable {
    public struct Content: Equatable, Sendable {
        /// `/jack/client` and `/jack/server`.
        public var client: String?
        public var server: String?
        public var inputs: [ConvPortSpec]
        public var outputs: [ConvPortSpec]
        /// The numbers of `/convolver/new` that the person set by hand; nil lets the application work them out.
        public var partition: Int?
        public var maxLength: Int?
        public var density: Double?
        public var impulses: [ConvPair: [ConvImpulse]]
        /// The comment lines at the top of the file, kept as they are.
        public var preamble: [String]

        public init(inputs: Int = 0, outputs: Int = 0) {
            self.inputs = Array(repeating: ConvPortSpec(), count: inputs)
            self.outputs = Array(repeating: ConvPortSpec(), count: outputs)
            self.impulses = [:]
            self.preamble = []
        }
    }

    private struct Origin: Equatable, Sendable {
        var config: ConvConfig
        var content: Content
    }

    public var content: Content
    private var origin: Origin?

    public subscript<T>(dynamicMember keyPath: WritableKeyPath<Content, T>) -> T {
        get { content[keyPath: keyPath] }
        set { content[keyPath: keyPath] = newValue }
    }

    /// An empty matrix.
    public init(inputs: Int, outputs: Int) {
        content = Content(inputs: inputs, outputs: outputs)
    }

    // MARK: Reading

    /// What is read from a file, and what could not be placed.
    public struct Import: Sendable {
        public var document: ConvDocument
        /// What the lines of the file say that does not fit (a port that does not exist, a copy of a pair that is not there).
        public var issues: [ConfIssue]
    }

    public static func make(from config: ConvConfig) -> Import {
        var content = Content()
        var issues: [ConfIssue] = []
        var seenCommand = false
        var seenConvolver = false

        for (index, line) in config.lines.enumerated() {
            let number = index + 1
            switch line.kind {
            case .blank, .comment:
                if !seenCommand { content.preamble.append(line.text) }
                continue
            case .jackClient(let name): if content.client == nil { content.client = name }
            case .jackServer(let name): if content.server == nil { content.server = name }
            case .convolverNew(let i, let o, let p, let m, let d):
                if !seenConvolver {
                    seenConvolver = true
                    content.inputs = Array(repeating: ConvPortSpec(), count: i)
                    content.outputs = Array(repeating: ConvPortSpec(), count: o)
                    content.partition = p
                    content.maxLength = m
                    content.density = d
                }
            case .inputName(let n, let name, let connections):
                if n >= 1, n <= content.inputs.count { content.inputs[n - 1] = ConvPortSpec(name: name, connections: connections) }
                else { issues.append(ConfIssue(line: number, message: "Bad input or output number.")) }
            case .outputName(let n, let name, let connections):
                if n >= 1, n <= content.outputs.count { content.outputs[n - 1] = ConvPortSpec(name: name, connections: connections) }
                else { issues.append(ConfIssue(line: number, message: "Bad input or output number.")) }
            default: break
            }
            seenCommand = true
        }

        for placement in config.placements {
            switch placement.kind {
            case .read(let r):
                add(pair: (r.input, r.output), line: placement.line, to: &content, issues: &issues,
                    ConvImpulse(source: .file(path: r.file, channel: r.channel), gain: r.gain, delay: r.delay, offset: r.offset, length: r.length, directory: placement.directory))
            case .dirac(let i, let o, let g, let d):
                add(pair: (i, o), line: placement.line, to: &content, issues: &issues, ConvImpulse(source: .dirac, gain: g, delay: d))
            case .hilbert(let i, let o, let g, let d, let l):
                add(pair: (i, o), line: placement.line, to: &content, issues: &issues, ConvImpulse(source: .hilbert(length: l), gain: g, delay: d))
            case .copy(let i, let o, let fi, let fo):
                guard fi >= 1, fi <= content.inputs.count, fo >= 1, fo <= content.outputs.count else {
                    issues.append(ConfIssue(line: placement.line, message: "Bad input or output number.")); continue
                }
                add(pair: (i, o), line: placement.line, to: &content, issues: &issues,
                    ConvImpulse(source: .copy(of: ConvPair(input: fi - 1, output: fo - 1))))
            default: break
            }
        }

        var document = ConvDocument(inputs: 0, outputs: 0)
        document.content = content
        document.origin = Origin(config: config, content: content)
        return Import(document: document, issues: issues)
    }

    private static func add(pair: (Int, Int), line: Int, to content: inout Content, issues: inout [ConfIssue], _ impulse: ConvImpulse) {
        guard pair.0 >= 1, pair.0 <= content.inputs.count, pair.1 >= 1, pair.1 <= content.outputs.count else {
            issues.append(ConfIssue(line: line, message: "Bad input or output number."))
            return
        }
        content.impulses[ConvPair(input: pair.0 - 1, output: pair.1 - 1), default: []].append(impulse)
    }

    // MARK: Editing

    public var isModified: Bool { origin?.content != content }

    /// The document has been written as this configuration: it is not modified any more, and comes out as this text while it
    /// is not changed again.
    public mutating func markSaved(as config: ConvConfig) { origin = Origin(config: config, content: content) }

    public var inputCount: Int { content.inputs.count }
    public var outputCount: Int { content.outputs.count }

    public func impulses(at pair: ConvPair) -> [ConvImpulse] { content.impulses[pair] ?? [] }

    public mutating func add(_ impulse: ConvImpulse, at pair: ConvPair) {
        guard pair.input >= 0, pair.input < inputCount, pair.output >= 0, pair.output < outputCount else { return }
        content.impulses[pair, default: []].append(impulse)
    }

    public mutating func replace(_ impulse: ConvImpulse, at index: Int, of pair: ConvPair) {
        guard var list = content.impulses[pair], list.indices.contains(index) else { return }
        list[index] = impulse
        content.impulses[pair] = list
    }

    public mutating func remove(at index: Int, of pair: ConvPair) {
        guard var list = content.impulses[pair], list.indices.contains(index) else { return }
        list.remove(at: index)
        content.impulses[pair] = list.isEmpty ? nil : list
    }

    public mutating func clear(_ pair: ConvPair) { content.impulses[pair] = nil }

    /// Changes the number of inputs and outputs. What is placed on a pair that goes away goes with it; a copy of such a
    /// pair becomes nothing.
    public mutating func resize(inputs: Int, outputs: Int) {
        func fit(_ ports: inout [ConvPortSpec], to count: Int) {
            if ports.count > count { ports.removeLast(ports.count - count) }
            else { ports += Array(repeating: ConvPortSpec(), count: count - ports.count) }
        }
        fit(&content.inputs, to: max(0, inputs))
        fit(&content.outputs, to: max(0, outputs))
        var kept: [ConvPair: [ConvImpulse]] = [:]
        for (pair, list) in content.impulses where pair.input < inputCount && pair.output < outputCount {
            let valid = list.filter { impulse in
                if case .copy(let source) = impulse.source { return source.input < inputCount && source.output < outputCount }
                return true
            }
            if !valid.isEmpty { kept[pair] = valid }
        }
        content.impulses = kept
    }

    // MARK: What it says

    /// The number of pairs that have something placed on them.
    public var placedPairs: Int { content.impulses.values.filter { !$0.isEmpty }.count }

    /// The share of the pairs that have an impulse response: what `/convolver/new` calls the density.
    public var pairDensity: Double {
        let total = inputCount * outputCount
        return total > 0 ? Double(placedPairs) / Double(total) : 0
    }

    /// The length, in samples, of the longest convolution: what the maximum length of `/convolver/new` has to cover.
    /// - Parameter lengthOfFile: the number of frames of the sound file of an impulse response (its folder is the one of the
    ///   impulse response); nil when it cannot be read.
    public func longestImpulse(lengthOfFile: (ConvImpulse) -> Int?) -> Int {
        func end(_ impulse: ConvImpulse, _ pair: ConvPair, depth: Int = 0) -> Int {
            switch impulse.source {
            case .dirac: return impulse.delay + 1
            case .hilbert(let length): return impulse.delay + length / 2
            case .file:
                if impulse.length > 0 { return impulse.delay + impulse.length }
                guard let frames = lengthOfFile(impulse) else { return impulse.delay }
                return impulse.delay + max(0, frames - impulse.offset)
            case .copy(let source):
                guard depth < 8 else { return 0 }
                return (content.impulses[source] ?? []).map { end($0, source, depth: depth + 1) }.max() ?? 0
            }
        }
        return content.impulses.flatMap { pair, list in list.map { end($0, pair) } }.max() ?? 0
    }

    /// The numbers of `/convolver/new` the application works out when the person did not set them: a partition of the
    /// period of JACK (no latency is added), the length of the longest convolution, and the density of the matrix.
    public func automaticHeader(period: Int, lengthOfFile: (ConvImpulse) -> Int?) -> ConvHeader {
        ConvHeader(partition: period, maxLength: max(longestImpulse(lengthOfFile: lengthOfFile), 1), density: (pairDensity * 100).rounded() / 100)
    }

    // MARK: Writing

    /// The configuration file.
    /// - Parameter automatic: the numbers of `/convolver/new` to use for those the person did not set.
    public func makeConfig(automatic: ConvHeader) -> ConvConfig {
        if let origin, origin.content == content { return origin.config }
        var lines: [ConfLine] = content.preamble.map { text in
            ConfLine(text.trimmingCharacters(in: .whitespaces).isEmpty ? .blank : .comment(text), source: text)
        }
        if let client = content.client { lines.append(ConfLine(.jackClient(client))) }
        if let server = content.server { lines.append(ConfLine(.jackServer(server))) }
        lines.append(ConfLine(.convolverNew(inputs: inputCount, outputs: outputCount,
                                            partition: content.partition ?? automatic.partition,
                                            maxLength: content.maxLength ?? automatic.maxLength,
                                            density: content.density ?? automatic.density)))
        for (i, port) in content.inputs.enumerated() where port.isCustom {
            lines.append(ConfLine(.inputName(number: i + 1, name: port.name ?? "in-\(i + 1)", connections: port.connections)))
        }
        for (o, port) in content.outputs.enumerated() where port.isCustom {
            lines.append(ConfLine(.outputName(number: o + 1, name: port.name ?? "out-\(o + 1)", connections: port.connections)))
        }

        // Files are grouped by folder so that a `/cd` is written once for each, the pulses and filters come first, and a
        // copy comes after everything it may copy.
        var entries: [(pair: ConvPair, impulse: ConvImpulse)] = []
        for pair in content.impulses.keys.sorted() {
            for var impulse in content.impulses[pair] ?? [] {
                // A file given with a whole path is written as a folder (`/cd`, once for all the files of the folder) and a name.
                if case .file(let path, let channel) = impulse.source, impulse.directory == nil, path.hasPrefix("/") {
                    impulse.directory = (path as NSString).deletingLastPathComponent
                    impulse.source = .file(path: (path as NSString).lastPathComponent, channel: channel)
                }
                entries.append((pair, impulse))
            }
        }
        func isCopy(_ i: ConvImpulse) -> Bool { if case .copy = i.source { return true } else { return false } }
        func isFile(_ i: ConvImpulse) -> Bool { if case .file = i.source { return true } else { return false } }

        for entry in entries where !isFile(entry.impulse) && !isCopy(entry.impulse) { lines.append(ConfLine(Self.kind(entry.pair, entry.impulse))) }
        var seen: [String?] = []
        for entry in entries where isFile(entry.impulse) && !seen.contains(entry.impulse.directory) { seen.append(entry.impulse.directory) }
        // The files of the folder of the configuration come first: they must not follow a `/cd`.
        let directories = seen.filter { $0 == nil } + seen.filter { $0 != nil }
        var current: String??
        for directory in directories {
            for entry in entries where isFile(entry.impulse) && entry.impulse.directory == directory {
                if directory != nil, current != .some(directory) { lines.append(ConfLine(.changeDirectory(directory!))); current = .some(directory) }
                lines.append(ConfLine(Self.kind(entry.pair, entry.impulse)))
            }
        }
        for entry in entries where isCopy(entry.impulse) { lines.append(ConfLine(Self.kind(entry.pair, entry.impulse))) }
        return ConvConfig(lines: lines, endsWithNewline: true)
    }

    private static func kind(_ pair: ConvPair, _ impulse: ConvImpulse) -> ConfLine.Kind {
        let i = pair.input + 1, o = pair.output + 1
        switch impulse.source {
        case .file(let path, let channel):
            return .read(.init(input: i, output: o, gain: impulse.gain, delay: impulse.delay, offset: impulse.offset, length: impulse.length, channel: channel, file: path))
        case .dirac: return .dirac(input: i, output: o, gain: impulse.gain, delay: impulse.delay)
        case .hilbert(let length): return .hilbert(input: i, output: o, gain: impulse.gain, delay: impulse.delay, length: length)
        case .copy(let source): return .copy(input: i, output: o, fromInput: source.input + 1, fromOutput: source.output + 1)
        }
    }
}
