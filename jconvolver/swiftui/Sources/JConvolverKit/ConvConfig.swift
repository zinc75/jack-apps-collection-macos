// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One line of a configuration file (the format is described in `README.CONFIG` of jconvolver).
///
/// The numbers of inputs, outputs and channels are the ones of the file, which start at 1.
public struct ConfLine: Equatable, Sendable {
    public struct Read: Equatable, Sendable {
        public var input: Int, output: Int
        /// Linear gain (not dB).
        public var gain: Double
        /// Samples of silence put before the impulse response.
        public var delay: Int
        /// Frames skipped at the start of the file.
        public var offset: Int
        /// Frames used, 0 for all of them.
        public var length: Int
        public var channel: Int
        public var file: String

        public init(input: Int, output: Int, gain: Double, delay: Int, offset: Int, length: Int, channel: Int, file: String) {
            self.input = input; self.output = output; self.gain = gain; self.delay = delay
            self.offset = offset; self.length = length; self.channel = channel; self.file = file
        }
    }

    public enum Kind: Equatable, Sendable {
        case blank
        /// A line starting with `#`, as it is written.
        case comment(String)
        case jackClient(String)
        case jackServer(String)
        case convolverNew(inputs: Int, outputs: Int, partition: Int, maxLength: Int, density: Double?)
        /// A name for an input, and the ports to connect it to (several on a line is what the 0004 patch of jconvolver reads;
        /// a jconvolver without it connects the first and ignores the others).
        case inputName(number: Int, name: String, connections: [String])
        case outputName(number: Int, name: String, connections: [String])
        case changeDirectory(String)
        case read(Read)
        case dirac(input: Int, output: Int, gain: Double, delay: Int)
        case hilbert(input: Int, output: Int, gain: Double, delay: Int, length: Int)
        case copy(input: Int, output: Int, fromInput: Int, fromOutput: Int)
        /// A line the program would refuse, as it is written.
        case invalid(String)
    }

    public var kind: Kind
    /// The text of the line as it was read. It is kept while the line is not changed, so that a file that is opened and
    /// saved without change comes out as it was, comments and spacing included.
    public var source: String?

    public init(_ kind: Kind, source: String? = nil) {
        self.kind = kind
        self.source = source
    }

    /// The text of the line: the one that was read if the line was not changed, else the one written from its content.
    public var text: String { source ?? kind.formatted }
}

extension ConfLine.Kind {
    private static func number(_ v: Double) -> String { String(format: "%.9g", v) }

    /// The line as it is written in a file.
    public var formatted: String {
        func words(_ name: String, _ connections: [String]) -> String {
            ([name] + connections).map { ConfWord.format($0) }.joined(separator: " ")
        }
        switch self {
        case .blank: return ""
        case .comment(let text): return text
        case .jackClient(let name): return "/jack/client " + ConfWord.format(name)
        case .jackServer(let name): return "/jack/server " + ConfWord.format(name)
        case .convolverNew(let i, let o, let p, let m, let d):
            return "/convolver/new \(i) \(o) \(p) \(m)" + (d.map { " " + Self.number($0) } ?? "")
        case .inputName(let n, let name, let connections): return "/input/name \(n) " + words(name, connections)
        case .outputName(let n, let name, let connections): return "/output/name \(n) " + words(name, connections)
        case .changeDirectory(let path): return "/cd " + ConfWord.format(path)
        case .read(let r):
            return "/impulse/read \(r.input) \(r.output) \(Self.number(r.gain)) \(r.delay) \(r.offset) \(r.length) \(r.channel) " + ConfWord.format(r.file)
        case .dirac(let i, let o, let g, let d): return "/impulse/dirac \(i) \(o) \(Self.number(g)) \(d)"
        case .hilbert(let i, let o, let g, let d, let l): return "/impulse/hilbert \(i) \(o) \(Self.number(g)) \(d) \(l)"
        case .copy(let i, let o, let fi, let fo): return "/impulse/copy \(i) \(o) \(fi) \(fo)"
        case .invalid(let text): return text
        }
    }
}

