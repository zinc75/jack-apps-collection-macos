// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Something the program would refuse, or do differently from what the matrix says: what the interface lists as "to settle".
/// The problems carry what is needed to write them in the language of the person; they have no words of their own.
public struct ConvProblem: Equatable, Sendable {
    public enum Severity: Int, Comparable, Sendable {
        /// The program runs, but not as the matrix says.
        case warning
        /// The program would refuse, or a pair would stay silent.
        case error
        public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    public enum Kind: Equatable, Sendable {
        // The setting
        /// JACK is not running, so that its rate and period cannot be checked.
        case jackNotRunning
        /// The input file of fconvolver has not the number of channels of the matrix.
        case inputFileChannels(channels: Int, expected: Int)
        /// The compensation of latency removes or shortens this many impulse responses.
        case latencyAffects(count: Int)

        // The ports
        case tooManyPorts(inputs: Int, outputs: Int, maximum: Int)
        case emptyPortName(isInput: Bool, index: Int)
        case duplicatePortName(isInput: Bool, name: String, count: Int)
        /// An input and an output have the same name: the ports of a JACK client have names of their own.
        case sharedPortName(name: String)

        // The matrix
        case noImpulse
        case fileMissing(path: String)
        case sampleRateMismatch(path: String, fileRate: Double, expectedRate: Double)
        case startBeyondEnd(offset: Int, frames: Int)
        case channelMissing(channel: Int, channels: Int)
        case hilbertLengthOutOfRange(length: Int)
        case hilbertDelayTooSmall(delay: Int, minimum: Int)
        /// A copy of a pair on which nothing is placed.
        case copyOfEmptyPair(source: ConvPair)

        // `/convolver/new`
        case partitionIllegal(Int)
        case maxLengthOutOfRange(Int)
        case maxLengthTooShort(maxLength: Int, needed: Int)
        case densityOutOfRange(Double)
    }

    public var kind: Kind
    /// The pair it is about, when it is about one.
    public var pair: ConvPair?

    public init(_ kind: Kind, pair: ConvPair? = nil) {
        self.kind = kind
        self.pair = pair
    }

    public var severity: Severity {
        switch kind {
        case .jackNotRunning, .latencyAffects, .noImpulse, .copyOfEmptyPair, .maxLengthTooShort: return .warning
        default: return .error
        }
    }
}

/// What the matrix is checked against.
public struct ConvValidationContext: Sendable {
    public enum Mode: Sendable {
        /// jconvolver, with the rate of the JACK server when it is running.
        case realTime(jackRate: Int?)
        /// fconvolver, with the file it reads (nil while it is not chosen).
        case file(input: AudioFileInfo?)
    }

    public var mode: Mode
    /// The folder of the configuration file, where the files without a `/cd` are looked for.
    public var configDirectory: String
    /// `-L`: the samples the impulse responses are moved earlier by.
    public var latencyCompensation: Int
    /// The number of inputs and of outputs the programs of this edition accept.
    public var maximumPorts: Int
    /// What is known of a sound file, by its path; nil when it is not there. Usually `AudioFileCatalog.info(at:)`.
    public var fileInfo: @Sendable (String) -> AudioFileInfo?

    public init(mode: Mode, configDirectory: String, latencyCompensation: Int = 0, maximumPorts: Int = 128,
                fileInfo: @escaping @Sendable (String) -> AudioFileInfo?) {
        self.mode = mode
        self.configDirectory = configDirectory
        self.latencyCompensation = latencyCompensation
        self.maximumPorts = maximumPorts
        self.fileInfo = fileInfo
    }
}

public enum ConvValidator {
    /// The limits of the programs (`zita-convolver.h` and `config.h` of jconvolver).
    public static let partitionRange = 64...8192
    public static let maximumLength = 0x0010_0000
    public static let hilbertLengthRange = 64...65536

