// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import MeterKit

/// The status line jack_capture prints about once a second: the buffer, the time, the incidents.
public struct CaptureStatus: Equatable, Sendable {
    /// Free room in the memory buffer, and its size, in seconds.
    public var bufferFree: Double
    public var bufferTotal: Double
    /// True when the disk thread runs at a higher priority, as it does when the buffer fills up.
    public var diskThreadHighPriority: Bool
    public var overruns: Int
    public var xruns: Int
}

/// The meter scale of jack_capture, taken from meterbridge by Steve Harris: a deflection in percent for a level in dB.
/// The levels of the console meter are on this scale (1 is 0 dBFS, 0.5 is about -20 dB). It is the scale of the
/// meters of this interface, and stays here, under the licence of jack_capture, not in MeterKit.
public struct IECScale: MeterScale {
    public init() {}

    public func fraction(db: Double) -> Double { Self.fraction(db: db) }

    /// 0...1 for a level in dBFS.
    public static func fraction(db: Double) -> Double {
        let def: Double
        switch db {
        case ..<(-70): def = 0
        case ..<(-60): def = (db + 70) * 0.25
        case ..<(-50): def = (db + 60) * 0.5 + 5
        case ..<(-40): def = (db + 50) * 0.75 + 7.5
        case ..<(-30): def = (db + 40) * 1.5 + 15
        case ..<(-20): def = (db + 30) * 2 + 30
        case ..<0: def = (db + 20) * 2.5 + 50
        default: def = 100
        }
        return def / 100
    }
}

/// What jack_capture says, as the interface understands it.
public enum CaptureEvent: Equatable, Sendable {
    /// The file the recording is written to.
    case recording(file: String)
    /// Timemachine: listening, waiting for Return.
    case waitingToStart(file: String)
    /// Waiting for the JACK transport, or for freewheeling.
    case waitingForJack(String)
    case status(CaptureStatus)
    /// The levels of all the channels, from its console meter.
    case meters([ChannelMeter])
    /// The buffer is being written to the disk after a stop.
    case flushing
    case finished
    /// Anything else it says on its error output: a refused port, an unwritable file.
    case message(String)
}

/// Reads the two outputs of jack_capture. It prints with ANSI colours and cursor moves, and redraws the level
/// meters in place: the parser removes them and looks for the lines that matter.
public final class CaptureLogParser {
    private var out = ""
    private var err = ""

    public init() {}

    private static let escapes = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[A-Za-z]")
    /// The sign put in place of the yellow colour code: in timemachine mode, the meter row is cut there.
    private static let cut: Character = "¦"
    private static let meterRow = try! NSRegularExpression(pattern: "([0-9]{2}):\\|([ \\-*]{65})([|!])")
    private static let meterRowWaiting = try! NSRegularExpression(pattern: "([0-9]{2}):\\|([^¦\\n|]*)¦")
    private static let status = try! NSRegularExpression(
        pattern: "Buffer:\\s*([0-9.]+)s\\./([0-9.]+)s\\s+Time:\\s*[0-9.]+m\\.\\s+DHP:\\s*\\[(.?)\\]\\s+Overruns:\\s*([0-9]+)\\s+Xruns:\\s*([0-9]+)")

    static func clean(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return escapes.stringByReplacingMatches(in: text, range: range, withTemplate: "").replacingOccurrences(of: "\r", with: "")
    }

    /// Standard output: the meters and the status line.
    public func feedOutput(_ chunk: String) -> [CaptureEvent] {
        out += Self.clean(chunk.replacingOccurrences(of: "\u{1B}[33m", with: String(Self.cut)))
        var events: [CaptureEvent] = []
        if out.contains(">>> Please wait while writing") {
            events.append(.flushing)
            out = out.replacingOccurrences(of: ">>> Please wait while writing all data to disk. (shouldn't take long)", with: "")
        }
        var consumed = out.startIndex
        if let meters = readMeters() {
            events.append(.meters(meters.levels))
            consumed = meters.end
        }
        let range = NSRange(out.startIndex..., in: out)
        let matches = Self.status.matches(in: out, range: range)
        if let last = matches.last, let all = Range(last.range, in: out) {
            func group(_ i: Int) -> String { Range(last.range(at: i), in: out).map { String(out[$0]) } ?? "" }
            events.append(.status(CaptureStatus(
                bufferFree: Double(group(1)) ?? 0, bufferTotal: Double(group(2)) ?? 0,
                diskThreadHighPriority: group(3) == "x",
                overruns: Int(group(4)) ?? 0, xruns: Int(group(5)) ?? 0)))
            consumed = max(consumed, all.upperBound)
        }
        out = String(out[consumed...])
        if out.count > 4000 { out = String(out.suffix(1000)) }   // meters only: nothing to keep
        return events
    }