/// A line that jconvolver would refuse, with the words it uses for it.
public struct ConfIssue: Equatable, Sendable {
    /// Starts at 1.
    public var line: Int
    public var message: String
    public init(line: Int, message: String) { self.line = line; self.message = message }
}

/// An impulse response placed on a pair of input and output, in the order of the file, with the folder in force.
public struct ConfPlacement: Equatable, Sendable {
    /// The number of the line, from 1.
    public var line: Int
    /// `.read`, `.dirac`, `.hilbert` or `.copy`.
    public var kind: ConfLine.Kind
    /// What the last `/cd` before the line said; nil when there was none (the folder of the file itself is then used).
    public var directory: String?
}

/// A configuration file of jconvolver and fconvolver, as lines. The language is imperative: the order of the lines is
/// the meaning (a `/cd` applies to the lines that follow it), so it is kept.
public struct ConvConfig: Equatable, Sendable {
    public var lines: [ConfLine]
    /// Whether the text ends with a line break.
    public var endsWithNewline: Bool

    public init(lines: [ConfLine] = [], endsWithNewline: Bool = true) {
        self.lines = lines
        self.endsWithNewline = endsWithNewline
    }

    // MARK: Reading

    /// Reads a file, with the way the program reads it: what it would refuse is kept as an `.invalid` line and reported,
    /// the rest is read.
    public static func parse(_ text: String) -> (config: ConvConfig, issues: [ConfIssue]) {
        var pieces = text.components(separatedBy: "\n")
        var endsWithNewline = false
        if pieces.last == "" { pieces.removeLast(); endsWithNewline = true }
        var lines: [ConfLine] = []
        var issues: [ConfIssue] = []
        for (index, raw) in pieces.enumerated() {
            let (kind, problem) = parseLine(raw)
            lines.append(ConfLine(kind, source: raw))
            if let problem { issues.append(ConfIssue(line: index + 1, message: problem)) }
        }
        return (ConvConfig(lines: lines, endsWithNewline: endsWithNewline), issues)
    }

    /// Sees the text of a line: its meaning, and the reason why the program would refuse it (nil when it would not).
    static func parseLine(_ raw: String) -> (ConfLine.Kind, String?) {
        guard raw.first == "/" else {
            let trimmed = raw.drop { $0.isWhitespace }
            guard let c = trimmed.unicodeScalars.first else { return (.blank, nil) }
            if c == "#" { return (.comment(raw), nil) }
            if c.value > 32 { return (.invalid(raw), "Syntax error.") }
            return (.blank, nil)
        }
        // The command ends at the first blank; the arguments start at the next word.
        let end = raw.firstIndex { $0.isWhitespace || ($0.unicodeScalars.first?.value ?? 32) < 32 } ?? raw.endIndex
        let command = String(raw[..<end])
        var scan = ArgScanner(rest: raw[end...])
        let badParameters: (ConfLine.Kind, String?) = (.invalid(raw), "Bad or missing parameters.")

        switch command {
        case "/cd":
            guard let w = scan.word() else { return badParameters }
            return (.changeDirectory(w), nil)
        case "/jack/client":
            guard let w = scan.word() else { return badParameters }
            return (.jackClient(w), nil)
        case "/jack/server":
            guard let w = scan.word() else { return badParameters }
            return (.jackServer(w), nil)
        case "/convolver/new":
            guard let i = scan.int(), let o = scan.int(), let p = scan.int(), let m = scan.int() else { return badParameters }
            return (.convolverNew(inputs: i, outputs: o, partition: p, maxLength: m, density: scan.double()), nil)
        case "/input/name", "/output/name":
            guard let n = scan.int(), let name = scan.word() else { return badParameters }
            // The ports to connect to: as many as the line has. The empty word is none, and text from a `#` is not a port.
            var connections: [String] = []
            while let w = scan.word(), !w.hasPrefix("#") { if !w.isEmpty { connections.append(w) } }
            return (command == "/input/name" ? .inputName(number: n, name: name, connections: connections)
                                             : .outputName(number: n, name: name, connections: connections), nil)
        case "/impulse/read":
            guard let i = scan.int(), let o = scan.int(), let g = scan.double(), let d = scan.int(), let off = scan.int(),
                  let len = scan.int(), let ch = scan.int(), let file = scan.word() else { return badParameters }
            return (.read(.init(input: i, output: o, gain: g, delay: d, offset: off, length: len, channel: ch, file: file)), nil)
        case "/impulse/dirac":
            guard let i = scan.int(), let o = scan.int(), let g = scan.double(), let d = scan.int() else { return badParameters }
            return (.dirac(input: i, output: o, gain: g, delay: d), nil)
        case "/impulse/hilbert":
            guard let i = scan.int(), let o = scan.int(), let g = scan.double(), let d = scan.int(), let l = scan.int() else { return badParameters }
            return (.hilbert(input: i, output: o, gain: g, delay: d, length: l), nil)
        case "/impulse/copy":
            guard let i = scan.int(), let o = scan.int(), let fi = scan.int(), let fo = scan.int() else { return badParameters }
            return (.copy(input: i, output: o, fromInput: fi, fromOutput: fo), nil)
        default:
            return (.invalid(raw), "Unknown command.")
        }
    }

