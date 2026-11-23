// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One line of what jconvolver or fconvolver writes, understood.
///
/// The texts are the ones of the programs (`jconvolver.cc`, `config.cc`, `jconfig.cc`, `jclient.cc`, `fconvolver.cc`). While
/// all goes well they say nothing at all.
public struct EngineMessage: Equatable, Sendable {
    public enum Severity: Int, Comparable, Sendable {
        case info, warning, error
        public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    /// Why the real-time program ended on its own. It does so with the exit code 0 whatever the reason, so the exit code
    /// says nothing: only these messages do.
    public enum StopReason: String, Equatable, Sendable {
        /// "CPU overload, exiting."
        case overload
        /// "Jack buffer size change, exiting."
        case bufferSizeChange
        /// "Zombified by Jack, exiting."
        case zombified
    }

    public enum Kind: Equatable, Sendable {
        /// "Line N: First K frames removed by latency compensation."
        case latencyCompensated(line: Int, frames: Int)
        /// "Line N: Dirac pulse removed: delay < latency." and the same for a Hilbert filter.
        case impulseRemoved(line: Int)
        /// "Line N: Sample rate (R) of 'path' does not match." The file is read all the same.
        case sampleRateMismatch(line: Int, rate: Int, path: String)
        /// "Line N: Data truncated." The impulse response is longer than the convolver.
        case dataTruncated(line: Int)
        /// "Line N: partition size adjusted to S."
        case partitionAdjusted(line: Int, size: Int)
        /// "Line N: Unable to open 'path'."
        case fileUnreadable(line: Int, path: String)
        /// Any other refusal of a line: a syntax error, a wrong number, a channel that does not exist...
        case configError(line: Int, text: String)
        /// "Computation threads are late (0001)." A cycle of JACK that the computation did not finish in time.
        case threadsLate(flags: Int)
        /// "client NAME": the name JACK gave the client of jconvolver (written by the 0005 patch). A name with a suffix means that another client had the one asked.
        case clientName(String)
        /// The program ends on its own.
        case stopped(StopReason)
        /// The program cannot start: no JACK server, a configuration file that is not there, a file that does not match...
        case cannotStart
        /// Anything else.
        case other
    }

    public var text: String
    public var kind: Kind

    public init(text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }

    public var severity: Severity {
        switch kind {
        case .latencyCompensated, .impulseRemoved, .sampleRateMismatch, .dataTruncated, .partitionAdjusted, .threadsLate: return .warning
        case .fileUnreadable, .configError, .stopped, .cannotStart: return .error
        case .clientName, .other: return .info
        }
    }

    /// The reason, when the message says that the program ended on its own.
    public var stopReason: StopReason? {
        if case .stopped(let reason) = kind { return reason }
        return nil
    }

    /// Understands a line (without its line break).
    public static func classify(_ text: String) -> EngineMessage {
        EngineMessage(text: text, kind: kind(of: text))
    }

    private static func kind(of text: String) -> Kind {
        switch text {
        case "CPU overload, exiting.": return .stopped(.overload)
        case "Jack buffer size change, exiting.": return .stopped(.bufferSizeChange)
        case "Zombified by Jack, exiting.": return .stopped(.zombified)
        default: break
        }
        if let m = match(#"^Computation threads are late \(([0-9a-fA-F]+)\)\.$"#, text), let flags = Int(m[1], radix: 16) {
            return .threadsLate(flags: flags)
        }
        if let m = match(#"^Line (\d+): (.*)$"#, text), let line = Int(m[1]) {
            let body = m[2]
            if let k = match(#"^First (\d+) frames removed by latency compensation\.$"#, body), let frames = Int(k[1]) {
                return .latencyCompensated(line: line, frames: frames)
            }
            if body.hasPrefix("Dirac pulse removed") || body.hasPrefix("Hilbert impulse removed") { return .impulseRemoved(line: line) }
            if let k = match(#"^Sample rate \((\d+)\) of '(.*)' does not match\.$"#, body), let rate = Int(k[1]) {
                return .sampleRateMismatch(line: line, rate: rate, path: k[2])
            }
            if body == "Data truncated." { return .dataTruncated(line: line) }
            if let k = match(#"^partition size adjusted to (\d+)\.$"#, body), let size = Int(k[1]) {
                return .partitionAdjusted(line: line, size: size)
            }
            if let k = match(#"^Unable to open '(.*)'\.$"#, body) { return .fileUnreadable(line: line, path: k[1]) }
            return .configError(line: line, text: body)
        }
        // What follows "client " is the name, spaces included.
        if let m = match(#"^client (.+)$"#, text) { return .clientName(m[1]) }
        let startupFailures = [
            "Can't connect to JACK", "Can't activate JACK.", "Fragment size is too small", "Fragment size is too large",
            "Zita-convolver does not match compile-time version.", "Can't initialise convolution engine.",
            "Can't initialise convolution engine",
        ]
        if startupFailures.contains(text) { return .cannotStart }
        if match(#"^Can't open '.*' for reading$"#, text) != nil { return .cannotStart }
        if match(#"^Unable to (read input|create output) file '.*'$"#, text) != nil { return .cannotStart }
        if text.hasPrefix("Number of inputs (") && text.contains("doesn't match input file") { return .cannotStart }
        return .other
    }

    /// The groups of the first match of a pattern: [whole, group 1, group 2...].
    private static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }
}

/// Cuts what a program writes into lines and understands them. The bytes come in pieces of any size.
public struct EngineLogParser: Sendable {
    private var pending = Data()

    public init() {}

    /// The complete lines of what has come so far. An empty line is dropped.
    public mutating func feed(_ data: Data) -> [EngineMessage] {
        pending.append(data)
        var out: [EngineMessage] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<newline]
            pending = Data(pending[(newline + 1)...])
            if let message = Self.message(from: line) { out.append(message) }
        }
        return out
    }

    /// What was written after the last line break, when the program ends.
    public mutating func finish() -> [EngineMessage] {
        defer { pending = Data() }
        return Self.message(from: pending).map { [$0] } ?? []
    }

    private static func message(from bytes: Data) -> EngineMessage? {
        var text = String(decoding: bytes, as: UTF8.self)
        // The pseudo-terminal turns a line feed into a carriage return and a line feed.
        while text.last == "\r" { text.removeLast() }
        text = text.replacingOccurrences(of: "\r", with: "")
        return text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : EngineMessage.classify(text)
    }
}