    /// What is wrong with the matrix, the worst first, and in the order of the matrix within each kind of gravity.
    public static func problems(in document: ConvDocument, context: ConvValidationContext) -> [ConvProblem] {
        var out: [ConvProblem] = []
        let rate: Double?
        switch context.mode {
        case .realTime(let jackRate):
            rate = jackRate.map(Double.init)
            if jackRate == nil { out.append(ConvProblem(.jackNotRunning)) }
        case .file(let input):
            rate = input?.sampleRate
            if let input, input.channels != document.inputCount {
                out.append(ConvProblem(.inputFileChannels(channels: input.channels, expected: document.inputCount)))
            }
        }
        let isRealTime: Bool = { if case .realTime = context.mode { return true } else { return false } }()
        let compensation = isRealTime ? max(0, context.latencyCompensation) : 0

        if document.inputCount > context.maximumPorts || document.outputCount > context.maximumPorts {
            out.append(ConvProblem(.tooManyPorts(inputs: document.inputCount, outputs: document.outputCount, maximum: context.maximumPorts)))
        }
        if isRealTime { out += portProblems(document) }
        if document.placedPairs == 0 { out.append(ConvProblem(.noImpulse)) }

        var affected = 0
        var rateReported = Set<String>()
        for pair in document.content.impulses.keys.sorted() {
            for impulse in document.content.impulses[pair] ?? [] {
                switch impulse.source {
                case .file(let file, let channel):
                    if compensation > 0, impulse.delay < compensation { affected += 1 }
                    let path = ConvConfig.path(of: file, directory: impulse.directory, configDirectory: context.configDirectory)
                    guard let info = context.fileInfo(path) else { out.append(ConvProblem(.fileMissing(path: path), pair: pair)); continue }
                    if let rate, info.sampleRate != rate, rateReported.insert(path).inserted {
                        out.append(ConvProblem(.sampleRateMismatch(path: path, fileRate: info.sampleRate, expectedRate: rate), pair: pair))
                    }
                    if info.frames > 0, impulse.offset >= Int(info.frames) {
                        out.append(ConvProblem(.startBeyondEnd(offset: impulse.offset, frames: Int(info.frames)), pair: pair))
                    }
                    if channel < 1 || channel > info.channels {
                        out.append(ConvProblem(.channelMissing(channel: channel, channels: info.channels), pair: pair))
                    }
                case .dirac:
                    if compensation > 0, impulse.delay < compensation { affected += 1 }
                case .hilbert(let length):
                    if !Self.hilbertLengthRange.contains(length) {
                        out.append(ConvProblem(.hilbertLengthOutOfRange(length: length), pair: pair))
                    } else if impulse.delay < compensation + length / 2 {
                        if compensation > 0 { affected += 1 }
                        out.append(ConvProblem(.hilbertDelayTooSmall(delay: impulse.delay, minimum: compensation + length / 2), pair: pair))
                    }
                case .copy(let source):
                    if document.impulses(at: source).isEmpty { out.append(ConvProblem(.copyOfEmptyPair(source: source), pair: pair)) }
                }
            }
        }
        if affected > 0 { out.append(ConvProblem(.latencyAffects(count: affected))) }
        out += headerProblems(document, context: context)
        return out.enumerated().sorted { a, b in
            a.element.severity != b.element.severity ? a.element.severity > b.element.severity : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Pieces

    /// The names of the ports: all different, entries and exits together, and none empty.
    private static func portProblems(_ document: ConvDocument) -> [ConvProblem] {
        var out: [ConvProblem] = []
        func effective(_ ports: [ConvPortSpec], prefix: String) -> [String] {
            ports.enumerated().map { $0.element.name ?? "\(prefix)-\($0.offset + 1)" }
        }
        let inputs = effective(document.inputs, prefix: "in"), outputs = effective(document.outputs, prefix: "out")
        for (isInput, names) in [(true, inputs), (false, outputs)] {
            var counts: [String: Int] = [:]
            var order: [String] = []
            for (index, name) in names.enumerated() {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { out.append(ConvProblem(.emptyPortName(isInput: isInput, index: index))); continue }
                if counts[trimmed] == nil { order.append(trimmed) }
                counts[trimmed, default: 0] += 1
            }
            for name in order where counts[name]! > 1 { out.append(ConvProblem(.duplicatePortName(isInput: isInput, name: name, count: counts[name]!))) }
        }
        var shared = Set<String>()
        for name in inputs where outputs.contains(name) && !name.trimmingCharacters(in: .whitespaces).isEmpty {
            if shared.insert(name).inserted { out.append(ConvProblem(.sharedPortName(name: name))) }
        }
        return out
    }

    /// The numbers of `/convolver/new` that were set by hand.
    private static func headerProblems(_ document: ConvDocument, context: ConvValidationContext) -> [ConvProblem] {
        var out: [ConvProblem] = []
        if let p = document.partition, !partitionRange.contains(p) || p & (p - 1) != 0 { out.append(ConvProblem(.partitionIllegal(p))) }
        if let m = document.maxLength {
            if m > maximumLength { out.append(ConvProblem(.maxLengthOutOfRange(m))) }
            let needed = document.longestImpulse { impulse in
                guard case .file(let file, _) = impulse.source else { return nil }
                let path = ConvConfig.path(of: file, directory: impulse.directory, configDirectory: context.configDirectory)
                return context.fileInfo(path).map { Int($0.frames) }
            }
            if m <= maximumLength, m < needed { out.append(ConvProblem(.maxLengthTooShort(maxLength: m, needed: needed))) }
        }
        if let d = document.density, d < 0 || d > 1 { out.append(ConvProblem(.densityOutOfRange(d))) }
        return out
    }
}