    // MARK: Writing

    /// The text of the file.
    public var text: String {
        lines.map(\.text).joined(separator: "\n") + (endsWithNewline && !lines.isEmpty ? "\n" : "")
    }

    // MARK: What it says

    /// What the first `/convolver/new` says: inputs, outputs, partition size, maximum length, density.
    public var convolver: (inputs: Int, outputs: Int, partition: Int, maxLength: Int, density: Double?)? {
        for line in lines {
            if case .convolverNew(let i, let o, let p, let m, let d) = line.kind { return (i, o, p, m, d) }
        }
        return nil
    }

    /// The impulse responses, in the order of the file, each with the folder in force.
    public var placements: [ConfPlacement] {
        var directory: String?
        var out: [ConfPlacement] = []
        for (index, line) in lines.enumerated() {
            switch line.kind {
            case .changeDirectory(let path): directory = path
            case .read, .dirac, .hilbert, .copy: out.append(ConfPlacement(line: index + 1, kind: line.kind, directory: directory))
            default: break
            }
        }
        return out
    }

    /// Where the program looks for a file of impulse responses: an absolute path as it is, else in the folder of the last
    /// `/cd` (which itself may be relative), else in the folder of the configuration file. As `config.cc` does.
    /// A folder that ends with a slash (`/cd /ir/`) gives `/ir/a.wav`, not `/ir//a.wav`: the same file must have the same path
    /// whichever way it is reached, since the list of files and the matrix compare paths.
    public static func path(of file: String, directory: String?, configDirectory: String) -> String {
        if file.hasPrefix("/") { return file }
        let folder = directory ?? configDirectory
        return folder.hasSuffix("/") ? folder + file : folder + "/" + file
    }
}

/// Reads the numbers and the words that follow a command.
struct ArgScanner {
    var rest: Substring

    private mutating func token() -> Substring? {
        rest = rest.drop { $0.isWhitespace }
        guard !rest.isEmpty else { return nil }
        let end = rest.firstIndex { $0.isWhitespace } ?? rest.endIndex
        let token = rest[..<end]
        rest = rest[end...]
        return token
    }

    mutating func int() -> Int? {
        let saved = rest
        guard let t = token(), let v = Int(t), v >= 0 else { rest = saved; return nil }
        return v
    }

    mutating func double() -> Double? {
        let saved = rest
        guard let t = token(), let v = Double(t), v.isFinite else { rest = saved; return nil }
        return v
    }

    mutating func word() -> String? {
        guard let (word, next) = ConfWord.read(rest) else { return nil }
        rest = next
        return word
    }
}