    /// The last row of each channel in the buffer, as levels; and where the last of them ends.
    private func readMeters() -> (levels: [ChannelMeter], end: String.Index)? {
        let full = NSRange(out.startIndex..., in: out)
        var rows: [Int: ChannelMeter] = [:]
        var end: String.Index?
        for match in Self.meterRow.matches(in: out, range: full) {
            guard let channel = Range(match.range(at: 1), in: out).flatMap({ Int(out[$0]) }),
                  let cells = Range(match.range(at: 2), in: out), let mark = Range(match.range(at: 3), in: out),
                  let all = Range(match.range, in: out) else { continue }
            let chars = Array(out[cells])
            // The bar is a run of "-" from the left; "*" is the peak the meter holds, which may be above it.
            let run = chars.prefix { $0 == "-" || $0 == "*" }.count
            let star = chars.firstIndex(of: "*").map { $0 + 1 } ?? run
            rows[channel] = ChannelMeter(level: Double(run) / 65, peak: Double(max(star, run)) / 65, clipped: out[mark] == "!")
            end = max(end ?? all.upperBound, all.upperBound)
        }
        // Timemachine, not recording yet: the row is the message "Press <Return> to start", of which the part drawn as
        // a bar comes before the yellow code.
        for match in Self.meterRowWaiting.matches(in: out, range: full) {
            guard let channel = Range(match.range(at: 1), in: out).flatMap({ Int(out[$0]) }),
                  let cells = Range(match.range(at: 2), in: out), let all = Range(match.range, in: out) else { continue }
            let level = Double(out[cells].count) / 65
            rows[channel] = ChannelMeter(level: level, peak: level, clipped: false)
            end = max(end ?? all.upperBound, all.upperBound)
        }
        guard let end, let last = rows.keys.max() else { return nil }
        return ((0...last).map { rows[$0] ?? .silent }, end)
    }

    /// Error output: one message per line.
    public func feedError(_ chunk: String) -> [CaptureEvent] {
        err += Self.clean(chunk)
        var events: [CaptureEvent] = []
        while let newline = err.firstIndex(of: "\n") {
            let line = String(err[..<newline]).trimmingCharacters(in: .whitespaces)
            err = String(err[err.index(after: newline)...])
            if let event = Self.event(forLine: line) { events.append(event) }
        }
        // jack_capture does not always end its last line (e.g. "Finished.").
        if err.contains("Finished.") { err = ""; events.append(.finished) }
        return events
    }

    static func event(forLine line: String) -> CaptureEvent? {
        guard !line.isEmpty else { return nil }
        func quoted() -> String? {
            guard let a = line.firstIndex(of: "\""), let b = line.lastIndex(of: "\""), a < b else { return nil }
            return String(line[line.index(after: a)..<b])
        }
        if line.hasPrefix(">>> Recording to"), let file = quoted() { return .recording(file: file) }
        if line.hasPrefix(">>> Waiting to start recording"), let file = quoted() { return .waitingToStart(file: file) }
        if line.hasPrefix(">>> Waiting for") { return .waitingForJack(String(line.dropFirst(">>> ".count))) }
        if line.hasPrefix(">>> Press <Ctrl-C>") { return nil }
        // "to last 179 seconds Press <Ctrl-C> to stop before that.": what -d announces, which the interface shows itself.
        if line.contains("to last"), line.contains("to stop before that") { return nil }
        if line == "Finished." { return .finished }
        return .message(line.hasPrefix(">>> ") ? String(line.dropFirst(4)) : line)
    }
}
