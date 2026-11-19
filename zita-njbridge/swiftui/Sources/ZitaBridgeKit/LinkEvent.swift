// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One line of the statistics that `zita-n2j --info` prints, four times a second.
public struct LinkStatistics: Equatable, Sendable {
    /// How many JACK periods the line averages (about a quarter of a second of them).
    public var periods: Int
    /// The mean error of the resampling loop, in samples.
    public var meanError: Double
    /// The resampling ratio the loop asks for: 1.0 means both ends run at the same speed.
    public var ratio: Double
    /// The smallest number of frames that were waiting in the receiver's queue during those periods. A queue that runs dry
    /// shows as a value at or below zero: that is an interruption of the sound.
    public var frames: Int

    public init(periods: Int, meanError: Double, ratio: Double, frames: Int) {
        self.periods = periods; self.meanError = meanError; self.ratio = ratio; self.frames = frames
    }

    /// The buffer margin in milliseconds. The queue holds frames at the rate of the sender.
    public func margin(senderRate: Double) -> Double {
        senderRate > 0 ? Double(frames) / senderRate * 1000 : 0
    }

    /// How far from 1.0 the ratio is, in parts per million.
    public var ratioOffsetPPM: Double { (ratio - 1) * 1_000_000 }
}

/// What `zita-n2j` (the receiver) or `zita-j2n` (the sender) tells the application.
public enum LinkEvent: Equatable, Sendable {
    /// The receiver listens and has not heard the sender yet.
    case waitingForSender
    /// The first packet of a sender arrived: where it comes from and what it sends.
    case senderFound(address: String, channels: Int, rate: Int)
    /// The length of the resampler filter that the receiver uses, in samples.
    case filterDelay(Int)
    /// The receiver is adjusting its buffer and its resampler.
    case syncing
    /// The audio flows.
    case receiving
    /// The sender was lost or something was wrong: the receiver waits this many seconds and starts again.
    case retrying(seconds: Double)
    /// The sender stopped.
    case transmitterEnded
    /// The program gives up.
    case fatal
    /// A line of statistics (only with `--info`).
    case statistics(LinkStatistics)
    /// A warning, such as "memory lock failed", which macOS always gives and which is harmless.
    case warning(String)
    /// A reason why the program cannot start: no JACK server, an address that does not resolve, an option out of range…
    case error(String)
    /// Any other line.
    case message(String)
    /// The program has ended. `requested` is true when the application asked for it.
    case exited(status: Int32, requested: Bool)
}

/// Cuts what the programs write into lines and reads them. Data may arrive in pieces: a line is understood once it is
/// complete. Both programs are run in a pseudo-terminal (their output is not flushed into a pipe), so the standard output
/// and the standard error arrive mixed, with "\r\n" at the end of the lines.
public struct LinkLogParser: Sendable {
    private var pending = Data()

    public init() {}

    public mutating func feed(_ data: Data) -> [LinkEvent] {
        pending.append(data)
        var events = [LinkEvent]()
        while let newline = pending.firstIndex(of: 0x0A) {
            let raw = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            let line = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if let event = Self.parse(line) { events.append(event) }
        }
        // A line that never ends must not grow without limit.
        if pending.count > 65_536 { pending.removeAll() }
        return events
    }

    /// The beginnings of the lines that say why a program cannot run (from `zita-n2j.cc` and `zita-j2n.cc`).
    private static let errorPrefixes = [
        "Can't connect to Jack", "Can't activate Jack", "Failed to open socket", "Address resolution failed",
        "Port number is out of range", "Bad option argument", "Format error in channel list", "Buffer time is out of range",
        "Filter delay is out of range", "Number of channels is out of range", "Multicast requires a network device",
        "Fatal error on socket", "Usage:",
    ]

    static func parse(_ line: String) -> LinkEvent? {
        guard !line.isEmpty else { return nil }
        switch line {
        case "Waiting for info packet...": return .waitingForSender
        case "Syncing...": return .syncing
        case "Receiving.": return .receiving
        case "Transmitter terminated.": return .transmitterEnded
        case "Fatal error, terminating.", "Fatal error condition, terminating.": return .fatal
        default: break
        }
        let words = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        if line.hasPrefix("Waiting for "), words.count >= 4, let seconds = Double(words[2]) { return .retrying(seconds: seconds) }
        if line.hasPrefix("From "), let sender = parseSender(line) { return sender }
        if line.hasPrefix("Resampler filter delay is "), let value = Int(line.dropFirst("Resampler filter delay is ".count).dropLast()) {
            return .filterDelay(value)
        }
        if words.count == 4, let periods = Int(words[0]), let error = Double(words[1]), let ratio = Double(words[2]), let frames = Int(words[3]) {
            return .statistics(LinkStatistics(periods: periods, meanError: error, ratio: ratio, frames: frames))
        }
        if line.hasPrefix("Warning") || line.hasPrefix("Ignored") { return .warning(line) }
        if errorPrefixes.contains(where: { line.hasPrefix($0) }) { return .error(line) }
        return .message(line)
    }

    /// "From 192.168.1.2 : 2 chan, 48000 Hz". The address may be an IPv6 one, which holds colons: cut at the last " : ".
    private static func parseSender(_ line: String) -> LinkEvent? {
        let body = line.dropFirst("From ".count)
        guard let separator = body.range(of: " : ", options: .backwards) else { return nil }
        let address = String(body[body.startIndex..<separator.lowerBound])
        let rest = body[separator.upperBound...].split(whereSeparator: { $0 == " " || $0 == "," })
        // 2 chan , 48000 Hz  ->  ["2", "chan", "48000", "Hz"]
        guard rest.count == 4, rest[1] == "chan", rest[3] == "Hz", let channels = Int(rest[0]), let rate = Int(rest[2]) else { return nil }
        return .senderFound(address: address, channels: channels, rate: rate)
    }
}
