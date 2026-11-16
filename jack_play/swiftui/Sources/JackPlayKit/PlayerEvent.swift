// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum PlayerState: String, Equatable, Sendable {
    case paused, playing, ended
}

/// What `jack_play` tells the application.
public enum PlayerEvent: Equatable, Sendable {
    /// The program is ready: its ports exist and it waits for `play`.
    case ready(channels: Int, fileRate: Double, serverRate: Double, frames: Int64)
    /// Where it is in the file, in frames of the file.
    case position(frame: Int64, state: PlayerState)
    /// A line of information on its standard output ("jack client name: …").
    case message(String)
    /// A line on its standard error: a warning such as "disk thread late".
    case warning(String)
    /// The program has ended. `requested` is true when the application asked for it.
    case exited(status: Int32, requested: Bool)
}

/// Cuts what the program writes into lines and reads them. Data may arrive in pieces: a line is understood once
/// it is complete.
public struct PlayerLogParser: Sendable {
    private var pending = Data()
    private let isError: Bool

    /// - Parameter isError: true for the standard error, whose lines are all warnings.
    public init(isError: Bool = false) { self.isError = isError }

    public mutating func feed(_ data: Data) -> [PlayerEvent] {
        pending.append(data)
        var events = [PlayerEvent]()
        while let newline = pending.firstIndex(of: 0x0A) {
            let raw = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            let line = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if let event = Self.parse(line, isError: isError) { events.append(event) }
        }
        // A line that never ends must not grow without limit.
        if pending.count > 65_536 { pending.removeAll() }
        return events
    }

    static func parse(_ line: String, isError: Bool) -> PlayerEvent? {
        guard !line.isEmpty else { return nil }
        if isError { return .warning(line) }
        let words = line.split(separator: " ")
        if words.first == "ready", words.count == 5,
           let channels = Int(words[1]), let fileRate = Double(words[2]), let serverRate = Double(words[3]), let frames = Int64(words[4]) {
            return .ready(channels: channels, fileRate: fileRate, serverRate: serverRate, frames: frames)
        }
        if words.first == "pos", words.count == 3, let frame = Int64(words[1]), let state = PlayerState(rawValue: String(words[2])) {
            return .position(frame: frame, state: state)
        }
        return .message(line)
    }
}
